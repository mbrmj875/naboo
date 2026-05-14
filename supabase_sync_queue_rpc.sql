-- جدول قيود الصندوق على السيرفر
CREATE TABLE IF NOT EXISTS public.cash_ledger (
  global_id text PRIMARY KEY,
  tenant_id integer NOT NULL DEFAULT 1,
  transaction_type text NOT NULL,
  amount numeric NOT NULL,
  amount_fils integer NOT NULL DEFAULT 0,
  description text,
  invoice_id integer,
  work_shift_id integer,
  work_shift_global_id text,
  expense_global_id text,
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_cash_ledger_tenant ON public.cash_ledger(tenant_id);

-- تأكد من إضافة عمود work_shift_global_id للنسخ القديمة من الجدول
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='cash_ledger' AND column_name='work_shift_global_id') THEN
    ALTER TABLE public.cash_ledger ADD COLUMN work_shift_global_id text;
  END IF;
END $$;

-- جدول الورديات على السيرفر
CREATE TABLE IF NOT EXISTS public.work_shifts (
  global_id text PRIMARY KEY,
  tenant_id integer NOT NULL DEFAULT 1,
  session_user_id integer NOT NULL,
  shift_staff_user_id integer,
  opened_at timestamptz NOT NULL,
  closed_at timestamptz,
  system_balance_at_open numeric NOT NULL,
  declared_physical_cash numeric NOT NULL,
  added_cash_at_open numeric NOT NULL DEFAULT 0,
  shift_staff_name text NOT NULL,
  shift_staff_pin text NOT NULL,
  declared_closing_cash numeric,
  system_balance_at_close numeric,
  withdrawn_at_close numeric,
  declared_cash_in_box_at_close numeric,
  updated_at timestamptz NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_work_shifts_tenant ON public.work_shifts(tenant_id);

-- TODO(security): عند تفعيل SELECT/INSERT/UPDATE مباشرة من عميل Supabase على public.cash_ledger و public.work_shifts
-- فعّل RLS وقيود tenant_id (مثل expenses) — لا تعتمد على SECURITY DEFINER وحدها كحماية للقراءة من العميل.

-- إزالة الدالة القديمة
DROP FUNCTION IF EXISTS rpc_process_expense_mutations(jsonb);
-- إزالة أي إصدار قديم من الدالة الجديدة لو وجد
DROP FUNCTION IF EXISTS rpc_process_sync_queue(jsonb);

-- =========================================================================
-- 0. Realtime Delta Sync (Phase 6)
-- =========================================================================

-- جدول الإشعارات اللحظية
CREATE TABLE IF NOT EXISTS public.sync_notifications (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  sender_device_id text NOT NULL,
  entity_type text NOT NULL,
  global_id text NOT NULL,
  operation text NOT NULL,
  created_at timestamptz DEFAULT now()
);

-- فهرس لتسريع استعلامات Realtime
CREATE INDEX IF NOT EXISTS idx_sync_notif_user ON public.sync_notifications(user_id);

-- تفعيل Row Level Security (RLS)
ALTER TABLE public.sync_notifications ENABLE ROW LEVEL SECURITY;

-- سياسة رؤية: المستخدم يرى إشعاراته فقط
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'sync_notifications' AND policyname = 'Users can view their own notifications'
    ) THEN
        CREATE POLICY "Users can view their own notifications"
            ON public.sync_notifications FOR SELECT
            USING (auth.uid() = user_id);
    END IF;
END $$;

-- تفعيل Realtime على هذا الجدول فقط (يحتاج تنفيذ من واجهة Supabase أحياناً، ولكن هذا الكود يحاول تفعيله)
-- ALTER PUBLICATION supabase_realtime ADD TABLE sync_notifications;

-- (اختياري) تنظيف تلقائي عبر pg_cron إذا كان مفعّلاً
-- SELECT cron.schedule('cleanup_sync_notifications', '0 * * * *', $$ DELETE FROM sync_notifications WHERE created_at < now() - interval '24 hours'; $$);


