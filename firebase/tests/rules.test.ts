import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  type RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { Timestamp, deleteDoc, doc, getDoc, setDoc, updateDoc } from "firebase/firestore";
import { afterAll, beforeAll, beforeEach, describe, it } from "vitest";
import {
  ALICE,
  BOB,
  CARA,
  DAY,
  HOUR,
  MINUTE,
  ROOT,
  claimFields,
  claimedReport,
  closeFields,
  contract,
  openReport,
  ts,
} from "./helpers";

let env: RulesTestEnvironment;
const ID = "r1";

const db = (uid: string) => env.authenticatedContext(uid).firestore();
const ref = (uid: string, id = ID) => doc(db(uid), contract.collection, id);

async function seed(data: Record<string, unknown>, id = ID) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), contract.collection, id), data);
  });
}

beforeAll(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-patiharita-rules",
    firestore: { rules: readFileSync(resolve(ROOT, "firebase", "firestore.rules"), "utf8") },
  });
});
afterAll(() => env.cleanup());
beforeEach(() => env.clearFirestore());

describe("okuma", () => {
  it("giriş yapmış (anonim dahil) herkes okuyabilir", async () => {
    await seed(openReport());
    await assertSucceeds(getDoc(ref(CARA)));
  });

  it("giriş yapmamış kullanıcı okuyamaz", async () => {
    await seed(openReport());
    await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), contract.collection, ID)));
  });
});

describe("işaret oluşturma", () => {
  it("geçerli bir işaret oluşturulabilir", async () => {
    await assertSucceeds(setDoc(ref(ALICE), openReport()));
  });

  it("başkası adına işaret oluşturulamaz", async () => {
    await assertFails(setDoc(ref(BOB), openReport()));
  });

  it("çevrimdışı işaretlenip geç senkronlanan kayıt kabul edilir", async () => {
    const seenAt = Date.now() - 3 * HOUR;
    await assertSucceeds(
      setDoc(ref(ALICE), openReport({ createdAt: ts(seenAt), lastSeenAt: ts(seenAt), expiresAt: ts(seenAt + 24 * HOUR) })),
    );
  });

  it("çok eski ya da gelecekteki zaman damgası reddedilir", async () => {
    const old = Date.now() - (contract.maxBackdateHours + 1) * HOUR;
    await assertFails(setDoc(ref(ALICE), openReport({ createdAt: ts(old), lastSeenAt: ts(old), expiresAt: ts(old + 24 * HOUR) })));
    const future = Date.now() + 2 * HOUR;
    await assertFails(
      setDoc(ref(ALICE), openReport({ createdAt: ts(future), lastSeenAt: ts(future), expiresAt: ts(future + 24 * HOUR) })),
    );
  });

  it("doğrudan 'claimed' ya da 'closed' olarak oluşturulamaz", async () => {
    await assertFails(setDoc(ref(ALICE), claimedReport(ALICE)));
    await assertFails(setDoc(ref(ALICE), openReport(closeFields("resolved"))));
  });

  it("eksik, fazla ya da hatalı alanlar reddedilir", async () => {
    const { geohash: _omit, ...missing } = openReport();
    await assertFails(setDoc(ref(ALICE), missing));
    await assertFails(setDoc(ref(ALICE), openReport({ note: "uzun açıklama" })));
    await assertFails(setDoc(ref(ALICE), openReport({ species: "fish" })));
    await assertFails(setDoc(ref(ALICE), openReport({ need: "toys" })));
    await assertFails(setDoc(ref(ALICE), openReport({ lat: 91 })));
    await assertFails(setDoc(ref(ALICE), openReport({ geohash: "sxk9hw43ba" }))); // 'a' geohash alfabesinde yok
    await assertFails(setDoc(ref(ALICE), openReport({ goneReports: [BOB] })));
  });

  it("\"kaç kişi bildirdi\" listesi yalnızca bildiren kişiyle başlar", async () => {
    const { seenBy: _omit, ...missing } = openReport();
    await assertFails(setDoc(ref(ALICE), missing));
    await assertFails(setDoc(ref(ALICE), openReport({ seenBy: [] })));
    await assertFails(setDoc(ref(ALICE), openReport({ seenBy: ALICE })));
    await assertFails(setDoc(ref(ALICE), openReport({ seenBy: [BOB] })));
    await assertFails(setDoc(ref(ALICE), openReport({ seenBy: [ALICE, BOB] })));
    await assertSucceeds(setDoc(ref(ALICE), openReport({ seenBy: [ALICE] })));
  });

  it("sözleşmedeki her tür kabul edilir", async () => {
    for (const species of contract.species) {
      await assertSucceeds(setDoc(ref(ALICE, `s-${species}`), openReport({ species })));
    }
  });

  it("her ihtiyacın ömrü sözleşmeyle aynı sınırda uygulanır", async () => {
    for (const [need, { lifetimeHours }] of Object.entries(contract.needs)) {
      const now = Date.now();
      const base = { need, createdAt: ts(now), lastSeenAt: ts(now) };
      await assertSucceeds(setDoc(ref(ALICE, `ok-${need}`), openReport({ ...base, expiresAt: ts(now + lifetimeHours * HOUR) })));
      await assertFails(
        setDoc(ref(ALICE, `long-${need}`), openReport({ ...base, expiresAt: ts(now + lifetimeHours * HOUR + 2 * MINUTE) })),
      );
    }
  });
});

