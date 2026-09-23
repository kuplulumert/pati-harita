import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { sweepReports } from "./sweep";

initializeApp();

/** Eski işaretlerin haritada kalmasını önleyen periyodik temizlik. */
export const sweepStaleReports = onSchedule(
  { schedule: "every 10 minutes", region: "europe-west1", timeoutSeconds: 120 },
  async () => {
    const result = await sweepReports(getFirestore());
    logger.info("Harita temizliği tamamlandı", result);
  },
);
