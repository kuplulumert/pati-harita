import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import {
  Timestamp,
  doc,
  increment,
  serverTimestamp,
  writeBatch,
  type FieldValue,
  type Firestore,
} from "firebase/firestore";

export const ROOT = fileURLToPath(new URL("../..", import.meta.url));

export type Need = "emergency" | "injured" | "babies" | "vet" | "food" | "shelter" | "other";
export type ClosingReason = "resolved" | "gone";

export const contract = JSON.parse(
  readFileSync(resolve(ROOT, "shared", "report-contract.json"), "utf8"),
) as {
  collection: string;
  usersCollection: string;
  species: string[];
  statuses: string[];
  needs: Record<Need, { lifetimeHours: number; closeCost: number; demoteMinutes: number }>;
  claimHours: number;
  claimStaleMinutes: number;
  undoMinutes: number;
  goneThreshold: number;
  maxSeenBy: number;
  maxDisputed: number;
  maxReportAgeDays: number;
  retentionDays: number;
  clockSkewMinutes: number;
  maxBackdateHours: number;
  geohashPrecision: number;
  newAccountHours: number;
  budgetWindowHours: number;
  createQuota: { perWindow: number; firstDay: number };
  closeBudget: { points: number; maxDisputed: number };
  closingDisplay: {
    dayStartHour: number;
    dayEndHour: number;
    utcOffsetHours: number;
    streetDotMaxRadiusMeters: number;
    closerUndoToastSeconds: number;
    modes: string[];
    defaultMode: string;
  };
};

export const MINUTE = 60_000;
export const HOUR = 60 * MINUTE;
export const DAY = 24 * HOUR;

export const ts = (millis: number) => Timestamp.fromMillis(millis);

export const ALICE = "alice"; // işareti koyan
export const BOB = "bob"; // yardım eden
export const CARA = "cara"; // yoldan geçen
export const DAVE = "dave"; // başka bir gönüllü

// ---- reports/{id} ----------------------------------------------------------