describe("İlgileniyorum (claim)", () => {
  it("açık işaret üstüne alınabilir ve ömrü sahiplik süresine uzatılabilir", async () => {
    await seed(openReport({ need: "food", expiresAt: ts(Date.now() + HOUR) }));
    const claim = claimFields(BOB);
    await assertSucceeds(updateDoc(ref(BOB), { ...claim, expiresAt: claim.claimExpiresAt }));
  });

  it("işareti koyan kişi de ilgilenebilir", async () => {
    await seed(openReport());
    await assertSucceeds(updateDoc(ref(ALICE), claimFields(ALICE)));
  });

  it("başkasının aktif sahipliği devralınamaz", async () => {
    await seed(claimedReport(BOB));
    await assertFails(updateDoc(ref(CARA), claimFields(CARA)));
  });

  it("süresi dolmuş sahiplik devralınabilir", async () => {
    const past = Date.now() - 4 * HOUR;
    await seed(claimedReport(BOB, { claimedAt: ts(past), claimExpiresAt: ts(past + contract.claimHours * HOUR) }));
    await assertSucceeds(updateDoc(ref(CARA), claimFields(CARA)));
  });

  it("sahiplik süresi sözleşmedekinden uzun olamaz", async () => {
    await seed(openReport());
    const now = Date.now();
    await assertFails(
      updateDoc(ref(BOB), { ...claimFields(BOB, now), claimExpiresAt: ts(now + contract.claimHours * HOUR + 2 * MINUTE) }),
    );
  });

  it("başkası adına ya da başka alanlara dokunarak sahiplenilemez", async () => {
    await seed(openReport());
    await assertFails(updateDoc(ref(BOB), claimFields(CARA)));
    await assertFails(updateDoc(ref(BOB), { ...claimFields(BOB), need: "food" }));
    await assertFails(updateDoc(ref(BOB), { ...claimFields(BOB), lat: 41.1 }));
  });
});

describe("Vazgeç (release)", () => {
  const release = { status: "open", claimedBy: null, claimedAt: null, claimExpiresAt: null };

  it("ilgilenen kişi bırakabilir", async () => {
    await seed(claimedReport(BOB));
    await assertSucceeds(updateDoc(ref(BOB), release));
  });

  it("başkası bırakamaz", async () => {
    await seed(claimedReport(BOB));
    await assertFails(updateDoc(ref(ALICE), release));
    await assertFails(updateDoc(ref(CARA), release));
  });
});

