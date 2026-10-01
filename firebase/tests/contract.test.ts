import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { resolve } from "node:path";
import { distanceBetween, geohashForLocation, geohashQueryBounds } from "geofire-common";
import { describe, expect, it } from "vitest";
import { ROOT, contract } from "./helpers";

const vectors = JSON.parse(readFileSync(resolve(ROOT, "shared", "geohash-vectors.json"), "utf8"));

const readRules = () => readFileSync(resolve(ROOT, "firebase", "firestore.rules"), "utf8");
const list = (values: string[]) => `[${values.map((v) => `'${v}'`).join(", ")}]`;

/** Kurallardaki `function name() { return { 'need': N, ... }; }` tablosu. */
function needTable(rules: string, name: string): Record<string, number> {
  const body = rules.match(new RegExp(`function ${name}\\(\\) \\{\\s*return \\{([^}]*)\\};\\s*\\}`))?.[1];
  expect(body, `function ${name}() bulunamadı`).toBeDefined();
  return Object.fromEntries([...body!.matchAll(/'(\w+)': (\d+)/g)].map(([, need, value]) => [need, Number(value)]));
}

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

  it("kurallardaki süreler ve sınırlar sözleşmeyle aynı", () => {
    const rules = readRules();
    expect(needTable(rules, "lifetimeHours")).toEqual(
      Object.fromEntries(Object.entries(contract.needs).map(([need, { lifetimeHours }]) => [need, lifetimeHours])),
    );
    for (const constant of [
      `function claimDuration() { return duration.value(${contract.claimHours}, 'h'); }`,
      `function retention() { return duration.value(${contract.retentionDays}, 'd'); }`,
      `function maxBackdate() { return duration.value(${contract.maxBackdateHours}, 'h'); }`,
      `function skew() { return duration.value(${contract.clockSkewMinutes}, 'm'); }`,
      `function maxSeenBy() { return ${contract.maxSeenBy}; }`,
      `function claimStale() { return duration.value(${contract.claimStaleMinutes}, 'm'); }`,
      `function undoWindow() { return duration.value(${contract.undoMinutes}, 'm'); }`,
      `function maxAge() { return duration.value(${contract.maxReportAgeDays}, 'd'); }`,
      `function maxDisputed() { return ${contract.maxDisputed}; }`,
    ]) {
      expect(rules).toContain(constant);
    }
    expect(rules).toContain(`after.goneReports.size() >= ${contract.goneThreshold}`);
  });

  it("kurallardaki hesap yaşı ve haklar sözleşmeyle aynı", () => {
    const rules = readRules();
    for (const constant of [
      `function newAccountAge() { return duration.value(${contract.newAccountHours}, 'h'); }`,
      `function budgetWindow() { return duration.value(${contract.budgetWindowHours}, 'h'); }`,
      `function maxCreates() { return ${contract.createQuota.perWindow}; }`,
      `function maxCreatesFirstDay() { return ${contract.createQuota.firstDay}; }`,
      `function closePoints() { return ${contract.closeBudget.points}; }`,
      `function credibleMaxDisputed() { return ${contract.closeBudget.maxDisputed}; }`,
    ]) {
      expect(rules).toContain(constant);
    }
    expect(needTable(rules, "closeCost")).toEqual(
      Object.fromEntries(Object.entries(contract.needs).map(([need, { closeCost }]) => [need, closeCost])),
    );
    // closeLast.w yalnızca sözleşmedeki puanlardan biri olabilir.
    const costs = [...new Set(Object.values(contract.needs).map((n) => n.closeCost))].sort();
    expect(rules).toContain(`after.closeLast.w in [${costs.join(", ")}]`);
  });

  it("kurallardaki durumlar, türler ve koleksiyonlar sözleşmeyle aynı", () => {
    const rules = readRules();
    expect(rules).toContain(`d.status in ${list(contract.statuses)}`);
    expect(rules).toContain(`d.species in ${list(contract.species)}`);
    expect(rules).toContain(`match /${contract.collection}/{reportId}`);
    expect(rules).toContain(`match /${contract.usersCollection}/{uid}`);
    expect(rules).toContain(`/documents/${contract.usersCollection}/$(me())`);
    expect(rules).toContain(`match /${contract.collections.flags}/{flagId}`);
    expect(rules).toContain(`match /${contract.collections.banned}/{uid}`);
    expect(rules).toContain(`match /${contract.collections.config}/{doc}`);
    expect(rules).toContain(`/documents/${contract.collections.banned}/$(me())`);
    expect(rules).toContain(`/documents/${contract.collection}/$(d.reportId)`);
  });

  it("şimdilik yalnızca kedi ve köpek; 'Diğer' ihtiyacı yok", () => {
    expect(contract.species).toEqual(["cat", "dog"]);
    expect(Object.keys(contract.needs)).toEqual(["emergency", "injured", "babies", "vet", "food", "shelter"]);
    const rules = readRules();
    for (const removed of ["'bird'", "'other'"]) expect(rules).not.toContain(removed);
  });

  it("kurallardaki kapatma ve kapanış sebepleri sözleşmeyle aynı", () => {
    const rules = readRules();
    expect(rules).toContain(`d.closingReason in ${list(contract.closingReasons)}`);
    expect(rules).toContain(`d.closedReason in ${list(contract.closedReasons)}`);
    // Önerilen her sebep, onay ya da süre dolumuyla aynen kapanış sebebi olur.
    for (const reason of contract.closingReasons) expect(contract.closedReasons).toContain(reason);
    expect(contract.closedReasons).toContain("expired");
    expect(rules).toContain(`function unneededNeeds() { return ${list(contract.unneededNeeds)}; }`);
  });

  it("hafif ihtiyaç listeleri bilinen ihtiyaçlardan oluşur; 'Yardım gerekmiyor' ağır ihtiyaçta yok", () => {
    const needs = Object.keys(contract.needs);
    for (const need of [...contract.unneededNeeds, ...contract.gentleCheckNeeds]) expect(needs).toContain(need);
    // "Yardım gerekmiyor" en ucuz kapatma puanlı ihtiyaçlarla sınırlı.
    const minCost = Math.min(...Object.values(contract.needs).map((n) => n.closeCost));
    for (const need of contract.unneededNeeds) expect(contract.needs[need].closeCost).toBe(minCost);
    expect(contract.gentleCheckNeeds).not.toContain("emergency");
  });

  it("kurallardaki düzenleme sınırları sözleşmeyle aynı", () => {
    const rules = readRules();
    const { windowMinutes, maxEdits, maxLatDelta, maxLngDelta } = contract.edit;
    for (const constant of [
      `function editWindow() { return duration.value(${windowMinutes}, 'm'); }`,
      `function maxEdits() { return ${maxEdits}; }`,
      `function editMaxLatDelta() { return ${maxLatDelta}; }`,
      `function editMaxLngDelta() { return ${maxLngDelta}; }`,
    ]) {
      expect(rules).toContain(constant);
    }
    // ~200 m: 0,0018° enlem ≈ 200 m; 0,0024° boylam Türkiye enlemlerinde ≈ 200 m.
    expect(distanceBetween([41, 29], [41 + maxLatDelta, 29]) * 1000).toBeCloseTo(200, -1);
    expect(distanceBetween([41, 29], [41, 29 + maxLngDelta]) * 1000).toBeLessThanOrEqual(210);
  });

  it("kurallardaki bildirim sebepleri sözleşmeyle aynı", () => {
    expect(readRules()).toContain(`d.reason in ${list(contract.flagReasons)}`);
  });

  it("uid içeren alanlar tek alan indeksinden çıkarılmış; TTL korunmuş; indeks dosyası geçerli", () => {
    const spec = JSON.parse(readFileSync(resolve(ROOT, "firebase", "firestore.indexes.json"), "utf8"));
    // Deploy'un yaptığı doğrulama (firebase-tools).
    const { FirestoreApi } = createRequire(import.meta.url)("firebase-tools/lib/firestore/api");
    const api = new FirestoreApi();
    expect(() => api.validateSpec(api.upgradeOldSpec(spec))).not.toThrow();

    const overrides = spec.fieldOverrides as { collectionGroup: string; fieldPath: string; ttl?: boolean; indexes: unknown[] }[];
    const uidFields = ["reporterId", "claimedBy", "closingBy", "seenBy", "goneReports", "objectors", "disputed"];
    for (const field of uidFields) {
      const override = overrides.find((o) => o.collectionGroup === contract.collection && o.fieldPath === field);
      expect(override, field).toBeDefined();
      expect(override!.indexes, field).toEqual([]);
      expect(override!.ttl, field).toBeUndefined();
    }
    expect(overrides.find((o) => o.fieldPath === "purgeAt")).toEqual({
      collectionGroup: contract.collection,
      fieldPath: "purgeAt",
      ttl: true,
      indexes: [],
    });
    // Hiçbir bileşik indeks ve temizlik sorgusu bu alanlara dayanmaz.
    for (const index of spec.indexes as { fields: { fieldPath: string }[] }[]) {
      for (const { fieldPath } of index.fields) expect(uidFields).not.toContain(fieldPath);
    }
    const sweep = readFileSync(resolve(ROOT, "firebase", "functions", "src", "sweep.ts"), "utf8");
    const queried = [...sweep.matchAll(/\.(?:where|orderBy)\("(\w+)"/g)].map(([, field]) => field);
    expect(queried.length).toBeGreaterThan(0);
    for (const field of queried) expect(uidFields).not.toContain(field);
  });

  // Kurallar konsola prototype/firebase-kurulum.html'deki "Kuralları kopyala" ile yapıştırılıyor;
  // oradaki kopya eskirse yeni istemcinin yazmaları reddedilir.
  it("kurulum sayfasındaki kural kopyası firestore.rules ile aynı", () => {
    const rules = readRules();
    const page = readFileSync(resolve(ROOT, "prototype", "firebase-kurulum.html"), "utf8");
    const escaped = page.match(/<pre id="rules">([\s\S]*?)<\/pre>/)?.[1];
    expect(escaped, "<pre id=\"rules\"> bulunamadı").toBeDefined();
    const embedded = escaped!
      .replace(/&lt;/g, "<")
      .replace(/&gt;/g, ">")
      .replace(/&quot;/g, "\"")
      .replace(/&#x27;/g, "'")
      .replace(/&amp;/g, "&");
    expect(embedded.replace(/\r\n/g, "\n")).toBe(rules.replace(/\r\n/g, "\n"));
  });
});