/** İstemcinin oluşturduğu tam bir "open" işaret (ReportLifecycle.makeReport karşılığı). */
export function openReport(overrides: Record<string, unknown> = {}) {
  const now = Date.now();
  return {
    species: "cat",
    need: "injured",
    lat: 40.9903,
    lng: 29.029,
    geohash: "sxk9hw43b9",
    status: "open",
    closedReason: null,
    reporterId: ALICE,
    createdAt: ts(now),
    lastSeenAt: ts(now),
    expiresAt: ts(now + contract.needs.injured.lifetimeHours * HOUR),
    claimedBy: null,
    claimedAt: null,
    claimExpiresAt: null,
    goneReports: [],
    seenBy: [ALICE],
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

/** `userId`'nin `claimedMinutesAgo` dakika önce üstüne aldığı, sahipliği hâlâ geçerli işaret. */
export function claimedReport(userId: string, overrides: Record<string, unknown> = {}, claimedMinutesAgo = 10) {
  const claimedAt = Date.now() - claimedMinutesAgo * MINUTE;
  return openReport({
    status: "claimed",
    claimedBy: userId,
    claimedAt: ts(claimedAt),
    claimExpiresAt: ts(claimedAt + contract.claimHours * HOUR),
    ...overrides,
  });
}

/** `by`'ın `minutesAgo` dakika önce önerdiği "Çözüldü dendi" / "Artık yok dendi" işaret. */
export function closingReport(
  by: string,
  reason: ClosingReason = "resolved",
  credible = false,
  overrides: Record<string, unknown> = {},
  minutesAgo = 5,
) {
  return openReport({
    status: "closing",
    closingReason: reason,
    closingBy: by,
    closingAt: ts(Date.now() - minutesAgo * MINUTE),
    closingCredible: credible,
    ...overrides,
  });
}

/** "İlgileniyorum" yazımı; claimedAt sunucu saatidir. */
export function claimFields(userId: string, now = Date.now()) {
  return {
    status: "claimed",
    claimedBy: userId,
    claimedAt: serverTimestamp(),
    claimExpiresAt: ts(now + contract.claimHours * HOUR),
  };
}

export function closeFields(reason: ClosingReason | "expired", now = Date.now()) {
  return {
    status: "closed",
    closedReason: reason,
    closedAt: ts(now),
    purgeAt: ts(now + contract.retentionDays * DAY),
  };
}

/** Kapatma önerisi (`by` yazan kişi olmalı); closingAt sunucu saatidir. */
export function closingFields(by: string, reason: ClosingReason = "resolved", credible = false) {
  return {
    status: "closing",
    closingReason: reason,
    closingBy: by,
    closingAt: serverTimestamp(),
    closingCredible: credible,
  };
}

/** Kapatma önerisini geri alan alanlar (Geri al / itiraz). */
export const clearedClosing = {
  closingReason: null,
  closingBy: null,
  closingAt: null,
  closingCredible: null,
};

export const clearedClaim = { claimedBy: null, claimedAt: null, claimExpiresAt: null };

// ---- users/{uid} -----------------------------------------------------------

/** users/{uid}: `ageMillis` yaşında hesap; pencereler 1 saat önce başlamış, hiç harcama yok. */
export function userRecord(overrides: Record<string, unknown> = {}, ageMillis = 3 * DAY) {
  const now = Date.now();
  return {
    createdAt: ts(now - ageMillis),
    createWindow: ts(now - HOUR),
    createUsed: 0,
    createLast: null,
    closeWindow: ts(now - HOUR),
    closeUsed: 0,
    closeLast: null,
    ...overrides,
  };
}

/** En az 24 saatlik hesap (kanıtlı kapatabilir, günde 10 işaret). */
export const agedUser = (overrides: Record<string, unknown> = {}) => userRecord(overrides, 3 * DAY);

/** 1 saatlik hesap (ilk gün: 5 işaret, başkasının işaretini kanıtlı kapatamaz). */
export const newUser = (overrides: Record<string, unknown> = {}) => userRecord(overrides, HOUR);

/** İstemcinin ilk açılışta yazdığı users dokümanı. */
export function newUserFields() {
  return {
    createdAt: serverTimestamp(),
    createWindow: serverTimestamp(),
    createUsed: 0,
    createLast: null,
    closeWindow: serverTimestamp(),
    closeUsed: 0,
    closeLast: null,
  };
}

type Fields = Record<string, unknown>;

/** Aynı pencerede bir işaret hakkı harcar (`used` verilmezse sayaç sunucuda 1 artar). */
export function createSpend(reportId: string, used?: number): Fields {
  return {
    createUsed: used ?? (increment(1) as FieldValue),
    createLast: { t: serverTimestamp(), id: reportId },
  };
}

/** Pencere bittiyse yenisini başlatıp ilk hakkı harcar. */
export function createReset(reportId: string): Fields {
  return { createWindow: serverTimestamp(), createUsed: 1, createLast: { t: serverTimestamp(), id: reportId } };
}

/** Aynı pencerede `w` puan harcar (`used` verilmezse sayaç sunucuda `w` artar). */
export function closeSpend(reportId: string, w: number, used?: number): Fields {
  return {
    closeUsed: used ?? (increment(w) as FieldValue),
    closeLast: { t: serverTimestamp(), id: reportId, w },
  };
}

/** Pencere bittiyse yenisini başlatıp `w` puan harcar. */
export function closeReset(reportId: string, w: number): Fields {
  return { closeWindow: serverTimestamp(), closeUsed: w, closeLast: { t: serverTimestamp(), id: reportId, w } };
}

/**
 * Uygulamanın işaret oluşturması: işaret + users/{uid}'den bu işaret için harcanan hak,
 * tek toplu yazımda (çevrimdışı da çalışır). `spend` null ise yalnızca işaret yazılır.
 */
export function createWithSpend(
  db: Firestore,
  uid: string,
  id: string,
  data: Fields,
  spend: Fields | null = createSpend(id),
) {
  const batch = writeBatch(db);
  batch.set(doc(db, contract.collection, id), data);
  if (spend) batch.update(doc(db, contract.usersCollection, uid), spend);
  return batch.commit();
}

/** Bir işaret güncellemesi + users/{uid} harcaması, tek toplu yazımda (kanıtlı kapatma). */
export function updateWithSpend(db: Firestore, uid: string, id: string, fields: Fields, spend: Fields) {
  const batch = writeBatch(db);
  batch.update(doc(db, contract.collection, id), fields);
  batch.update(doc(db, contract.usersCollection, uid), spend);
  return batch.commit();
}
