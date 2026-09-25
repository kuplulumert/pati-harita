import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { distanceBetween, geohashForLocation, geohashQueryBounds } from "geofire-common";
import { describe, expect, it } from "vitest";
import { ROOT, contract } from "./helpers";

const vectors = JSON.parse(readFileSync(resolve(ROOT, "shared", "geohash-vectors.json"), "utf8"));

const readRules = () => readFileSync(resolve(ROOT, "firebase", "firestore.rules"), "utf8");

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
    const list = (values: string[]) => `[${values.map((v) => `'${v}'`).join(", ")}]`;
    expect(rules).toContain(`d.status in ${list(contract.statuses)}`);
    expect(rules).toContain(`d.species in ${list(contract.species)}`);
    expect(rules).toContain(`match /${contract.collection}/{reportId}`);
    expect(rules).toContain(`match /${contract.usersCollection}/{uid}`);
    expect(rules).toContain(`/documents/${contract.usersCollection}/$(me())`);
  });

  // Kurallar konsola prototype/firebase-kurulum.html'deki "Kuralları kopyala" ile yapıştırılıyor;
  // oradaki kopya eskirse yeni istemcinin yazmaları reddedilir.
  it("kurulum sayfasındaki kural kopyası firestore.rules ile aynı", () => {
    const rules = readRules();
    const page =readFileSync(resolve(ROOT, "prototype", "firebase-kurulum.html"), "utf8");
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
