import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { Timestamp } from "firebase/firestore";

export const ROOT = fileURLToPath(new URL("../..", import.meta.url));

export const contract = JSON.parse(
  readFileSync(resolve(ROOT, "shared", "report-contract.json"), "utf8"),
) as {
  collection: string;
  species: string[];
  needs: Record<string, { lifetimeHours: number }>;
  claimHours: number;
  goneThreshold: number;
  retentionDays: number;
  clockSkewMinutes: number;
  maxBackdateHours: number;
  geohashPrecision: number;
};

export const MINUTE = 60_000;
export const HOUR = 60 * MINUTE;
export const DAY = 24 * HOUR;

export const ts = (millis: number) => Timestamp.fromMillis(millis);

export const ALICE = "alice"; // işareti koyan
export const BOB = "bob"; // yardım eden
export const CARA = "cara"; // yoldan geçen

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
    closedAt: null,
    purgeAt: null,
    ...overrides,
  };
}

/** `userId` tarafından şu an ilgilenilen işaret. */
export function claimedReport(userId: string, overrides: Record<string, unknown> = {}) {
  const now = Date.now();
  return openReport({
    status: "claimed",
    claimedBy: userId,
    claimedAt: ts(now - 10 * MINUTE),
    claimExpiresAt: ts(now - 10 * MINUTE + contract.claimHours * HOUR),
    ...overrides,
  });
}

export function claimFields(userId: string, now = Date.now()) {
  return {
    status: "claimed",
    claimedBy: userId,
    claimedAt: ts(now),
    claimExpiresAt: ts(now + contract.claimHours * HOUR),
  };
}

export function closeFields(reason: "resolved" | "gone", now = Date.now()) {
  return {
    status: "closed",
    closedReason: reason,
    closedAt: ts(now),
    purgeAt: ts(now + contract.retentionDays * DAY),
  };
}
