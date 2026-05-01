# Realtime Sync Verification Checklist

Use this checklist to verify that all major data mutations sync across devices linked to the same Google account.

## Preconditions

- Run the app on two devices: `Device A` and `Device B`.
- Sign in on both devices with the same Google account.
- Keep both devices online.
- Wait until initial bootstrap sync completes on both devices.

## Global Pass Criteria

- Any create/update/delete on `Device A` appears on `Device B` automatically.
- Server state updates in Supabase (`app_snapshots`, and `app_snapshot_chunks` when payload is large).
- No manual full refresh is required (normal screen reload is acceptable where UI caches local query results).

## Verification Matrix

Mark each item as Pass/Fail.

### 1) Products

- [ ] Add a new product on `Device A`.
  - Expected: product appears on `Device B`.
- [ ] Edit same product (price/name/qty) on `Device B`.
  - Expected: edits appear on `Device A`.
- [ ] Update warehouse stock for that product.
  - Expected: stock-related values reflect on the other device.

### 2) Invoices + Invoice Items

- [ ] Create a cash sale invoice on `Device A`.
  - Expected: invoice and items appear on `Device B`.
  - Expected: related product quantity change appears on both devices.
- [ ] Create a return invoice on `Device B`.
  - Expected: return appears on `Device A`.
  - Expected: inventory reversal reflects on both devices.

### 3) Cash Ledger

- [ ] Add a manual cash entry on `Device A` (deposit/withdrawal).
  - Expected: ledger entry appears on `Device B`.
- [ ] Create an invoice that affects cash (cash sale or collection).
  - Expected: generated cash movement appears on the other device.

### 4) Customers

- [ ] Add a customer on `Device A`.
  - Expected: customer appears on `Device B`.
- [ ] Edit customer phone/notes on `Device B`.
  - Expected: edit appears on `Device A`.
- [ ] Delete that customer on one device.
  - Expected: customer disappears on the other device.

### 5) Parked Sales

- [ ] Park a sale on `Device A`.
  - Expected: parked entry appears on `Device B`.
- [ ] Resume and update parked sale on `Device B`.
  - Expected: latest parked state appears on `Device A`.
- [ ] Delete parked sale on one device.
  - Expected: deleted on the other device.

### 6) Stock Vouchers

- [ ] Commit an inbound stock voucher on `Device A`.
  - Expected: voucher and inventory changes appear on `Device B`.
- [ ] Commit an outbound stock voucher on `Device B`.
  - Expected: voucher and inventory changes appear on `Device A`.
- [ ] Commit a transfer stock voucher.
  - Expected: source/destination warehouse quantities match on both devices.

### 7) Suppliers + AP

- [ ] Add a supplier on `Device A`.
  - Expected: supplier appears on `Device B`.
- [ ] Add supplier bill on `Device B`.
  - Expected: bill appears on `Device A`.
- [ ] Record supplier payout on one device.
  - Expected: payout appears on other device.
  - Expected: related receipt/cash impact appears on both devices.
- [ ] Delete supplier payout (reversing cash).
  - Expected: reversal result appears on other device.

## Supabase Spot Checks (Optional but recommended)

Run the helper SQL in `tool/sync_verification_queries.sql`:

- Confirm latest row in `app_snapshots` for your `user_id` is updating.
- For heavy payload runs, confirm rows exist in `app_snapshot_chunks`.
- Confirm both devices exist in `account_devices` and `last_seen_at` updates.

## Stress Test (Large Dataset)

- [ ] Add 50 products + 10 invoices on `Device A`.
- [ ] Confirm `Device B` catches up correctly.
- [ ] Edit 5 products + add 1 invoice on `Device B`.
- [ ] Confirm `Device A` receives all changes.
- [ ] Delete one product and confirm propagation.
- [ ] Verify no sync crash and no stuck stale state.

## License-Constrained Sync Behavior (Critical)

- [ ] Device B في `Restricted Mode`.
      Device A يرفع snapshot جديد.
      Expected:
      - Device B يستقبل البيانات (Pull يعمل).
      - Device B لا يرفع أي تغييرات محلية (Push محجوب بسبب Preflight).

## Failure Log Template

If any check fails, record:

- Step:
- Device where change was made:
- Expected result:
- Actual result:
- Delay observed:
- Supabase snapshot/chunk status:
- Screenshot/log excerpt:
