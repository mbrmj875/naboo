# Sync E2E Test Plan (A/B/Third Device)

This plan validates end-to-end sync reliability for:
- Device A push -> server
- Device B pull/merge -> push back
- Delete propagation
- Device registration limit enforcement
- Large payload chunking behavior

## Preconditions

- Google OAuth works and both devices can sign in with the same account.
- Supabase SQL migrations already applied from `supabase_sync_setup.sql`.
- App build contains latest sync implementation.

## Test Account

- Use one fixed Google account for all steps.
- Optional: clear app data before test on each device.

## Step 1: Baseline on Device A

1. Sign in on Device A.
2. Create:
   - 50 products
   - 10 invoices
3. Trigger sync (`Sync now` or wait auto cycle).
4. In Supabase, run section **2** and **3** from:
   - `tool/sync_verification_queries.sql`
5. Expected:
   - `app_snapshots.updated_at` updated recently.
   - If payload large, `chunked=true` and chunks exist.

## Step 2: Pull on Device B

1. Sign in using same Google account on Device B.
2. Wait one sync cycle or use `Sync now`.
3. Verify in app:
   - products count ~= 50
   - invoices count ~= 10
4. Expected: Device B receives data created on A.

## Step 3: Edit from Device B and return to A

1. On Device B:
   - Update 3 existing products.
   - Create 1 new invoice.
2. Trigger sync.
3. On Device A:
   - Trigger sync.
   - Verify product edits arrived.
   - Verify new invoice exists.

## Step 4: Delete propagation

1. On Device A:
   - Delete 1 product (or another business record).
2. Trigger sync on A then B.
3. Verify deleted record disappears on B after sync.

## Step 5: Device tracking and limit

1. In Supabase run section **4** from SQL script.
2. Expected:
   - `account_devices` has both A and B.
   - `last_seen_at` updates after each sync/login.
3. Try login from Device C (same account) while plan=basic (2 devices).
4. Expected:
   - login blocked with clear message indicating device limit reached.

## Step 6: Stability under repeated sync

1. On both A/B, trigger sync repeatedly for 5-10 minutes.
2. No crash/no endless conflict loops.
3. `updated_at` keeps advancing only when data changes.

## Failure signals to capture

- Error message shown in-app.
- Last 30 lines from app logs.
- Output from SQL sections 2/3/4/5.
- Which step failed and on which device.

## Pass criteria

- A -> server -> B works.
- B edits -> server -> A works.
- Deletes propagate.
- Device limit enforced.
- No sync-related crashes.
- For large payloads: chunk data exists and integrity check is OK.
