import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { computeOperationHash } from "./field-hash";

describe("field-hash idempotency keys", () => {
  it("update_visit includes visitId in hash", () => {
    const payload = {
      shop_name: "محل",
      owner_name: "أحمد",
      interest: "warm",
      location_source: "gps",
      lat: 30.5,
      lng: 47.8,
    };
    const a = computeOperationHash("update_visit", payload, "11111111-1111-1111-1111-111111111111");
    const b = computeOperationHash("update_visit", payload, "22222222-2222-2222-2222-222222222222");
    assert.notEqual(a, b);
  });
});
