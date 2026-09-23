import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { distanceBetween, geohashForLocation, geohashQueryBounds } from "geofire-common";
import { describe, expect, it } from "vitest";
import { ROOT, contract } from "./helpers";

const vectors = JSON.parse(readFileSync(resolve(ROOT, "shared", "geohash-vectors.json"), "utf8"));

// shared/geohash-vectors.json, iOS tarafındaki Geohash testlerinin referansıdır.
// Bu test dosyanın gerçekten geofire-common (Firebase'in resmi geo sorgu mantığı) ile
// aynı sonuçları verdiğini doğrular.
describe("geohash referans değerleri", () => {
  it("encode değerleri geofire-common ile aynı", () => {
    for (const v of vectors.encode) {
      expect(geohashForLocation([v.lat, v.lng], v.precision), v.name).toBe(v.geohash);
    }
  });

  it("sorgu aralıkları geofire-common ile aynı", () => {
    for (const v of vectors.queryBounds) {
      expect(geohashQueryBounds([v.lat, v.lng], v.radiusMeters), `${v.name} @ ${v.radiusMeters} m`).toEqual(v.bounds);
    }
  });

  it("mesafeler geofire-common ile aynı", () => {
    for (const v of vectors.distances) {
      expect(distanceBetween(v.from, v.to) * 1000).toBeCloseTo(v.meters, 6);
    }
  });
});

describe("paylaşılan sözleşme", () => {
  it("işaretler istemcinin kullandığı hassasiyette geohash'lenir", () => {
    expect(vectors.encode.every((v: { geohash: string }) => v.geohash.length === contract.geohashPrecision)).toBe(true);
  });

  it("kurallardaki süreler sözleşmeyle aynı", () => {
    const rules = readFileSync(resolve(ROOT, "firebase", "firestore.rules"), "utf8");
    for (const [need, { lifetimeHours }] of Object.entries(contract.needs)) {
      expect(rules, need).toMatch(new RegExp(`'${need}': ${lifetimeHours}\\b`));
    }
    expect(rules).toContain(`duration.value(${contract.claimHours}, 'h')`);
    expect(rules).toContain(`duration.value(${contract.retentionDays}, 'd')`);
    expect(rules).toContain(`duration.value(${contract.maxBackdateHours}, 'h')`);
    expect(rules).toContain(`duration.value(${contract.clockSkewMinutes}, 'm')`);
    expect(rules).toContain(`after.goneReports.size() >= ${contract.goneThreshold}`);
  });
});
