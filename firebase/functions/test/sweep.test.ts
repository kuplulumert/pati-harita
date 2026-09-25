import { readFileSync } from "node:fs";
import { deleteApp, initializeApp, type App } from "firebase-admin/app";
import { getFirestore, Timestamp, type Firestore } from "firebase-admin/firestore";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { ACTIVE_STATUSES, REPORTS, RETENTION_DAYS, sweepReports } from "../src/sweep";

const PROJECT = "demo-patiharita-sweep";
const HOUR = 3_600_000;
const DAY = 24 * HOUR;

let app: App;
let db: Firestore;

function report(overrides: Record<string, unknown> = {}) {
  const now = Date.now();
  return {
    species: "dog",
    need: "food",
    lat: 39.9208,
    lng: 32.8541,
    geohash: "sxp75e7es0",
    status: "open",
    closedReason: null,
    reporterId: "alice",
    createdAt: Timestamp.fromMillis(now - HOUR),
    lastSeenAt: Timestamp.fromMillis(now - HOUR),
    expiresAt: Timestamp.fromMillis(now + 11 * HOUR),
    claimedBy: null,
    claimedAt: null,
    claimExpiresAt: null,
    goneReports: [],
    seenBy: ["alice"],
    closedAt: null,
    purgeAt: null,
    closingReason: null,
    closingBy: null,
    closingAt: null,
    closingCredible: null,
    objectors: [],
    disputed: [],
    ...overrides,
  };
}

const get = async (id: string) => (await db.collection(REPORTS).doc(id).get()).data()!;

beforeAll(() => {
  if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error("Bu test Firestore emülatörü ile çalışır: npm test");
  app = initializeApp({ projectId: PROJECT }, "sweep-test");
  db = getFirestore(app);
});
afterAll(() => deleteApp(app));
beforeEach(async () => {
  await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${PROJECT}/databases/(default)/documents`, {
    method: "DELETE",
  });
});

describe("sözleşme", () => {
  it("sabitler shared/report-contract.json ile aynı", () => {
    const contract = JSON.parse(readFileSync(new URL("../../../shared/report-contract.json", import.meta.url), "utf8"));
    expect(REPORTS).toBe(contract.collection);
    expect(RETENTION_DAYS).toBe(contract.retentionDays);
    expect(ACTIVE_STATUSES).toEqual(contract.statuses.filter((s: string) => s !== "closed"));
  });
});

describe("sweepReports", () => {
  it("süresi dolan işaretleri kapatır ve silinme tarihini ayarlar", async () => {
    await db.collection(REPORTS).doc("stale").set(report({ expiresAt: Timestamp.fromMillis(Date.now() - 1000) }));
    const now = Timestamp.now();

    const result = await sweepReports(db, now);

    expect(result).toEqual({ expired: 1, claimsReleased: 0 });
    const doc = await get("stale");
    expect(doc.status).toBe("closed");
    expect(doc.closedReason).toBe("expired");
    expect(doc.closedAt.toMillis()).toBe(now.toMillis());
    expect(doc.purgeAt.toMillis()).toBe(now.toMillis() + RETENTION_DAYS * DAY);
  });

  it("süresi dolan \"… dendi\" işareti önerilen sebeple kapatır, öneriyi geçmiş olarak bırakır", async () => {
    const past = Timestamp.fromMillis(Date.now() - 1000);
    const closing = (closingReason: string) =>
      report({
        status: "closing",
        expiresAt: past,
        closingReason,
        closingBy: "bob",
        closingAt: Timestamp.fromMillis(Date.now() - 2 * HOUR),
        closingCredible: true,
      });
    await db.collection(REPORTS).doc("rescued").set(closing("resolved"));
    await db.collection(REPORTS).doc("gone").set(closing("gone"));
    await db.collection(REPORTS).doc("live").set({ ...closing("resolved"), expiresAt: Timestamp.fromMillis(Date.now() + HOUR) });

    const result = await sweepReports(db);

    expect(result).toEqual({ expired: 2, claimsReleased: 0 });
    const rescued = await get("rescued");
    expect(rescued.status).toBe("closed");
    expect(rescued.closedReason).toBe("resolved");
    expect(rescued.closingBy).toBe("bob");
    expect(rescued.closingCredible).toBe(true);
    expect((await get("gone")).closedReason).toBe("gone");
    expect((await get("live")).status).toBe("closing");
  });

  it("sahipliği olan işaret süresi dolunca closed(expired) olur", async () => {
    const claimedAt = Date.now() - HOUR;
    await db.collection(REPORTS).doc("claimed").set(
      report({
        status: "claimed",
        claimedBy: "bob",
        claimedAt: Timestamp.fromMillis(claimedAt),
        claimExpiresAt: Timestamp.fromMillis(claimedAt + 3 * HOUR),
        expiresAt: Timestamp.fromMillis(Date.now() - 1000),
      }),
    );

    const result = await sweepReports(db);

    expect(result).toEqual({ expired: 1, claimsReleased: 0 });
    const doc = await get("claimed");
    expect(doc.status).toBe("closed");
    expect(doc.closedReason).toBe("expired");
  });

  it("süresi dolan sahipliği bırakır, işaret yeniden yardım bekler", async () => {
    const claimedAt = Date.now() - 4 * HOUR;
    await db.collection(REPORTS).doc("abandoned").set(
      report({
        status: "claimed",
        claimedBy: "bob",
        claimedAt: Timestamp.fromMillis(claimedAt),
        claimExpiresAt: Timestamp.fromMillis(claimedAt + 3 * HOUR),
      }),
    );

    const result = await sweepReports(db);

    expect(result).toEqual({ expired: 0, claimsReleased: 1 });
    const doc = await get("abandoned");
    expect(doc.status).toBe("open");
    expect(doc.claimedBy).toBeNull();
    expect(doc.claimedAt).toBeNull();
    expect(doc.claimExpiresAt).toBeNull();
  });

  it("aktif ve kapanmış işaretlere dokunmaz", async () => {
    const liveClaim = report({
      status: "claimed",
      claimedBy: "bob",
      claimedAt: Timestamp.fromMillis(Date.now() - HOUR),
      claimExpiresAt: Timestamp.fromMillis(Date.now() + 2 * HOUR),
    });
    const closed = report({
      status: "closed",
      closedReason: "resolved",
      expiresAt: Timestamp.fromMillis(Date.now() - DAY),
      closedAt: Timestamp.fromMillis(Date.now() - DAY),
      purgeAt: Timestamp.fromMillis(Date.now() + 29 * DAY),
    });
    await db.collection(REPORTS).doc("fresh").set(report());
    await db.collection(REPORTS).doc("helping").set(liveClaim);
    await db.collection(REPORTS).doc("done").set(closed);

    const result = await sweepReports(db);

    expect(result).toEqual({ expired: 0, claimsReleased: 0 });
    expect((await get("fresh")).status).toBe("open");
    expect((await get("helping")).claimedBy).toBe("bob");
    expect((await get("done")).closedReason).toBe("resolved");
  });

  it("sayfalar hâlinde çok sayıda işareti işler", async () => {
    const batch = db.batch();
    for (let i = 0; i < 450; i++) {
      batch.set(db.collection(REPORTS).doc(`old-${i}`), report({ expiresAt: Timestamp.fromMillis(Date.now() - 1000) }));
    }
    await batch.commit();

    const result = await sweepReports(db);

    expect(result.expired).toBe(450);
    const remaining = await db.collection(REPORTS).where("status", "==", "open").count().get();
    expect(remaining.data().count).toBe(0);
  });
});
