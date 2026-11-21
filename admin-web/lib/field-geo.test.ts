import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  BASRA_CENTER,
  checkVisitGeo,
  geoDistanceKm,
  isWithinBasraGovernorate,
} from "./field-geo";
import { computeOperationHash } from "./field-hash";

describe("field-geo", () => {
  it("distance near center is small", () => {
    const d = geoDistanceKm(
      BASRA_CENTER.lat,
      BASRA_CENTER.lng,
      BASRA_CENTER.lat + 0.01,
      BASRA_CENTER.lng,
    );
    assert.ok(d < 2);
  });

  it("rejects coords outside governorate", () => {
    assert.equal(isWithinBasraGovernorate(33.3, 44.4), false);
    const r = checkVisitGeo({ lat: 33.3, lng: 44.4 });
    assert.equal(r.ok, false);
    assert.equal(r.code, "OUT_OF_GOVERNORATE");
  });

  it("requires confirm beyond 15km", () => {
    // ~20km north of center roughly
    const lat = BASRA_CENTER.lat + 0.2;
    const lng = BASRA_CENTER.lng;
    const r = checkVisitGeo({ lat, lng, geoConfirmed: false });
    assert.equal(r.ok, false);
    assert.equal(r.code, "GEO_CONFIRM_REQUIRED");
    const ok = checkVisitGeo({ lat, lng, geoConfirmed: true });
    assert.equal(ok.ok, true);
    assert.equal(ok.geoWarning, "out_of_basra");
  });
});

describe("field-hash", () => {
  it("is stable for same payload", () => {
    const a = computeOperationHash("create_visit", {
      shop_name: "محل",
      owner_name: "أحمد",
      phone: null,
      lat: 30.5,
      lng: 47.8,
      interest: "warm",
      notes: null,
      location_source: "gps",
    });
    const b = computeOperationHash("create_visit", {
      shop_name: "محل",
      owner_name: "أحمد",
      phone: null,
      lat: 30.5,
      lng: 47.8,
      interest: "warm",
      notes: null,
      location_source: "gps",
    });
    assert.equal(a, b);
    assert.equal(a.length, 64);
  });

  it("changes when interest changes", () => {
    const base = {
      shop_name: "محل",
      owner_name: "أحمد",
      phone: null,
      lat: 30.5,
      lng: 47.8,
      notes: null,
      location_source: "gps" as const,
    };
    const a = computeOperationHash("create_visit", {
      ...base,
      interest: "warm",
    });
    const b = computeOperationHash("create_visit", {
      ...base,
      interest: "purchased",
    });
    assert.notEqual(a, b);
  });
});