describe("Çözüldü (resolve)", () => {
  it("ilgilenen kişi kapatabilir", async () => {
    await seed(claimedReport(BOB));
    await assertSucceeds(updateDoc(ref(BOB), closeFields("resolved")));
  });

  it("işareti koyan kişi kapatabilir", async () => {
    await seed(openReport());
    await assertSucceeds(updateDoc(ref(ALICE), closeFields("resolved")));
  });

  it("ilgisiz biri kapatamaz", async () => {
    await seed(openReport());
    await assertFails(updateDoc(ref(CARA), closeFields("resolved")));
    await seed(claimedReport(BOB));
    await assertFails(updateDoc(ref(CARA), closeFields("resolved")));
  });

  it("sahipliği dolmuş kişi kapatamaz", async () => {
    const past = Date.now() - 4 * HOUR;
    await seed(claimedReport(BOB, { claimedAt: ts(past), claimExpiresAt: ts(past + contract.claimHours * HOUR) }));
    await assertFails(updateDoc(ref(BOB), closeFields("resolved")));
  });

  it("saklama süresi sözleşmedekinden uzun olamaz", async () => {
    await seed(openReport());
    const now = Date.now();
    await assertSucceeds(updateDoc(ref(ALICE), closeFields("resolved", now)));
    await seed(openReport());
    await assertFails(
      updateDoc(ref(ALICE), { ...closeFields("resolved", now), purgeAt: ts(now + (contract.retentionDays + 1) * DAY) }),
    );
  });

  it("kapanmış işaret tekrar değiştirilemez", async () => {
    await seed(openReport(closeFields("resolved")));
    await assertFails(updateDoc(ref(ALICE), claimFields(ALICE)));
    await assertFails(updateDoc(ref(CARA), { lastSeenAt: ts(Date.now()) }));
  });
});

describe("Hâlâ orada (confirm)", () => {
  it("herkes ömrü ihtiyacın süresi kadar uzatabilir", async () => {
    const created = Date.now() - 20 * HOUR;
    await seed(openReport({ createdAt: ts(created), lastSeenAt: ts(created), expiresAt: ts(created + 24 * HOUR) }));
    const now = Date.now();
    await assertSucceeds(updateDoc(ref(CARA), { lastSeenAt: ts(now), expiresAt: ts(now + 24 * HOUR) }));
  });

  it("ihtiyacın süresinden fazla uzatılamaz ya da kısaltılamaz", async () => {
    const created = Date.now() - 20 * HOUR;
    await seed(openReport({ createdAt: ts(created), lastSeenAt: ts(created), expiresAt: ts(created + 24 * HOUR) }));
    const now = Date.now();
    await assertFails(updateDoc(ref(CARA), { lastSeenAt: ts(now), expiresAt: ts(now + 48 * HOUR) }));
    await assertFails(updateDoc(ref(CARA), { lastSeenAt: ts(now), expiresAt: ts(now + HOUR) }));
  });
});