// Ücretsiz planda (Spark) TTL politikası kurulamıyor; indeksler firebase.spark.json ile TTL'siz dosyadan
// yüklenir. İki dosya TTL dışında hiç ayrışmamalı, yoksa Spark'ta yüklenen indeksler eksik kalır.
describe("Spark indeks dosyası", () => {
  const read = (name: string) => JSON.parse(readFileSync(resolve(ROOT, "firebase", name), "utf8"));

  it("firestore.indexes.json'dan yalnızca purgeAt TTL'si eksik", () => {
    const full = read("firestore.indexes.json");
    const spark = read("firestore.indexes.spark.json");
    const withoutTtl = JSON.parse(JSON.stringify(full));
    for (const override of withoutTtl.fieldOverrides) delete override.ttl;
    expect(spark).toEqual(withoutTtl);
    expect(full.fieldOverrides.find((o: { fieldPath: string }) => o.fieldPath === "purgeAt").ttl).toBe(true);
  });

  it("firebase.spark.json yalnızca indeks dosyasında ayrışır", () => {
    const full = read("firebase.json");
    const spark = read("firebase.spark.json");
    expect(spark.firestore.indexes).toBe("firestore.indexes.spark.json");
    expect({ ...spark, firestore: { ...spark.firestore, indexes: full.firestore.indexes } }).toEqual(full);
  });
});
