import type { DocumentData, Firestore, QueryDocumentSnapshot } from "firebase-admin/firestore";
import { Timestamp } from "firebase-admin/firestore";

/** shared/report-contract.json ile aynı değerler. */
export const REPORTS = "reports";
export const RETENTION_DAYS = 30;
/** Henüz kapanmamış, haritada duran işaret durumları. */
export const ACTIVE_STATUSES = ["open", "claimed", "closing"];

const PAGE_SIZE = 400;
// Tek çalıştırmada en fazla bu kadar sayfa işlenir; kalan bir sonraki çalıştırmaya kalır.
const MAX_PAGES = 25;
const DAY_MS = 24 * 60 * 60 * 1000;

export interface SweepResult {
  expired: number;
  claimsReleased: number;
}

/**
 * Süresi dolan işaret: haritadan kalkar, `retentionDays` sonra TTL ile silinir.
 * "Çözüldü dendi" / "Artık yok dendi" (closing) işaret önerildiği sebeple kapanır;
 * kurallardaki isExpire ile aynı (Spark'ta istemciler de süresi dolanı böyle kapatır).
 */
export function expiredFields(now: Timestamp, report: DocumentData = {}) {
  const proposed = report.status === "closing" ? report.closingReason : null;
  return {
    status: "closed",
    closedReason: proposed === "resolved" || proposed === "gone" ? proposed : "expired",
    closedAt: now,
    purgeAt: Timestamp.fromMillis(now.toMillis() + RETENTION_DAYS * DAY_MS),
  };
}

/** Sahiplik süresi dolan işaret: tekrar "yardım bekliyor" durumuna döner. */
export function releasedClaimFields() {
  return {
    status: "open",
    claimedBy: null,
    claimedAt: null,
    claimExpiresAt: null,
  };
}

/**
 * Haritayı temiz tutar:
 *  1. `expiresAt` geçmiş açık/ilgilenilen işaretleri `closed(expired)`, "… dendi" işaretleri
 *     önerilen sebeple (`closed(closingReason)`) kapatır.
 *  2. `claimExpiresAt` geçmiş sahiplikleri bırakır (işaret yeniden `open` olur).
 *
 * İstemci de süresi dolmuş işaretleri gizlediği için bu iş birkaç dakika gecikse
 * bile kullanıcı eski işaret görmez; burası veritabanını tutarlı tutar.
 */
export async function sweepReports(db: Firestore, now: Timestamp = Timestamp.now()): Promise<SweepResult> {
  const reports = db.collection(REPORTS);

  const expired = await updateInPages(
    () =>
      reports
        .where("status", "in", ACTIVE_STATUSES)
        .where("expiresAt", "<=", now)
        .limit(PAGE_SIZE)
        .get(),
    db,
    (doc) => expiredFields(now, doc.data()),
  );

  const claimsReleased = await updateInPages(
    () =>
      reports
        .where("status", "==", "claimed")
        .where("claimExpiresAt", "<=", now)
        .limit(PAGE_SIZE)
        .get(),
    db,
    () => releasedClaimFields(),
  );

  return { expired, claimsReleased };
}

async function updateInPages(
  fetchPage: () => Promise<{ docs: QueryDocumentSnapshot[] }>,
  db: Firestore,
  fields: (doc: QueryDocumentSnapshot) => Record<string, unknown>,
): Promise<number> {
  let total = 0;
  for (let page = 0; page < MAX_PAGES; page++) {
    const { docs } = await fetchPage();
    if (docs.length === 0) break;

    const batch = db.batch();
    for (const doc of docs) batch.update(doc.ref, fields(doc));
    await batch.commit();

    total += docs.length;
    if (docs.length < PAGE_SIZE) break;
  }
  return total;
}