describe("Kaç kişi bildirdi (seenBy)", () => {
  // 20 saat önce görülmüş, "Hâlâ orada" ile yenilenmeye hazır işaret.
  function seedSeen(seenBy: string[]) {
    const created = Date.now() - 20 * HOUR;
    return seed(openReport({ createdAt: ts(created), lastSeenAt: ts(created), expiresAt: ts(created + 24 * HOUR), seenBy }));
  }

  // "Hâlâ orada" yazımı; seenBy verilirse o da yazılır.
  function confirm(seenBy?: string[]) {
    const now = Date.now();
    return { lastSeenAt: ts(now), expiresAt: ts(now + 24 * HOUR), ...(seenBy ? { seenBy } : {}) };
  }

  it("\"Hâlâ orada\" diyen kişi kendini sona ekleyebilir", async () => {
    await seedSeen([ALICE]);
    await assertSucceeds(updateDoc(ref(CARA), confirm([ALICE, CARA])));
    await seedSeen([ALICE, BOB]);
    await assertSucceeds(updateDoc(ref(CARA), confirm([ALICE, BOB, CARA])));
  });

  it("seenBy değişmeden de yenilenebilir (zaten listede olan dahil)", async () => {
    await seedSeen([ALICE]);
    await assertSucceeds(updateDoc(ref(CARA), confirm()));
    await seedSeen([ALICE, CARA]);
    await assertSucceeds(updateDoc(ref(CARA), confirm([ALICE, CARA])));
    await seedSeen([ALICE, CARA]);
    await assertSucceeds(updateDoc(ref(ALICE), confirm()));
  });

  it("başkası eklenemez", async () => {
    await seedSeen([ALICE]);
    await assertFails(updateDoc(ref(CARA), confirm([ALICE, BOB])));
    await assertFails(updateDoc(ref(CARA), confirm([ALICE, CARA, BOB])));
    await assertFails(updateDoc(ref(CARA), confirm([ALICE, BOB, CARA])));
  });

  it("aynı kişi iki kez eklenemez", async () => {
    await seedSeen([ALICE, CARA]);
    await assertFails(updateDoc(ref(CARA), confirm([ALICE, CARA, CARA])));
    await assertFails(updateDoc(ref(ALICE), confirm([ALICE, CARA, ALICE])));
  });

  it("kimse silinemez, sıra değiştirilemez", async () => {
    await seedSeen([ALICE, BOB]);
    await assertFails(updateDoc(ref(CARA), confirm([ALICE])));
    await assertFails(updateDoc(ref(CARA), confirm([])));
    await assertFails(updateDoc(ref(CARA), confirm([CARA])));
    await assertFails(updateDoc(ref(CARA), confirm([BOB, ALICE])));
    await assertFails(updateDoc(ref(CARA), confirm([BOB, ALICE, CARA])));
    await assertFails(updateDoc(ref(CARA), confirm([ALICE, CARA])));
  });

  it("ömür yenilenmeden tek başına seenBy yazılamaz", async () => {
    await seedSeen([ALICE]);
    await assertFails(updateDoc(ref(CARA), { seenBy: [ALICE, CARA] }));
  });

  it(`en fazla ${contract.maxSeenBy} kişi tutulur; liste doluyken yenilemek yine serbest`, async () => {
    const full = [ALICE, ...Array.from({ length: contract.maxSeenBy - 1 }, (_, i) => `u${i}`)];
    await seedSeen(full);
    await assertFails(updateDoc(ref(CARA), confirm([...full, CARA])));
    await assertSucceeds(updateDoc(ref(CARA), confirm()));
    // Bir eksikken son kişi eklenebilir.
    const almost = full.slice(0, -1);
    await seedSeen(almost);
    await assertSucceeds(updateDoc(ref(CARA), confirm([...almost, CARA])));
  });

  // Her eylem önce seenBy ile reddedilir, ardından seenBy'sız aynı yazım kabul edilir.
  it("İlgileniyorum, Vazgeç, Çözüldü ve Artık yok seenBy'a dokunamaz", async () => {
    await seed(openReport());
    await assertFails(updateDoc(ref(BOB), { ...claimFields(BOB), seenBy: [ALICE, BOB] }));
    await assertSucceeds(updateDoc(ref(BOB), claimFields(BOB)));

    const release = { status: "open", claimedBy: null, claimedAt: null, claimExpiresAt: null };
    await seed(claimedReport(BOB));
    await assertFails(updateDoc(ref(BOB), { ...release, seenBy: [ALICE, BOB] }));
    await assertSucceeds(updateDoc(ref(BOB), release));

    await seed(claimedReport(BOB, { seenBy: [ALICE, BOB] }));
    await assertFails(updateDoc(ref(BOB), { ...closeFields("resolved"), seenBy: [ALICE] }));
    await assertSucceeds(updateDoc(ref(BOB), closeFields("resolved")));

    await seed(openReport());
    await assertFails(updateDoc(ref(CARA), { goneReports: [CARA], seenBy: [ALICE, CARA] }));
    await assertSucceeds(updateDoc(ref(CARA), { goneReports: [CARA] }));

    await seed(claimedReport(BOB));
    await assertFails(updateDoc(ref(BOB), { goneReports: [BOB], ...closeFields("gone"), seenBy: [ALICE, BOB] }));
    await assertSucceeds(updateDoc(ref(BOB), { goneReports: [BOB], ...closeFields("gone") }));
  });
});