-- الدالة الموحدة لمعالجة الطابور
-- 15. Financial Obligations (Phase 5.5)
CREATE TABLE IF NOT EXISTS public.installment_plans (
  global_id text PRIMARY KEY,
  invoice_global_id text,
  customer_global_id text,
  customer_name text,
  total_amount numeric,
  paid_amount numeric,
  number_of_installments integer,
  updated_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.installments (
  global_id text PRIMARY KEY,
  plan_global_id text REFERENCES public.installment_plans(global_id) ON DELETE CASCADE,
  due_date timestamptz,
  amount numeric,
  paid integer,
  paid_date timestamptz,
  updated_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.customer_debt_payments (
  global_id text PRIMARY KEY,
  customer_global_id text REFERENCES public.customers(global_id),
  customer_name_snapshot text NOT NULL,
  amount numeric NOT NULL,
  debt_before numeric NOT NULL,
  debt_after numeric NOT NULL,
  created_at timestamptz NOT NULL,
  created_by_user_name text,
  note text,
  updated_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.supplier_bills (
  global_id text PRIMARY KEY,
  supplier_global_id text REFERENCES public.suppliers(global_id),
  their_reference text,
  their_bill_date timestamptz,
  amount numeric NOT NULL,
  note text,
  image_path text,
  created_at timestamptz NOT NULL,
  created_by_user_name text,
  updated_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.supplier_payouts (
  global_id text PRIMARY KEY,
  supplier_global_id text REFERENCES public.suppliers(global_id),
  amount numeric NOT NULL,
  note text,
  created_at timestamptz NOT NULL,
  created_by_user_name text,
  affects_cash integer NOT NULL DEFAULT 1,
  receipt_invoice_id integer,
  updated_at timestamptz DEFAULT now()
);

CREATE OR REPLACE FUNCTION rpc_process_sync_queue(mutations_json jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    mutation jsonb;
    entity_type text;
    operation text;
    mutation_id text;
    v_global_id text;
    v_updated_at timestamp with time zone;
    existing_updated_at timestamp with time zone;
    v_cat_id integer;
    v_should_ledger boolean;
    cle jsonb;
    v_cash_updated timestamptz;
    v_sender_device_id text;
    v_user_id uuid;
BEGIN
    -- الحصول على معرف المستخدم الحالي الذي يستدعي الدالة
    v_user_id := auth.uid();

    FOR mutation IN SELECT * FROM jsonb_array_elements(mutations_json)
    LOOP
        mutation_id := mutation->>'_mutation_id';
        entity_type := mutation->>'_entity_type';
        operation := mutation->>'_operation';
        v_global_id := mutation->>'global_id';
        v_sender_device_id := mutation->>'_device_id';

        -- If the client didn't send a device ID, use a placeholder so we don't break
        IF v_sender_device_id IS NULL OR trim(v_sender_device_id) = '' THEN
            v_sender_device_id := 'unknown_device';
        END IF;


        -- =========================================================================
        -- 1. EXPENSES
        -- =========================================================================
        IF entity_type = 'expense' THEN
            v_updated_at := (mutation->>'updatedAt')::timestamptz;

            IF operation = 'DELETE' THEN
                DELETE FROM cash_ledger WHERE global_id = (v_global_id || '_cash');
                IF v_updated_at IS NULL THEN
                    DELETE FROM expenses WHERE global_id = v_global_id;
                ELSE
                    SELECT updated_at INTO existing_updated_at FROM expenses WHERE global_id = v_global_id;
                    IF existing_updated_at IS NULL OR existing_updated_at <= v_updated_at THEN
                        DELETE FROM expenses WHERE global_id = v_global_id;
                    END IF;
                END IF;

            ELSIF operation IN ('INSERT', 'UPDATE') THEN
                v_cat_id := NULL;
                SELECT id INTO v_cat_id
                FROM expense_categories
                WHERE global_id = (mutation->>'category_global_id')
                  AND tenant_id = (mutation->>'tenantId')::integer
                LIMIT 1;

                IF v_cat_id IS NULL THEN
                    CONTINUE;
                END IF;

                INSERT INTO expenses (
                    global_id,
                    tenant_id,
                    category_id,
                    amount,
                    occurred_at,
                    status,
                    description,
                    employee_user_id,
                    is_recurring,
                    recurring_day,
                    recurring_origin_id,
                    attachment_path,
                    affects_cash,
                    invoice_ref,
                    landlord_or_property,
                    tax_kind,
                    created_at,
                    updated_at
                ) VALUES (
                    v_global_id,
                    (mutation->>'tenantId')::integer,
                    v_cat_id,
                    (mutation->>'amount')::numeric,
                    (mutation->>'occurredAt')::timestamptz,
                    mutation->>'status',
                    mutation->>'description',
                    NULLIF(trim(mutation->>'employeeUserId'), '')::integer,
                    (COALESCE((mutation->>'isRecurring')::integer, 0) <> 0),
                    NULLIF(trim(mutation->>'recurringDay'), '')::integer,
                    NULLIF(trim(mutation->>'recurringOriginId'), '')::integer,
                    mutation->>'attachmentPath',
                    (COALESCE((mutation->>'affectsCash')::integer, 1) <> 0),
                    mutation->>'invoiceRef',
                    mutation->>'landlordOrProperty',
                    mutation->>'taxKind',
                    (mutation->>'createdAt')::timestamptz,
                    v_updated_at
                )
                ON CONFLICT (global_id) DO UPDATE SET
                    tenant_id = EXCLUDED.tenant_id,
                    category_id = EXCLUDED.category_id,
                    amount = EXCLUDED.amount,
                    occurred_at = EXCLUDED.occurred_at,
                    status = EXCLUDED.status,
                    description = EXCLUDED.description,
                    employee_user_id = EXCLUDED.employee_user_id,
                    is_recurring = EXCLUDED.is_recurring,
                    recurring_day = EXCLUDED.recurring_day,
                    recurring_origin_id = EXCLUDED.recurring_origin_id,
                    attachment_path = EXCLUDED.attachment_path,
                    affects_cash = EXCLUDED.affects_cash,
                    invoice_ref = EXCLUDED.invoice_ref,
                    landlord_or_property = EXCLUDED.landlord_or_property,
                    tax_kind = EXCLUDED.tax_kind,
                    updated_at = EXCLUDED.updated_at
                WHERE expenses.updated_at < EXCLUDED.updated_at;

                v_should_ledger := (mutation->>'status' = 'paid')
                    AND (COALESCE((mutation->>'affectsCash')::integer, 1) <> 0);
                cle := mutation->'cash_ledger_entry';

                IF v_should_ledger AND cle IS NOT NULL AND jsonb_typeof(cle) = 'object' THEN
                    v_cash_updated := (cle->>'updatedAt')::timestamptz;
                    INSERT INTO cash_ledger (
                        global_id,
                        tenant_id,
                        transaction_type,
                        amount,
                        amount_fils,
                        description,
                        invoice_id,
                        work_shift_id,
                        work_shift_global_id,
                        expense_global_id,
                        created_at,
                        updated_at
                    ) VALUES (
                        cle->>'global_id',
                        (cle->>'tenantId')::integer,
                        cle->>'transactionType',
                        (cle->>'amount')::numeric,
                        COALESCE((cle->>'amountFils')::integer, 0),
                        cle->>'description',
                        NULLIF(trim(cle->>'invoiceId'), '')::integer,
                        NULLIF(trim(cle->>'workShiftId'), '')::integer,
                        NULLIF(trim(cle->>'work_shift_global_id'), ''),
                        COALESCE(NULLIF(trim(cle->>'expense_global_id'), ''), v_global_id),
                        (cle->>'createdAt')::timestamptz,
                        v_cash_updated
                    )
                    ON CONFLICT (global_id) DO UPDATE SET
                        tenant_id = EXCLUDED.tenant_id,
                        transaction_type = EXCLUDED.transaction_type,
                        amount = EXCLUDED.amount,
                        amount_fils = EXCLUDED.amount_fils,
                        description = EXCLUDED.description,
                        invoice_id = EXCLUDED.invoice_id,
                        work_shift_id = EXCLUDED.work_shift_id,
                        work_shift_global_id = EXCLUDED.work_shift_global_id,
                        expense_global_id = EXCLUDED.expense_global_id,
                        updated_at = EXCLUDED.updated_at
                    WHERE cash_ledger.updated_at < EXCLUDED.updated_at;
                ELSIF NOT v_should_ledger THEN
                    DELETE FROM cash_ledger WHERE global_id = (v_global_id || '_cash');
                END IF;
            END IF;
        END IF;

        -- =========================================================================
        -- 2. EXPENSE CATEGORIES
        -- =========================================================================
        IF entity_type = 'expense_category' THEN
            v_updated_at := (mutation->>'createdAt')::timestamptz;

            IF operation = 'DELETE' THEN
                DELETE FROM expense_categories WHERE global_id = v_global_id;
            ELSIF operation IN ('INSERT', 'UPDATE') THEN
                INSERT INTO expense_categories (
                    global_id,
                    tenant_id,
                    name,
                    sort_order,
                    is_active,
                    created_at
                ) VALUES (
                    v_global_id,
                    (mutation->>'tenantId')::integer,
                    mutation->>'name',
                    (mutation->>'sortOrder')::integer,
                    (COALESCE((mutation->>'isActive')::integer, 1) <> 0),
                    (mutation->>'createdAt')::timestamptz
                )
                ON CONFLICT (global_id) DO UPDATE SET
                    tenant_id = EXCLUDED.tenant_id,
                    name = EXCLUDED.name,
                    sort_order = EXCLUDED.sort_order,
                    is_active = EXCLUDED.is_active
                WHERE expense_categories.created_at < EXCLUDED.created_at;
            END IF;
        END IF;

        -- =========================================================================
        -- 3. WORK SHIFTS
        -- =========================================================================
        IF entity_type = 'work_shift' THEN
            v_updated_at := (mutation->>'updatedAt')::timestamptz;

            IF operation = 'DELETE' THEN
                -- Not commonly used, but supported for completeness
                DELETE FROM work_shifts WHERE global_id = v_global_id;
            ELSIF operation IN ('INSERT', 'UPDATE') THEN
                INSERT INTO work_shifts (
                    global_id,
                    tenant_id,
                    session_user_id,
                    shift_staff_user_id,
                    opened_at,
                    closed_at,
                    system_balance_at_open,
                    declared_physical_cash,
                    added_cash_at_open,
                    shift_staff_name,
                    shift_staff_pin,
                    declared_closing_cash,
                    system_balance_at_close,
                    withdrawn_at_close,
                    declared_cash_in_box_at_close,
                    updated_at
                ) VALUES (
                    v_global_id,
                    (mutation->>'tenantId')::integer,
                    (mutation->>'sessionUserId')::integer,
                    NULLIF(trim(mutation->>'shiftStaffUserId'), '')::integer,
                    (mutation->>'openedAt')::timestamptz,
                    (NULLIF(trim(mutation->>'closedAt'), ''))::timestamptz,
                    (mutation->>'systemBalanceAtOpen')::numeric,
                    (mutation->>'declaredPhysicalCash')::numeric,
                    (mutation->>'addedCashAtOpen')::numeric,
                    mutation->>'shiftStaffName',
                    mutation->>'shiftStaffPin',
                    (NULLIF(trim(mutation->>'declaredClosingCash'), ''))::numeric,
                    (NULLIF(trim(mutation->>'systemBalanceAtClose'), ''))::numeric,
                    (NULLIF(trim(mutation->>'withdrawnAtClose'), ''))::numeric,
                    (NULLIF(trim(mutation->>'declaredCashInBoxAtClose'), ''))::numeric,
                    v_updated_at
                )
                ON CONFLICT (global_id) DO UPDATE SET
                    tenant_id = EXCLUDED.tenant_id,
                    session_user_id = EXCLUDED.session_user_id,
                    shift_staff_user_id = EXCLUDED.shift_staff_user_id,
                    opened_at = EXCLUDED.opened_at,
                    closed_at = EXCLUDED.closed_at,
                    system_balance_at_open = EXCLUDED.system_balance_at_open,
                    declared_physical_cash = EXCLUDED.declared_physical_cash,
                    added_cash_at_open = EXCLUDED.added_cash_at_open,
                    shift_staff_name = EXCLUDED.shift_staff_name,
                    shift_staff_pin = EXCLUDED.shift_staff_pin,
                    declared_closing_cash = EXCLUDED.declared_closing_cash,
                    system_balance_at_close = EXCLUDED.system_balance_at_close,
                    withdrawn_at_close = EXCLUDED.withdrawn_at_close,
                    declared_cash_in_box_at_close = EXCLUDED.declared_cash_in_box_at_close,
                    updated_at = EXCLUDED.updated_at
                WHERE work_shifts.updated_at < EXCLUDED.updated_at;
            END IF;
        END IF;

        -- =========================================================================
        -- 4. STANDALONE CASH LEDGER ENTRIES
        -- =========================================================================
        IF entity_type = 'cash_ledger' THEN
            v_updated_at := (mutation->>'updatedAt')::timestamptz;

            IF operation = 'DELETE' THEN
                DELETE FROM cash_ledger WHERE global_id = v_global_id;
            ELSIF operation IN ('INSERT', 'UPDATE') THEN
                INSERT INTO cash_ledger (
                    global_id,
                    tenant_id,
                    transaction_type,
                    amount,
                    amount_fils,
                    description,
                    invoice_id,
                    work_shift_id,
                    work_shift_global_id,
                    expense_global_id,
                    created_at,
                    updated_at
                ) VALUES (
                    v_global_id,
                    (mutation->>'tenantId')::integer,
                    mutation->>'transactionType',
                    (mutation->>'amount')::numeric,
                    COALESCE((mutation->>'amountFils')::integer, 0),
                    mutation->>'description',
                    NULLIF(trim(mutation->>'invoiceId'), '')::integer,
                    NULLIF(trim(mutation->>'workShiftId'), '')::integer,
                    NULLIF(trim(mutation->>'work_shift_global_id'), ''),
                    NULLIF(trim(mutation->>'expense_global_id'), ''),
                    (mutation->>'createdAt')::timestamptz,
                    v_updated_at
                )
                ON CONFLICT (global_id) DO UPDATE SET
                    tenant_id = EXCLUDED.tenant_id,
                    transaction_type = EXCLUDED.transaction_type,
                    amount = EXCLUDED.amount,
                    amount_fils = EXCLUDED.amount_fils,
                    description = EXCLUDED.description,
                    invoice_id = EXCLUDED.invoice_id,
                    work_shift_id = EXCLUDED.work_shift_id,
                    work_shift_global_id = EXCLUDED.work_shift_global_id,
                    expense_global_id = EXCLUDED.expense_global_id,
                    updated_at = EXCLUDED.updated_at
                WHERE cash_ledger.updated_at < EXCLUDED.updated_at;
            END IF;
        END IF;


        -- =========================================================================
        -- الإشعار الفوري (Realtime Notification)
        -- =========================================================================
        -- بعد المعالجة الناجحة للكيان، ندرج إشعاراً للأجهزة الأخرى
        -- فقط إذا تم التعرف على المستخدم الحالي
        IF v_user_id IS NOT NULL THEN
            INSERT INTO public.sync_notifications (
                user_id,
                sender_device_id,
                entity_type,
                global_id,
                operation
            ) VALUES (
                v_user_id,
                v_sender_device_id,
                entity_type,
                v_global_id,
                operation
            );
        END IF;

    END LOOP;
END;
$$;
