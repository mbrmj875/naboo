-- جدول قيود الصندوق على السيرفر (مرحلة المصروفات + الطابور).
-- نفّذ مرة واحدة قبل استدعاء الدالة، أو سيُنشأ تلقائياً بـ IF NOT EXISTS.
CREATE TABLE IF NOT EXISTS public.cash_ledger (
  global_id text PRIMARY KEY,
  tenant_id integer NOT NULL DEFAULT 1,
  transaction_type text NOT NULL,
  amount numeric NOT NULL,
  amount_fils integer NOT NULL DEFAULT 0,
  description text,
  invoice_id integer,
  work_shift_id integer,
  expense_global_id text,
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_cash_ledger_tenant ON public.cash_ledger(tenant_id);

-- المرحلة 3.1: عملاء وموردون (Master Data + طابور).
CREATE TABLE IF NOT EXISTS public.customers (
  global_id text PRIMARY KEY,
  tenant_id integer NOT NULL DEFAULT 1,
  name text NOT NULL,
  phone text,
  email text,
  address text,
  notes text,
  balance numeric NOT NULL DEFAULT 0,
  loyalty_points integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_customers_tenant ON public.customers(tenant_id);

CREATE TABLE IF NOT EXISTS public.suppliers (
  global_id text PRIMARY KEY,
  tenant_id integer NOT NULL DEFAULT 1,
  name text NOT NULL,
  phone text,
  notes text,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_suppliers_tenant ON public.suppliers(tenant_id);

-- TODO(security): عند تفعيل SELECT/INSERT/UPDATE مباشرة من عميل Supabase على public.cash_ledger،
-- فعّل RLS وقيود tenant_id (مثل expenses) — لا تعتمد على SECURITY DEFINER وحدها كحماية للقراءة من العميل.

-- Drop existing function if any
DROP FUNCTION IF EXISTS rpc_process_expense_mutations(jsonb);

CREATE OR REPLACE FUNCTION rpc_process_expense_mutations(mutations_json jsonb)
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
BEGIN
    FOR mutation IN SELECT * FROM jsonb_array_elements(mutations_json)
    LOOP
        mutation_id := mutation->>'_mutation_id';
        entity_type := mutation->>'_entity_type';
        operation := mutation->>'_operation';

        IF entity_type = 'expense' THEN
            v_global_id := mutation->>'global_id';
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
                        expense_global_id = EXCLUDED.expense_global_id,
                        updated_at = EXCLUDED.updated_at
                    WHERE cash_ledger.updated_at < EXCLUDED.updated_at;
                ELSIF NOT v_should_ledger THEN
                    DELETE FROM cash_ledger WHERE global_id = (v_global_id || '_cash');
                END IF;
            END IF;
        END IF;

        IF entity_type = 'customer' THEN
            v_global_id := mutation->>'global_id';
            v_updated_at := (mutation->>'updatedAt')::timestamptz;

            IF operation = 'DELETE' THEN
                IF v_updated_at IS NULL THEN
                    DELETE FROM customers WHERE global_id = v_global_id;
                ELSE
                    SELECT updated_at INTO existing_updated_at FROM customers WHERE global_id = v_global_id;
                    IF existing_updated_at IS NULL OR existing_updated_at <= v_updated_at THEN
                        DELETE FROM customers WHERE global_id = v_global_id;
                    END IF;
                END IF;

            ELSIF operation IN ('INSERT', 'UPDATE') THEN
                INSERT INTO customers (
                    global_id,
                    tenant_id,
                    name,
                    phone,
                    email,
                    address,
                    notes,
                    balance,
                    loyalty_points,
                    created_at,
                    updated_at
                ) VALUES (
                    v_global_id,
                    (mutation->>'tenantId')::integer,
                    mutation->>'name',
                    mutation->>'phone',
                    mutation->>'email',
                    mutation->>'address',
                    mutation->>'notes',
                    (mutation->>'balance')::numeric,
                    COALESCE((mutation->>'loyaltyPoints')::integer, 0),
                    (mutation->>'createdAt')::timestamptz,
                    v_updated_at
                )
                ON CONFLICT (global_id) DO UPDATE SET
                    tenant_id = EXCLUDED.tenant_id,
                    name = EXCLUDED.name,
                    phone = EXCLUDED.phone,
                    email = EXCLUDED.email,
                    address = EXCLUDED.address,
                    notes = EXCLUDED.notes,
                    balance = EXCLUDED.balance,
                    loyalty_points = EXCLUDED.loyalty_points,
                    updated_at = EXCLUDED.updated_at
                WHERE customers.updated_at < EXCLUDED.updated_at;
            END IF;
        END IF;

        IF entity_type = 'supplier' THEN
            v_global_id := mutation->>'global_id';
            v_updated_at := (mutation->>'updatedAt')::timestamptz;

            IF operation = 'DELETE' THEN
                IF v_updated_at IS NULL THEN
                    DELETE FROM suppliers WHERE global_id = v_global_id;
                ELSE
                    SELECT updated_at INTO existing_updated_at FROM suppliers WHERE global_id = v_global_id;
                    IF existing_updated_at IS NULL OR existing_updated_at <= v_updated_at THEN
                        DELETE FROM suppliers WHERE global_id = v_global_id;
                    END IF;
                END IF;

            ELSIF operation IN ('INSERT', 'UPDATE') THEN
                INSERT INTO suppliers (
                    global_id,
                    tenant_id,
                    name,
                    phone,
                    notes,
                    is_active,
                    created_at,
                    updated_at
                ) VALUES (
                    v_global_id,
                    (mutation->>'tenantId')::integer,
                    mutation->>'name',
                    mutation->>'phone',
                    mutation->>'notes',
                    (COALESCE((mutation->>'isActive')::integer, 1) <> 0),
                    (mutation->>'createdAt')::timestamptz,
                    v_updated_at
                )
                ON CONFLICT (global_id) DO UPDATE SET
                    tenant_id = EXCLUDED.tenant_id,
                    name = EXCLUDED.name,
                    phone = EXCLUDED.phone,
                    notes = EXCLUDED.notes,
                    is_active = EXCLUDED.is_active,
                    updated_at = EXCLUDED.updated_at
                WHERE suppliers.updated_at < EXCLUDED.updated_at;
            END IF;
        END IF;

        IF entity_type = 'expense_category' THEN
            v_global_id := mutation->>'global_id';
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

    END LOOP;
END;
$$;