describe("Artık yok (gone)", () => {
  it("ilk bildirim işareti kapatmaz, sadece kaydedilir", async () => {
    await seed(openReport());
    await assertSucceeds(updateDoc(ref(CARA), { goneReports: [CARA] }));
  });

  it("tek bir yoldan geçen işareti kapatamaz", async () => {
    await seed(openReport());
    await assertFails(updateDoc(ref(CARA), { goneReports: [CARA], ...closeFields("gone") }));
  });

  it(`${contract.goneThreshold}. farklı kişi işareti kapatabilir`, async () => {
    await seed(openReport({ goneReports: [BOB] }));
    await assertSucceeds(updateDoc(ref(CARA), { goneReports: [BOB, CARA], ...closeFields("gone") }));
  });

  it("aynı kişi iki kez bildiremez ya da başkası adına bildiremez", async () => {
    await seed(openReport({ goneReports: [CARA] }));
    await assertFails(updateDoc(ref(CARA), { goneReports: [CARA, CARA] }));
    await assertFails(updateDoc(ref(CARA), { goneReports: [CARA, BOB] }));
  });

  it("işareti koyan ya da ilgilenen kişi tek başına kapatabilir", async () => {
    await seed(openReport());
    await assertSucceeds(updateDoc(ref(ALICE), { goneReports: [ALICE], ...closeFields("gone") }));
    await seed(claimedReport(BOB));
    await assertSucceeds(updateDoc(ref(BOB), { goneReports: [BOB], ...closeFields("gone") }));
  });
});

describe("Geri al (delete)", () => {
  it("kimse dokunmadıysa işareti koyan silebilir", async () => {
    await seed(openReport());
    await assertSucceeds(deleteDoc(ref(ALICE)));
  });

  it("başkası silemez; üzerinde işlem yapılmışsa silinemez", async () => {
    await seed(openReport());
    await assertFails(deleteDoc(ref(BOB)));
    await seed(claimedReport(BOB));
    await assertFails(deleteDoc(ref(ALICE)));
    await seed(openReport({ goneReports: [CARA] }));
    await assertFails(deleteDoc(ref(ALICE)));
  });
});

describe("yalnızca değişen alanlar yazılmalı", () => {
  // iOS, Timestamp'i Date'e çevirip geri yazdığında değer mikro saniye kayabilir. Kurallar
  // değişmemesi gereken alanları diff ile denetlediği için istemci yalnızca değişen alanları yazar
  // (FirestoreReportMapper.changes / Report.changedFields).
  it("değişmemiş zaman damgası 1 µs kaysa bile değişmiş sayılır ve reddedilir", async () => {
    const seen = Timestamp.fromMillis(Date.now() - 10 * MINUTE);
    const createdAt = new Timestamp(seen.seconds, 123_456_000);
    const stored = openReport({ createdAt, lastSeenAt: createdAt, expiresAt: ts(createdAt.toMillis() + 24 * HOUR) });
    await seed(stored);

    const drifted = new Timestamp(createdAt.seconds, createdAt.nanoseconds - 1_000);
    await assertFails(setDoc(ref(BOB), { ...stored, ...claimFields(BOB), createdAt: drifted, lastSeenAt: drifted }));
    await assertSucceeds(updateDoc(ref(BOB), claimFields(BOB)));
  });
});
