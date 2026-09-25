import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  type RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  Timestamp,
  collection,
  deleteDoc,
  doc,
  documentId,
  getDoc,
  getDocFromServer,
  getDocs,
  query,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
  writeBatch,
  type DocumentData,
  type Firestore,
} from "firebase/firestore";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import {
  ALICE,
  BOB,
  CARA,
  DAVE,
  DAY,
  HOUR,
  MINUTE,
  ROOT,
  agedUser,
  claimFields,
  claimedReport,
  clearedClaim,
  clearedClosing,
  closeFields,
  closeReset,
  closeSpend,
  closingFields,
  closingReport,
  contract,
  createReset,
  createSpend,
  createWithSpend,
  newUser,
  newUserFields,
  openReport,
  ts,
  updateWithSpend,
  userRecord,
  type Need,
} from "./helpers";

let env: RulesTestEnvironment;
const ID = "r1";

// Her kullanıcı için tek istemci: her çağrıda yeni bağlantı kurmak testleri çok yavaşlatıyor.
const clients = new Map<string, Firestore>();
function db(uid: string) {
  let client = clients.get(uid);
  if (!client) {
    client = env.authenticatedContext(uid).firestore() as unknown as Firestore;
    clients.set(uid, client);
  }
  return client;
}
const ref = (uid: string, id = ID) => doc(db(uid), contract.collection, id);
const userRef = (uid: string, of = uid) => doc(db(uid), contract.usersCollection, of);

const LIFETIME = contract.needs.injured.lifetimeHours * HOUR; // openReport'un ihtiyacı
const STALE = contract.claimStaleMinutes;
const UNDO = contract.undoMinutes;

async function seed(data: Record<string, unknown>, id = ID) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), contract.collection, id), data);
  });
}

async function seedUser(uid: string, data: Record<string, unknown> = agedUser()) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), contract.usersCollection, uid), data);
  });
}

/** Dokümanın sunucudaki hâli. İşaretleri giriş yapmış herkes okuyabildiği için onlar hazır bir
 *  istemciyle okunur (her seferinde kuralsız bağlam açmak yavaş); users kuralsız bağlamdan okunur. */
async function stored(path = `${contract.collection}/${ID}`): Promise<DocumentData | undefined> {
  if (path.startsWith(`${contract.collection}/`)) {
    return (await getDocFromServer(doc(db("okuyucu"), path))).data();
  }
  let data: DocumentData | undefined;
  await env.withSecurityRulesDisabled(async (ctx) => {
    data = (await getDoc(doc(ctx.firestore(), path))).data();
  });
  return data;
}

/** Uygulamanın yaptığı gibi: işaret + bu işaret için harcanan hak, tek toplu yazımda. */
const create = (uid: string, data: Record<string, unknown> = openReport(), id = ID, spend?: Record<string, unknown> | null) =>
  createWithSpend(db(uid), uid, id, data, spend);

/** `minutesAgo` dakika önce başlamış, hâlâ geçerli sahiplik alanları. */
function claimOf(userId: string, minutesAgo = 10) {
  const claimedAt = Date.now() - minutesAgo * MINUTE;
  return { claimedBy: userId, claimedAt: ts(claimedAt), claimExpiresAt: ts(claimedAt + contract.claimHours * HOUR) };
}

/** `hoursAgo` saat önce görülmüş, ömrü ihtiyacın süresi kadar olan işaretin zaman alanları. */
function seenAgo(hoursAgo: number) {
  const seen = Date.now() - hoursAgo * HOUR;
  return { createdAt: ts(seen), lastSeenAt: ts(seen), expiresAt: ts(seen + LIFETIME) };
}

/** "Hâlâ orada" yazımı; seenBy verilirse o da yazılır. */
function confirm(seenBy?: string[]) {
  const now = Date.now();
  return { lastSeenAt: ts(now), expiresAt: ts(now + LIFETIME), ...(seenBy ? { seenBy } : {}) };
}

/** `uid`'nin "Hâlâ yardım gerekiyor" yazımı (kurallardaki isObjection'ın beklediği biçim). */
function objection(uid: string, before: DocumentData, extra: Record<string, unknown> = {}) {
  const now = Date.now();
  const seenBy = before.seenBy as string[];
  const objectors = before.objectors as string[];
  return {
    status: "open",
    ...clearedClosing,
    ...clearedClaim,
    goneReports: [],
    disputed: [...(before.disputed as string[]), before.closingBy],
    objectors: uid === before.reporterId ? objectors : [...objectors, uid],
    lastSeenAt: ts(now),
    expiresAt: ts(now + LIFETIME),
    seenBy: seenBy.includes(uid) ? seenBy : [...seenBy, uid],
    ...extra,
  };
}

const release = { status: "open", ...clearedClaim };
const undo = { status: "open", ...clearedClosing, ...clearedClaim };
/** Geçerli sahiplik varken "Geri al": sahiplik alanlarına dokunulmaz, işaret yeniden 'claimed' olur. */
const undoKeepingClaim = { status: "claimed", ...clearedClosing };

beforeAll(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-patiharita-rules",
    firestore: { rules: readFileSync(resolve(ROOT, "firebase", "firestore.rules"), "utf8") },
  });
});
afterAll(async () => {
  clients.clear();
  await env.cleanup();
});
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

describe("users/{uid}: hesap kaydı", () => {
  it("kişi kendi kaydını sunucu saatiyle, sıfır sayaçla oluşturabilir", async () => {
    await assertSucceeds(setDoc(userRef(ALICE), newUserFields()));
    const user = (await stored(`${contract.usersCollection}/${ALICE}`))!;
    expect(user.createUsed).toBe(0);
    expect(user.createdAt.toMillis()).toBe(user.createWindow.toMillis());
  });

  it("başkası adına kayıt oluşturulamaz", async () => {
    await assertFails(setDoc(userRef(BOB, ALICE), newUserFields()));
    await assertFails(setDoc(doc(env.unauthenticatedContext().firestore(), contract.usersCollection, ALICE), newUserFields()));
  });

  it("hesap yaşı ve pencereler sunucu saatinde başlar; sayaçlar sıfır, harcamalar boş", async () => {
    const now = Date.now();
    await assertFails(setDoc(userRef(ALICE), { ...newUserFields(), createdAt: ts(now) }));
    await assertFails(setDoc(userRef(ALICE), { ...newUserFields(), createdAt: ts(now - 3 * DAY) }));
    await assertFails(setDoc(userRef(ALICE), { ...newUserFields(), createWindow: ts(now) }));
    await assertFails(setDoc(userRef(ALICE), { ...newUserFields(), closeWindow: ts(now) }));
    await assertFails(setDoc(userRef(ALICE), { ...newUserFields(), createUsed: -5 }));
    await assertFails(setDoc(userRef(ALICE), { ...newUserFields(), closeUsed: -5 }));
    await assertFails(setDoc(userRef(ALICE), { ...newUserFields(), createLast: { t: serverTimestamp(), id: ID } }));
    await assertFails(setDoc(userRef(ALICE), { ...newUserFields(), closeLast: { t: serverTimestamp(), id: ID, w: 2 } }));
  });

  it("eksik ya da fazla alan reddedilir (ör. banned istemciden yazılamaz)", async () => {
    const { closeLast: _omit, ...missing } = newUserFields();
    await assertFails(setDoc(userRef(ALICE), missing));
    await assertFails(setDoc(userRef(ALICE), { ...newUserFields(), banned: false }));
  });

  it("kayıt yalnızca sahibince okunur; listelenemez", async () => {
    await seedUser(ALICE);
    await assertSucceeds(getDoc(userRef(ALICE)));
    await assertFails(getDoc(userRef(BOB, ALICE)));
    await assertFails(getDocs(collection(db(ALICE), contract.usersCollection)));
    // Yalnızca kendi dokümanını hedefleyen bir sorgu bile liste sayılır.
    await assertFails(getDocs(query(collection(db(ALICE), contract.usersCollection), where(documentId(), "==", ALICE))));
    await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), contract.usersCollection, ALICE)));
  });

  it("kayıt silinemez, yeniden oluşturularak sıfırlanamaz", async () => {
    await seedUser(ALICE, newUser({ createUsed: 5 }));
    await assertFails(deleteDoc(userRef(ALICE)));
    await assertFails(setDoc(userRef(ALICE), newUserFields()));
  });

  it("createdAt değiştirilemez", async () => {
    await seedUser(ALICE, newUser());
    await assertFails(updateDoc(userRef(ALICE), { createdAt: ts(Date.now() - 3 * DAY) }));
    await assertFails(updateDoc(userRef(ALICE), { ...createSpend("x"), createdAt: ts(Date.now() - 3 * DAY) }));
    await assertFails(updateDoc(userRef(ALICE), { ...closeSpend("x", 1), createdAt: serverTimestamp() }));
  });
});

describe("users/{uid}: yeni işaret hakkı harcama", () => {
  it("aynı pencerede sayaç tam 1 artar", async () => {
    await seedUser(ALICE, agedUser({ createUsed: 3 }));
    await assertFails(updateDoc(userRef(ALICE), createSpend("x", 3)));
    await assertFails(updateDoc(userRef(ALICE), createSpend("x", 5)));
    await assertFails(updateDoc(userRef(ALICE), createSpend("x", 2)));
    await assertSucceeds(updateDoc(userRef(ALICE), createSpend("x", 4)));
    await assertSucceeds(updateDoc(userRef(ALICE), createSpend("y")));
    expect((await stored(`${contract.usersCollection}/${ALICE}`))!.createUsed).toBe(5);
  });

  it("createLast yalnızca sunucu saatli t ve bir işaret kimliği içerir", async () => {
    await seedUser(ALICE);
    await assertFails(updateDoc(userRef(ALICE), { createUsed: 1, createLast: { t: ts(Date.now()), id: "x" } }));
    await assertFails(updateDoc(userRef(ALICE), { createUsed: 1, createLast: { t: serverTimestamp() } }));
    await assertFails(updateDoc(userRef(ALICE), { createUsed: 1, createLast: { t: serverTimestamp(), id: 7 } }));
    await assertFails(updateDoc(userRef(ALICE), { createUsed: 1, createLast: { t: serverTimestamp(), id: "x", w: 1 } }));
    await assertFails(updateDoc(userRef(ALICE), { createUsed: 1, createLast: null }));
    await assertFails(updateDoc(userRef(ALICE), { createUsed: 1 }));
  });

  it("pencere 24 saat dolmadan sıfırlanamaz; dolduktan sonra sıfırlanır", async () => {
    await seedUser(ALICE, agedUser({ createWindow: ts(Date.now() - 23 * HOUR), createUsed: 10 }));
    await assertFails(updateDoc(userRef(ALICE), createReset("x")));
    await seedUser(ALICE, agedUser({ createWindow: ts(Date.now() - 25 * HOUR), createUsed: 10 }));
    await assertSucceeds(updateDoc(userRef(ALICE), createReset("x")));
  });

  it("yeni pencere sunucu saatinde ve 1 hakla başlar", async () => {
    await seedUser(ALICE, agedUser({ createWindow: ts(Date.now() - 25 * HOUR), createUsed: 10 }));
    await assertFails(updateDoc(userRef(ALICE), { ...createReset("x"), createWindow: ts(Date.now()) }));
    await assertFails(updateDoc(userRef(ALICE), { ...createReset("x"), createUsed: 2 }));
    await assertFails(updateDoc(userRef(ALICE), { ...createReset("x"), createUsed: 0 }));
  });

  it("pencere dolduktan sonra aynı pencerede artırmak da serbest (yalnızca daha kısıtlayıcı)", async () => {
    await seedUser(ALICE, agedUser({ createWindow: ts(Date.now() - 25 * HOUR), createUsed: 3 }));
    await assertSucceeds(updateDoc(userRef(ALICE), createSpend("x")));
  });

  it("başkasının hakkı harcanamaz", async () => {
    await seedUser(ALICE);
    await assertFails(updateDoc(userRef(BOB, ALICE), createSpend("x")));
  });

  it("işaret ve kapatma harcaması aynı yazımda birleştirilemez", async () => {
    await seedUser(ALICE);
    await assertFails(updateDoc(userRef(ALICE), { ...createSpend("x"), ...closeSpend("x", 1) }));
  });
});

describe("users/{uid}: kanıtlı kapatma puanı harcama", () => {
  it("aynı pencerede puan w kadar artar; w 1 ya da 2", async () => {
    await seedUser(ALICE, agedUser({ closeUsed: 2 }));
    await assertFails(updateDoc(userRef(ALICE), closeSpend("x", 3)));
    await assertFails(updateDoc(userRef(ALICE), closeSpend("x", 0)));
    await assertFails(updateDoc(userRef(ALICE), closeSpend("x", 1.5)));
    await assertFails(updateDoc(userRef(ALICE), closeSpend("x", 2, 3)));
    await assertFails(updateDoc(userRef(ALICE), closeSpend("x", 1, 2)));
    await assertSucceeds(updateDoc(userRef(ALICE), closeSpend("x", 2, 4)));
    await assertSucceeds(updateDoc(userRef(ALICE), closeSpend("y", 1)));
    expect((await stored(`${contract.usersCollection}/${ALICE}`))!.closeUsed).toBe(5);
  });

  it(`pencerede en fazla ${contract.closeBudget.points} puan harcanır`, async () => {
    const points = contract.closeBudget.points;
    await seedUser(ALICE, agedUser({ closeUsed: points - 2 }));
    await assertSucceeds(updateDoc(userRef(ALICE), closeSpend("x", 2)));
    await seedUser(ALICE, agedUser({ closeUsed: points - 1 }));
    await assertFails(updateDoc(userRef(ALICE), closeSpend("x", 2)));
    await assertSucceeds(updateDoc(userRef(ALICE), closeSpend("x", 1)));
    await assertFails(updateDoc(userRef(ALICE), closeSpend("y", 1)));
  });

  it("closeLast yalnızca sunucu saatli t, işaret kimliği ve w içerir", async () => {
    await seedUser(ALICE);
    await assertFails(updateDoc(userRef(ALICE), { closeUsed: 2, closeLast: { t: ts(Date.now()), id: "x", w: 2 } }));
    await assertFails(updateDoc(userRef(ALICE), { closeUsed: 2, closeLast: { t: serverTimestamp(), id: "x" } }));
    await assertFails(updateDoc(userRef(ALICE), { closeUsed: 2, closeLast: { t: serverTimestamp(), id: "x", w: 2, n: 1 } }));
  });

  it("pencere 24 saat dolmadan sıfırlanamaz; dolduktan sonra sıfırlanır", async () => {
    const points = contract.closeBudget.points;
    await seedUser(ALICE, agedUser({ closeWindow: ts(Date.now() - 23 * HOUR), closeUsed: points }));
    await assertFails(updateDoc(userRef(ALICE), closeReset("x", 2)));
    await seedUser(ALICE, agedUser({ closeWindow: ts(Date.now() - 25 * HOUR), closeUsed: points }));
    await assertFails(updateDoc(userRef(ALICE), closeSpend("x", 2)));
    await assertFails(updateDoc(userRef(ALICE), { ...closeReset("x", 2), closeUsed: 3 }));
    await assertFails(updateDoc(userRef(ALICE), { ...closeReset("x", 2), closeWindow: ts(Date.now()) }));
    await assertSucceeds(updateDoc(userRef(ALICE), closeReset("x", 2)));
  });

  it("pencere dolduktan sonra aynı pencerede artırmak da serbest (yalnızca daha kısıtlayıcı)", async () => {
    await seedUser(ALICE, agedUser({ closeWindow: ts(Date.now() - 25 * HOUR), closeUsed: 2 }));
    await assertSucceeds(updateDoc(userRef(ALICE), closeSpend("x", 2)));
    expect((await stored(`${contract.usersCollection}/${ALICE}`))!.closeUsed).toBe(4);
  });
});

describe("işaret oluşturma", () => {
  beforeEach(() => seedUser(ALICE));

  it("geçerli bir işaret, aynı toplu yazımda harcanan hakla oluşturulabilir", async () => {
    await assertSucceeds(create(ALICE));
    const user = (await stored(`${contract.usersCollection}/${ALICE}`))!;
    expect(user.createUsed).toBe(1);
    expect(user.createLast.id).toBe(ID);
  });

  it("hak harcanmadan işaret oluşturulamaz", async () => {
    await assertFails(setDoc(ref(ALICE), openReport()));
    await assertFails(create(ALICE, openReport(), ID, null));
  });

  it("users kaydı olmayan kişi işaret oluşturamaz", async () => {
    await assertFails(setDoc(ref(DAVE), openReport({ reporterId: DAVE, seenBy: [DAVE] })));
  });

  // Uygulama users/{me}'yi hiç görmediyse işaretten önce kaydı oluşturan yazımı sıraya koyar
  // (FirestoreReportRepository.create): kayıt yoksa oluşur, varsa reddedilir ve zararsızdır.
  it("kayıt oluşturma sıraya konunca ardından gelen aynı pencere harcamalı işaret kabul edilir", async () => {
    const daves = () => openReport({ reporterId: DAVE, seenBy: [DAVE] });
    await assertFails(create(DAVE, daves(), "d1"));
    await assertSucceeds(setDoc(userRef(DAVE), newUserFields()));
    await assertSucceeds(create(DAVE, daves(), "d1"));
    // Kayıt zaten varken ön yazım reddedilir; sonraki işaretin artışı gerçek kayda uygulanır.
    await assertFails(setDoc(userRef(DAVE), newUserFields()));
    await assertSucceeds(create(DAVE, daves(), "d2"));
    const user = (await stored(`${contract.usersCollection}/${DAVE}`))!;
    expect(user.createUsed).toBe(2);
    expect(user.createLast.id).toBe("d2");
  });

  it("başkası adına işaret oluşturulamaz", async () => {
    await seedUser(BOB);
    await assertFails(create(BOB, openReport()));
  });

  it("çevrimdışı işaretlenip geç senkronlanan kayıt kabul edilir", async () => {
    const seenAt = Date.now() - 3 * HOUR;
    await assertSucceeds(
      create(ALICE, openReport({ createdAt: ts(seenAt), lastSeenAt: ts(seenAt), expiresAt: ts(seenAt + 24 * HOUR) })),
    );
  });

  it("çok eski ya da gelecekteki zaman damgası reddedilir", async () => {
    const old = Date.now() - (contract.maxBackdateHours + 1) * HOUR;
    await assertFails(create(ALICE, openReport({ createdAt: ts(old), lastSeenAt: ts(old), expiresAt: ts(old + 24 * HOUR) })));
    const future = Date.now() + 2 * HOUR;
    await assertFails(
      create(ALICE, openReport({ createdAt: ts(future), lastSeenAt: ts(future), expiresAt: ts(future + 24 * HOUR) })),
    );
  });

  it("doğrudan 'claimed', 'closing' ya da 'closed' olarak oluşturulamaz", async () => {
    await assertFails(create(ALICE, claimedReport(ALICE)));
    await assertFails(create(ALICE, closingReport(ALICE)));
    await assertFails(create(ALICE, openReport(closeFields("resolved"))));
  });

  it("eksik, fazla ya da hatalı alanlar reddedilir", async () => {
    const { geohash: _omit, ...missing } = openReport();
    await assertFails(create(ALICE, missing));
    const { closingCredible: _omit2, ...noCredible } = openReport();
    await assertFails(create(ALICE, noCredible));
    await assertFails(create(ALICE, openReport({ note: "uzun açıklama" })));
    await assertFails(create(ALICE, openReport({ species: "fish" })));
    await assertFails(create(ALICE, openReport({ need: "toys" })));
    await assertFails(create(ALICE, openReport({ lat: 91 })));
    await assertFails(create(ALICE, openReport({ geohash: "sxk9hw43ba" }))); // 'a' geohash alfabesinde yok
    await assertFails(create(ALICE, openReport({ goneReports: [BOB] })));
    await assertFails(create(ALICE, openReport({ objectors: [BOB] })));
    await assertFails(create(ALICE, openReport({ disputed: [BOB] })));
    await assertFails(create(ALICE, openReport({ objectors: null })));
    await assertFails(create(ALICE, openReport({ closingCredible: false })));
    await assertFails(create(ALICE, openReport({ closingReason: "resolved", closingBy: ALICE, closingAt: ts(Date.now()), closingCredible: false })));
    await assertSucceeds(create(ALICE));
  });

  it("\"kaç kişi bildirdi\" listesi yalnızca bildiren kişiyle başlar", async () => {
    const { seenBy: _omit, ...missing } = openReport();
    await assertFails(create(ALICE, missing));
    await assertFails(create(ALICE, openReport({ seenBy: [] })));
    await assertFails(create(ALICE, openReport({ seenBy: ALICE })));
    await assertFails(create(ALICE, openReport({ seenBy: [BOB] })));
    await assertFails(create(ALICE, openReport({ seenBy: [ALICE, BOB] })));
    await assertSucceeds(create(ALICE, openReport({ seenBy: [ALICE] })));
  });

  it("sözleşmedeki her tür kabul edilir", async () => {
    for (const species of contract.species) {
      await assertSucceeds(create(ALICE, openReport({ species }), `s-${species}`));
    }
  });

  it("her ihtiyacın ömrü sözleşmeyle aynı sınırda uygulanır", async () => {
    for (const [need, { lifetimeHours }] of Object.entries(contract.needs)) {
      const now = Date.now();
      const base = { need, createdAt: ts(now), lastSeenAt: ts(now) };
      await assertSucceeds(create(ALICE, openReport({ ...base, expiresAt: ts(now + lifetimeHours * HOUR) }), `ok-${need}`));
      await assertFails(
        create(ALICE, openReport({ ...base, expiresAt: ts(now + lifetimeHours * HOUR + 2 * MINUTE) }), `long-${need}`),
      );
    }
  });
});

describe("günlük yeni işaret hakkı", () => {
  const { perWindow, firstDay } = contract.createQuota;

  it(`${contract.newAccountHours} saatten genç hesap en fazla ${firstDay} işaret koyar`, async () => {
    await seedUser(ALICE, newUser({ createUsed: firstDay - 1 }));
    await assertSucceeds(create(ALICE, openReport(), `a${firstDay}`));
    await assertFails(create(ALICE, openReport(), `a${firstDay + 1}`));
  });

  it(`eski hesap 24 saatte en fazla ${perWindow} işaret koyar`, async () => {
    await seedUser(ALICE, agedUser({ createUsed: firstDay }));
    await assertSucceeds(create(ALICE, openReport(), `a${firstDay + 1}`));
    await seedUser(ALICE, agedUser({ createUsed: perWindow - 1 }));
    await assertSucceeds(create(ALICE, openReport(), `a${perWindow}`));
    await assertFails(create(ALICE, openReport(), `a${perWindow + 1}`));
  });

  it("24 saat dolunca hak yenilenir (yeni pencere)", async () => {
    await seedUser(ALICE, agedUser({ createWindow: ts(Date.now() - 25 * HOUR), createUsed: perWindow }));
    await assertFails(create(ALICE, openReport(), ID, createSpend(ID)));
    await assertSucceeds(create(ALICE, openReport(), ID, createReset(ID)));
  });

  it("pencere dolmadan sıfırlayarak fazladan işaret konamaz", async () => {
    await seedUser(ALICE, agedUser({ createWindow: ts(Date.now() - 23 * HOUR), createUsed: perWindow }));
    await assertFails(create(ALICE, openReport(), ID, createReset(ID)));
  });

  it("tek harcama bir toplu yazımda iki işarete yetmez", async () => {
    await seedUser(ALICE);
    for (const paidFor of ["r1", "r2"]) {
      const d = db(ALICE);
      const batch = writeBatch(d);
      batch.set(doc(d, contract.collection, "r1"), openReport());
      batch.set(doc(d, contract.collection, "r2"), openReport());
      batch.update(doc(d, contract.usersCollection, ALICE), createSpend(paidFor));
      await assertFails(batch.commit());
    }
    await assertSucceeds(create(ALICE, openReport(), "r1"));
    await assertSucceeds(create(ALICE, openReport(), "r2"));
  });

  it("harcama başka bir işareti gösteriyorsa işaret oluşturulamaz", async () => {
    await seedUser(ALICE);
    await assertFails(create(ALICE, openReport(), "r1", createSpend("r2")));
  });

  it("harcama anı sunucu saati değilse reddedilir", async () => {
    await seedUser(ALICE);
    await assertFails(create(ALICE, openReport(), ID, { createUsed: 1, createLast: { t: ts(Date.now()), id: ID } }));
  });

  it("daha önce yapılmış bir harcama yeni işarete yetmez", async () => {
    await seedUser(ALICE, agedUser({ createUsed: 1, createLast: { t: ts(Date.now() - MINUTE), id: ID } }));
    await assertFails(setDoc(ref(ALICE), openReport()));
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
    await seed(claimedReport(BOB, {}, 2 * 60));
    await assertFails(updateDoc(ref(CARA), claimFields(CARA)));
  });

  it("süresi dolmuş sahiplik devralınabilir", async () => {
    await seed(claimedReport(BOB, {}, 4 * 60));
    await assertSucceeds(updateDoc(ref(CARA), claimFields(CARA)));
  });

  it("sahiplik anı sunucu saati olmalı", async () => {
    await seed(openReport());
    const now = Date.now();
    await assertFails(updateDoc(ref(BOB), { ...claimFields(BOB), claimedAt: ts(now) }));
    await assertFails(updateDoc(ref(BOB), { ...claimFields(BOB), claimedAt: ts(now - STALE * MINUTE) }));
    await assertSucceeds(updateDoc(ref(BOB), claimFields(BOB)));
    expect((await stored())!.claimedAt).toBeInstanceOf(Timestamp);
  });

  it("sahiplik süresi sözleşmedekinden (saat farkı payıyla) uzun olamaz", async () => {
    await seed(openReport());
    const now = Date.now();
    const limit = contract.claimHours * HOUR + contract.clockSkewMinutes * MINUTE;
    await assertFails(updateDoc(ref(BOB), { ...claimFields(BOB, now), claimExpiresAt: ts(now + limit + MINUTE) }));
    await assertFails(updateDoc(ref(BOB), { ...claimFields(BOB, now), claimExpiresAt: ts(now - MINUTE) }));
    // İstemci saati birkaç dakika ileride olabilir.
    await assertSucceeds(updateDoc(ref(BOB), { ...claimFields(BOB, now), claimExpiresAt: ts(now + limit - 5 * MINUTE) }));
  });

  it("başkası adına ya da başka alanlara dokunarak sahiplenilemez", async () => {
    await seed(openReport());
    await assertFails(updateDoc(ref(BOB), claimFields(CARA)));
    await assertFails(updateDoc(ref(BOB), { ...claimFields(BOB), need: "food" }));
    await assertFails(updateDoc(ref(BOB), { ...claimFields(BOB), lat: 41.1 }));
    await assertFails(updateDoc(ref(BOB), { ...claimFields(BOB), goneReports: [] , disputed: [BOB] }));
  });

  it("itiraz almış kapatan kişi bu işarette ilgilenemez", async () => {
    await seed(openReport({ disputed: [BOB], objectors: [CARA] }));
    await assertFails(updateDoc(ref(BOB), claimFields(BOB)));
    await assertSucceeds(updateDoc(ref(CARA), claimFields(CARA)));
  });

  it(`ömür, oluşturulmasından ${contract.maxReportAgeDays} gün sonrasını geçemez`, async () => {
    const created = Date.now() - contract.maxReportAgeDays * DAY + HOUR;
    const cap = created + contract.maxReportAgeDays * DAY;
    await seed(openReport({ createdAt: ts(created), lastSeenAt: ts(Date.now() - HOUR), expiresAt: ts(Date.now() + 30 * MINUTE) }));
    const claim = claimFields(BOB);
    await assertFails(updateDoc(ref(BOB), { ...claim, expiresAt: claim.claimExpiresAt }));
    await assertSucceeds(updateDoc(ref(BOB), { ...claim, expiresAt: ts(cap) }));
  });

  it("süresi dolmuş ya da 'Çözüldü dendi' işaret üstüne alınamaz", async () => {
    await seed(openReport(seenAgo(25)));
    await assertFails(updateDoc(ref(BOB), claimFields(BOB)));
    await seed(closingReport(CARA));
    await assertFails(updateDoc(ref(BOB), claimFields(BOB)));
  });
});

describe("Vazgeç (release)", () => {
  it("ilgilenen kişi her zaman bırakabilir", async () => {
    await seed(claimedReport(BOB));
    await assertSucceeds(updateDoc(ref(BOB), release));
    await seed(claimedReport(BOB, {}, 2 * 60));
    await assertSucceeds(updateDoc(ref(BOB), release));
  });

  it("başkası bırakamaz", async () => {
    await seed(claimedReport(BOB));
    await assertFails(updateDoc(ref(ALICE), release));
    await assertFails(updateDoc(ref(CARA), release));
    await seed(claimedReport(BOB, {}, STALE + 1));
    await assertFails(updateDoc(ref(CARA), release));
  });

  it(`işareti koyan, ${STALE} dk'dır haber vermeyen sahipliği bırakabilir ("İlgilenen gelmedi")`, async () => {
    await seed(claimedReport(BOB, {}, STALE - 2));
    await assertFails(updateDoc(ref(ALICE), release));
    await seed(claimedReport(BOB, {}, STALE + 1));
    await assertSucceeds(updateDoc(ref(ALICE), release));
  });
});

describe("Çözüldü (resolve)", () => {
  it("işareti koyan, başka gören yoksa hemen kapatabilir", async () => {
    await seed(openReport());
    await assertSucceeds(updateDoc(ref(ALICE), closeFields("resolved")));
    await seed(claimedReport(BOB));
    await assertSucceeds(updateDoc(ref(ALICE), closeFields("resolved")));
  });

  it("başkası da gördüyse koyanın 'Çözüldü'sü yalnızca 'Çözüldü dendi' olur", async () => {
    await seed(openReport({ seenBy: [ALICE, CARA] }));
    await assertFails(updateDoc(ref(ALICE), closeFields("resolved")));
    await assertSucceeds(updateDoc(ref(ALICE), closingFields(ALICE)));
  });

  it("ilgilenen kişinin 'Çözüldü'sü yalnızca 'Çözüldü dendi' olur", async () => {
    await seed(claimedReport(BOB));
    await assertFails(updateDoc(ref(BOB), closeFields("resolved")));
    await assertSucceeds(updateDoc(ref(BOB), closingFields(BOB)));
    const after = (await stored())!;
    expect(after.status).toBe("closing");
    expect(after.claimedBy).toBe(BOB); // zaman çizelgesi kartta gösterilir
  });

  it("ilgilenmeden de 'Çözüldü' denebilir", async () => {
    await seed(openReport());
    await assertFails(updateDoc(ref(CARA), closeFields("resolved")));
    await assertSucceeds(updateDoc(ref(CARA), closingFields(CARA)));
  });

  it(`başkasının sahipliği ${STALE} dk'dan tazeyse yalnızca koyan 'Çözüldü' diyebilir`, async () => {
    await seed(claimedReport(BOB, {}, STALE - 2));
    await assertFails(updateDoc(ref(CARA), closingFields(CARA)));
    await assertSucceeds(updateDoc(ref(ALICE), closingFields(ALICE)));
    await seed(claimedReport(BOB, {}, STALE + 1));
    await assertSucceeds(updateDoc(ref(CARA), closingFields(CARA)));
    // Sahipliği dolmuş işarette herkes.
    await seed(claimedReport(BOB, {}, 4 * 60));
    await assertSucceeds(updateDoc(ref(CARA), closingFields(CARA)));
  });

  it("kapatma anı sunucu saati olmalı", async () => {
    await seed(openReport());
    const now = Date.now();
    await assertFails(updateDoc(ref(CARA), { ...closingFields(CARA), closingAt: ts(now - 10 * MINUTE) }));
    await assertFails(updateDoc(ref(CARA), { ...closingFields(CARA), closingAt: ts(now) }));
  });

  it("kapatma önerisi ömrü değiştiremez, başkası adına ya da başka sebeple yapılamaz", async () => {
    await seed(openReport());
    await assertFails(updateDoc(ref(CARA), { ...closingFields(CARA), expiresAt: ts(Date.now() + HOUR) }));
    await assertFails(updateDoc(ref(CARA), { ...closingFields(CARA), expiresAt: ts(Date.now() + LIFETIME + HOUR) }));
    await assertFails(updateDoc(ref(CARA), closingFields(BOB)));
    await assertFails(updateDoc(ref(CARA), { ...closingFields(CARA), closingReason: "expired" }));
    await assertFails(updateDoc(ref(CARA), closingFields(CARA, "gone")));
    await assertFails(updateDoc(ref(CARA), { ...closingFields(CARA), closingCredible: null }));
    await assertFails(updateDoc(ref(CARA), { ...closingFields(CARA), claimedBy: CARA }));
  });

  it("itiraz almış kişi bu işarette yeniden 'Çözüldü' diyemez", async () => {
    await seed(openReport({ disputed: [CARA], objectors: [DAVE] }));
    await assertFails(updateDoc(ref(CARA), closingFields(CARA)));
    await assertSucceeds(updateDoc(ref(BOB), closingFields(BOB)));
  });

  it(`${contract.maxDisputed} itirazdan sonra kimse kapatma öneremez`, async () => {
    const disputed = Array.from({ length: contract.maxDisputed }, (_, i) => `d${i}`);
    await seed(openReport({ seenBy: [ALICE, CARA], disputed }));
    await assertFails(updateDoc(ref(CARA), closingFields(CARA)));
    await assertFails(updateDoc(ref(ALICE), closingFields(ALICE)));
    await seed(openReport({ seenBy: [ALICE, CARA], disputed: disputed.slice(1) }));
    await assertSucceeds(updateDoc(ref(CARA), closingFields(CARA)));
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
    await assertFails(updateDoc(ref(CARA), confirm()));
    await assertFails(updateDoc(ref(CARA), closingFields(CARA)));
    await seed(closingReport(BOB, "resolved", false, { ...seenAgo(25), ...closeFields("resolved") }));
    await assertFails(updateDoc(ref(CARA), objection(CARA, (await stored())!)));
    await assertFails(updateDoc(ref(CARA), closeFields("expired")));
  });
});

describe("kanıtlı kapatma (closingCredible)", () => {
  const credibleClose = (uid: string, w = contract.needs.injured.closeCost, id = ID) =>
    updateWithSpend(db(uid), uid, id, closingFields(uid, "resolved", true), closeSpend(id, w));

  it("en az 24 saatlik hesap, bu işaret için doğru puanı harcayınca kanıtlı kapatır", async () => {
    await seedUser(CARA);
    await seed(openReport());
    await assertSucceeds(credibleClose(CARA));
    expect((await stored())!.closingCredible).toBe(true);
    const user = (await stored(`${contract.usersCollection}/${CARA}`))!;
    expect(user.closeUsed).toBe(contract.needs.injured.closeCost);
    expect(user.closeLast.id).toBe(ID);
  });

  it("her ihtiyacın puanı sözleşmedeki closeCost", async () => {
    for (const [need, { closeCost }] of Object.entries(contract.needs) as [Need, { closeCost: number }][]) {
      await seedUser(CARA);
      const id = `n-${need}`;
      await seed(openReport({ need }), id);
      await assertFails(credibleClose(CARA, 3 - closeCost, id));
      await assertSucceeds(credibleClose(CARA, closeCost, id));
    }
  });

  it("puansız 'Çözüldü' users kaydı gerektirmez; kanıtlı olan gerektirir", async () => {
    await seed(openReport());
    await assertFails(updateDoc(ref(CARA), closingFields(CARA, "resolved", true)));
    await assertSucceeds(updateDoc(ref(CARA), closingFields(CARA, "resolved", false)));
  });

  it(`${contract.newAccountHours} saatten genç hesap başkasının işaretini kanıtlı kapatamaz`, async () => {
    await seedUser(CARA, userRecord({}, contract.newAccountHours * HOUR - HOUR));
    await seed(openReport());
    await assertFails(credibleClose(CARA));
    await assertSucceeds(updateDoc(ref(CARA), closingFields(CARA)));
  });

  it("işareti koyan, genç hesapla da kendi işaretini kanıtlı kapatır", async () => {
    await seedUser(ALICE, newUser());
    await seed(openReport({ seenBy: [ALICE, CARA] }));
    await assertSucceeds(credibleClose(ALICE));
  });

  it("harcama başka bir işareti ya da eski bir anı gösteriyorsa reddedilir", async () => {
    await seedUser(CARA);
    await seed(openReport());
    await assertFails(updateWithSpend(db(CARA), CARA, ID, closingFields(CARA, "resolved", true), closeSpend("r2", 2)));
    await seedUser(CARA, agedUser({ closeUsed: 2, closeLast: { t: ts(Date.now() - MINUTE), id: ID, w: 2 } }));
    await assertFails(updateDoc(ref(CARA), closingFields(CARA, "resolved", true)));
  });

  it("ağır ihtiyaçta 1 puanlık harcama yetmez", async () => {
    await seedUser(CARA);
    await seed(openReport({ need: "injured" }));
    await assertFails(credibleClose(CARA, 1));
  });

  it(`${contract.closeBudget.points + 1}. puan harcanamaz`, async () => {
    await seedUser(CARA, agedUser({ closeUsed: contract.closeBudget.points - 1 }));
    await seed(openReport({ need: "injured" }));
    await assertFails(credibleClose(CARA, 2));
    await seed(openReport({ need: "food" }));
    await assertSucceeds(credibleClose(CARA, 1));
  });

  it("tek harcama bir toplu yazımda iki işarete yetmez", async () => {
    await seedUser(CARA);
    await seed(openReport(), "r1");
    await seed(openReport(), "r2");
    const d = db(CARA);
    const batch = writeBatch(d);
    batch.update(doc(d, contract.collection, "r1"), closingFields(CARA, "resolved", true));
    batch.update(doc(d, contract.collection, "r2"), closingFields(CARA, "resolved", true));
    batch.update(doc(d, contract.usersCollection, CARA), closeSpend("r1", 2));
    await assertFails(batch.commit());
  });

  it(`${contract.closeBudget.maxDisputed + 1} itiraz almış işarette kapatma kanıtlı sayılmaz`, async () => {
    await seedUser(CARA);
    await seed(openReport({ disputed: [BOB, DAVE] }));
    await assertFails(credibleClose(CARA));
    await assertSucceeds(updateDoc(ref(CARA), closingFields(CARA)));
    await seed(openReport({ disputed: [BOB] }));
    await assertSucceeds(credibleClose(CARA));
  });

  it("pencere sınırında: dolmuş pencerede yeni pencereyle kapatılır, dolmamışta sıfırlanamaz", async () => {
    const points = contract.closeBudget.points;
    await seedUser(CARA, agedUser({ closeWindow: ts(Date.now() - 25 * HOUR), closeUsed: points }));
    await seed(openReport());
    await assertFails(credibleClose(CARA));
    await assertSucceeds(updateWithSpend(db(CARA), CARA, ID, closingFields(CARA, "resolved", true), closeReset(ID, 2)));
    await seedUser(CARA, agedUser({ closeWindow: ts(Date.now() - 23 * HOUR), closeUsed: points }));
    await seed(openReport());
    await assertFails(updateWithSpend(db(CARA), CARA, ID, closingFields(CARA, "resolved", true), closeReset(ID, 2)));
  });

  it("3. 'Artık yok' oyu da kanıtlı olabilir", async () => {
    await seedUser(CARA);
    await seed(openReport({ goneReports: [BOB, DAVE] }));
    await assertSucceeds(
      updateWithSpend(
        db(CARA),
        CARA,
        ID,
        { goneReports: [BOB, DAVE, CARA], ...closingFields(CARA, "gone", true) },
        closeSpend(ID, 2),
      ),
    );
  });

  it("closingCredible yalnızca itiraz ve geri alma ile (null olarak) değişir", async () => {
    await seedUser(BOB);
    await seed(closingReport(BOB, "resolved", false));
    await assertFails(updateDoc(ref(BOB), { closingCredible: true }));
    await assertFails(updateWithSpend(db(BOB), BOB, ID, { closingCredible: true }, closeSpend(ID, 2)));
    await assertFails(updateDoc(ref(CARA), { closingCredible: true }));
    await seed(closingReport(BOB, "resolved", true));
    await assertFails(updateDoc(ref(BOB), { closingCredible: false }));
    await assertFails(updateDoc(ref(ALICE), { closingCredible: false }));
    await assertFails(updateDoc(ref(BOB), { ...undo, closingCredible: true }));
    await assertSucceeds(updateDoc(ref(BOB), undo));
  });
});

describe("Hâlâ orada (confirm)", () => {
  it("herkes ömrü ihtiyacın süresi kadar uzatabilir", async () => {
    await seed(openReport(seenAgo(20)));
    await assertSucceeds(updateDoc(ref(CARA), confirm()));
  });

  it("ihtiyacın süresinden fazla uzatılamaz ya da kısaltılamaz", async () => {
    await seed(openReport(seenAgo(20)));
    const now = Date.now();
    await assertFails(updateDoc(ref(CARA), { lastSeenAt: ts(now), expiresAt: ts(now + 48 * HOUR) }));
    await assertFails(updateDoc(ref(CARA), { lastSeenAt: ts(now), expiresAt: ts(now + HOUR) }));
  });

  it("eski 'Artık yok' oylarını sıfırlayabilir, başka türlü değiştiremez", async () => {
    await seed(openReport({ ...seenAgo(20), goneReports: [BOB, DAVE] }));
    await assertFails(updateDoc(ref(CARA), { ...confirm(), goneReports: [BOB] }));
    await assertFails(updateDoc(ref(CARA), { ...confirm(), goneReports: [BOB, DAVE, CARA] }));
    await assertFails(updateDoc(ref(CARA), { goneReports: [] }));
    await assertSucceeds(updateDoc(ref(CARA), { ...confirm([ALICE, CARA]), goneReports: [] }));
  });

  it("süresi dolmuş işaret yeniden canlandırılamaz", async () => {
    await seed(openReport(seenAgo(25)));
    await assertFails(updateDoc(ref(CARA), confirm()));
    await assertFails(updateDoc(ref(ALICE), confirm()));
  });

  it(`ömür, oluşturulmasından ${contract.maxReportAgeDays} gün sonrasını geçemez`, async () => {
    const created = Date.now() - contract.maxReportAgeDays * DAY + 2 * HOUR;
    await seed(openReport({ createdAt: ts(created), lastSeenAt: ts(Date.now() - HOUR), expiresAt: ts(Date.now() + HOUR) }));
    await assertFails(updateDoc(ref(CARA), confirm()));
    await assertSucceeds(
      updateDoc(ref(CARA), { lastSeenAt: ts(Date.now()), expiresAt: ts(created + contract.maxReportAgeDays * DAY) }),
    );
  });

  it("'Çözüldü dendi' işarette 'Hâlâ orada' yerine itiraz kullanılır", async () => {
    await seed(closingReport(BOB, "resolved", false, seenAgo(20)));
    await assertFails(updateDoc(ref(CARA), confirm()));
    await assertFails(updateDoc(ref(CARA), confirm([ALICE, CARA])));
  });
});

describe("Kaç kişi bildirdi (seenBy)", () => {
  // 20 saat önce görülmüş, "Hâlâ orada" ile yenilenmeye hazır işaret.
  const seedSeen = (seenBy: string[]) => seed(openReport({ ...seenAgo(20), seenBy }));

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
  it("İlgileniyorum, Vazgeç, Çözüldü, Artık yok ve Geri al seenBy'a dokunamaz", async () => {
    await seed(openReport());
    await assertFails(updateDoc(ref(BOB), { ...claimFields(BOB), seenBy: [ALICE, BOB] }));
    await assertSucceeds(updateDoc(ref(BOB), claimFields(BOB)));

    await seed(claimedReport(BOB));
    await assertFails(updateDoc(ref(BOB), { ...release, seenBy: [ALICE, BOB] }));
    await assertSucceeds(updateDoc(ref(BOB), release));

    await seed(claimedReport(BOB, { seenBy: [ALICE, BOB] }));
    await assertFails(updateDoc(ref(BOB), { ...closingFields(BOB), seenBy: [ALICE] }));
    await assertSucceeds(updateDoc(ref(BOB), closingFields(BOB)));

    await seed(openReport());
    await assertFails(updateDoc(ref(CARA), { goneReports: [CARA], seenBy: [ALICE, CARA] }));
    await assertSucceeds(updateDoc(ref(CARA), { goneReports: [CARA] }));

    await seed(claimedReport(BOB));
    await assertFails(updateDoc(ref(BOB), { goneReports: [BOB], ...closingFields(BOB, "gone"), seenBy: [ALICE, BOB] }));
    await assertSucceeds(updateDoc(ref(BOB), { goneReports: [BOB], ...closingFields(BOB, "gone") }));

    await seed(closingReport(BOB));
    await assertFails(updateDoc(ref(BOB), { ...undo, seenBy: [ALICE, BOB] }));
    await assertSucceeds(updateDoc(ref(BOB), undo));
  });
});

describe("Artık yok (gone)", () => {
  it("ilk oy işareti kapatmaz, sadece kaydedilir", async () => {
    await seed(openReport());
    await assertSucceeds(updateDoc(ref(CARA), { goneReports: [CARA] }));
  });

  it("tek bir yoldan geçen işareti kapatamaz ya da 'Artık yok dendi' yapamaz", async () => {
    await seed(openReport());
    await assertFails(updateDoc(ref(CARA), { goneReports: [CARA], ...closeFields("gone") }));
    await assertFails(updateDoc(ref(CARA), { goneReports: [CARA], ...closingFields(CARA, "gone") }));
  });

  it(`${contract.goneThreshold - 1} oy işareti açık bırakır`, async () => {
    await seed(openReport({ goneReports: [BOB] }));
    await assertFails(updateDoc(ref(CARA), { goneReports: [BOB, CARA], ...closingFields(CARA, "gone") }));
    await assertSucceeds(updateDoc(ref(CARA), { goneReports: [BOB, CARA] }));
    expect((await stored())!.status).toBe("open");
  });

  it(`${contract.goneThreshold}. oy yalnızca 'Artık yok dendi' yapar`, async () => {
    await seed(openReport({ goneReports: [BOB, DAVE] }));
    await assertFails(updateDoc(ref(CARA), { goneReports: [BOB, DAVE, CARA], ...closeFields("gone") }));
    await assertSucceeds(updateDoc(ref(CARA), { goneReports: [BOB, DAVE, CARA], ...closingFields(CARA, "gone") }));
  });

  it("başkasının sahipliği sürerken 3. oy yalnızca kaydedilir", async () => {
    for (const minutesAgo of [10, STALE + 15]) {
      await seed(claimedReport(BOB, { goneReports: [DAVE, "u1"] }, minutesAgo));
      await assertFails(updateDoc(ref(CARA), { goneReports: [DAVE, "u1", CARA], ...closingFields(CARA, "gone") }));
      await assertSucceeds(updateDoc(ref(CARA), { goneReports: [DAVE, "u1", CARA] }));
    }
  });

  it("ilgilenen kişinin oyu 'Artık yok dendi' yapar (hemen kapatmaz)", async () => {
    await seed(claimedReport(BOB));
    await assertFails(updateDoc(ref(BOB), { goneReports: [BOB], ...closeFields("gone") }));
    await assertSucceeds(updateDoc(ref(BOB), { goneReports: [BOB], ...closingFields(BOB, "gone") }));
  });

  it("işareti koyan tek tanıksa hemen kapatır; başkası da gördüyse 'Artık yok dendi' yapar", async () => {
    await seed(openReport());
    await assertSucceeds(updateDoc(ref(ALICE), { goneReports: [ALICE], ...closeFields("gone") }));
    await seed(openReport({ seenBy: [ALICE, CARA] }));
    await assertFails(updateDoc(ref(ALICE), { goneReports: [ALICE], ...closeFields("gone") }));
    await assertSucceeds(updateDoc(ref(ALICE), { goneReports: [ALICE], ...closingFields(ALICE, "gone") }));
  });

  it("aynı kişi iki kez bildiremez ya da başkası adına bildiremez", async () => {
    await seed(openReport({ goneReports: [CARA] }));
    await assertFails(updateDoc(ref(CARA), { goneReports: [CARA, CARA] }));
    await assertFails(updateDoc(ref(CARA), { goneReports: [CARA, BOB] }));
  });

  it("itiraz almış kişi 'Artık yok dendi' yapan oyu veremez, yalnızca oy verebilir", async () => {
    await seed(openReport({ goneReports: [BOB, DAVE], disputed: [CARA], objectors: ["u1"] }));
    await assertFails(updateDoc(ref(CARA), { goneReports: [BOB, DAVE, CARA], ...closingFields(CARA, "gone") }));
    await assertSucceeds(updateDoc(ref(CARA), { goneReports: [BOB, DAVE, CARA] }));
  });
});

describe("Hâlâ yardım gerekiyor (itiraz)", () => {
  // BOB ilgilenip kanıtlı "Çözüldü" dedi, DAVE daha önce "Artık yok" demişti; CARA hayvanı görüyor.
  const closedByBob = (overrides: Record<string, unknown> = {}) =>
    closingReport(BOB, "resolved", true, { ...seenAgo(20), ...claimOf(BOB, 30), goneReports: [DAVE], ...overrides });

  it("işareti yeniden açar; sahiplik, oylar ve öneri temizlenir, kapatan disputed'a eklenir", async () => {
    await seed(closedByBob());
    await assertSucceeds(updateDoc(ref(CARA), objection(CARA, (await stored())!)));
    const after = (await stored())!;
    expect(after.status).toBe("open");
    expect(after.disputed).toEqual([BOB]);
    expect(after.objectors).toEqual([CARA]);
    expect(after.seenBy).toEqual([ALICE, CARA]);
    expect(after.claimedBy).toBeNull();
    expect(after.goneReports).toEqual([]);
    expect(after.closingReason).toBeNull();
    expect(after.closingCredible).toBeNull();
  });

  it("kapatanı disputed'a eklemeyen itiraz reddedilir", async () => {
    await seed(closedByBob());
    const before = (await stored())!;
    await assertFails(updateDoc(ref(CARA), objection(CARA, before, { disputed: [] })));
    await assertFails(updateDoc(ref(CARA), objection(CARA, before, { disputed: [CARA] })));
    await assertFails(updateDoc(ref(CARA), objection(CARA, before, { disputed: [BOB, DAVE] })));
  });

  it("kapatan kendi önerisine itiraz edemez", async () => {
    await seed(closedByBob());
    await assertFails(updateDoc(ref(BOB), objection(BOB, (await stored())!)));
  });

  it("aynı kişi (koyan dışında) bir kez itiraz edebilir; koyan her turda edebilir", async () => {
    // 2. tur: BOB'un önerisine CARA itiraz etmişti, şimdi DAVE "Çözüldü" dedi.
    await seed(closingReport(DAVE, "resolved", false, { ...seenAgo(20), seenBy: [ALICE, CARA], disputed: [BOB], objectors: [CARA] }));
    const before = (await stored())!;
    await assertFails(updateDoc(ref(CARA), objection(CARA, before)));
    await assertFails(updateDoc(ref(CARA), objection(CARA, before, { objectors: [CARA] })));
    await assertFails(updateDoc(ref(ALICE), objection(ALICE, before, { objectors: [CARA, ALICE] })));
    await assertSucceeds(updateDoc(ref(ALICE), objection(ALICE, before)));
    expect((await stored())!.objectors).toEqual([CARA]);
  });

  it("itiraz hayvanı şimdi görmek demektir: ömür 'Hâlâ orada' kurallarıyla yenilenir", async () => {
    await seed(closedByBob());
    const before = (await stored())!;
    const now = Date.now();
    await assertFails(updateDoc(ref(CARA), objection(CARA, before, { lastSeenAt: before.lastSeenAt })));
    await assertFails(updateDoc(ref(CARA), objection(CARA, before, { expiresAt: ts(now + HOUR) })));
    await assertFails(updateDoc(ref(CARA), objection(CARA, before, { expiresAt: ts(now + 2 * LIFETIME) })));
    await assertFails(updateDoc(ref(CARA), objection(CARA, before, { seenBy: [ALICE, DAVE] })));
    // seenBy'a eklenmeden de olur (liste doluysa ya da kişi zaten oradaysa).
    await assertSucceeds(updateDoc(ref(CARA), objection(CARA, before, { seenBy: [ALICE] })));
  });

  it("öneri alanları ya da sahiplik korunarak itiraz edilemez", async () => {
    await seed(closedByBob());
    const before = (await stored())!;
    await assertFails(updateDoc(ref(CARA), objection(CARA, before, { closingCredible: true })));
    await assertFails(updateDoc(ref(CARA), objection(CARA, before, { closingReason: "resolved" })));
    await assertFails(updateDoc(ref(CARA), objection(CARA, before, claimOf(BOB, 30))));
    await assertFails(updateDoc(ref(CARA), objection(CARA, before, { goneReports: [DAVE] })));
    await assertFails(updateDoc(ref(CARA), objection(CARA, before, { status: "closing" })));
  });

  it("süresi dolmuş 'Çözüldü dendi' işarete itiraz edilemez", async () => {
    await seed(closedByBob(seenAgo(25)));
    await assertFails(updateDoc(ref(CARA), objection(CARA, (await stored())!)));
  });

  it("itiraz edilen kişi bu işarette artık ilgilenemez ve kapatma öneremez", async () => {
    await seed(closedByBob());
    await assertSucceeds(updateDoc(ref(CARA), objection(CARA, (await stored())!)));
    await assertFails(updateDoc(ref(BOB), claimFields(BOB)));
    await assertFails(updateDoc(ref(BOB), closingFields(BOB)));
    await assertSucceeds(updateDoc(ref(DAVE), claimFields(DAVE)));
  });
});

describe("Evet, çözüldü (agree)", () => {
  it("işareti koyan başkasının önerisini onaylayıp önerilen sebeple kapatır", async () => {
    await seed(closingReport(BOB, "resolved"));
    await assertSucceeds(updateDoc(ref(ALICE), closeFields("resolved")));
    await seed(closingReport(BOB, "gone"));
    await assertFails(updateDoc(ref(ALICE), closeFields("resolved")));
    await assertSucceeds(updateDoc(ref(ALICE), closeFields("gone")));
  });

  it("kapatan kendi önerisini onaylayamaz; koyan dışında kimse başkasının önerisini onaylayamaz", async () => {
    await seed(closingReport(BOB, "resolved", true, { seenBy: [ALICE, BOB, CARA] }));
    await assertFails(updateDoc(ref(BOB), closeFields("resolved")));
    await assertFails(updateDoc(ref(CARA), closeFields("resolved")));
    await assertFails(updateDoc(ref(DAVE), closeFields("resolved")));
  });

  it("koyan önerdiyse, hayvanı gören başka biri onaylar", async () => {
    await seed(closingReport(ALICE, "resolved", false, { seenBy: [ALICE, CARA] }));
    await assertFails(updateDoc(ref(ALICE), closeFields("resolved")));
    await assertFails(updateDoc(ref(BOB), closeFields("resolved")));
    await assertSucceeds(updateDoc(ref(CARA), closeFields("resolved")));
  });

  it("onay öneri alanlarını değiştiremez; öneri geçmiş olarak kalır", async () => {
    await seed(closingReport(BOB, "resolved", true));
    await assertFails(updateDoc(ref(ALICE), { ...closeFields("resolved"), closingBy: ALICE }));
    await assertFails(updateDoc(ref(ALICE), { ...closeFields("resolved"), closingCredible: false }));
    await assertFails(updateDoc(ref(ALICE), { ...closeFields("resolved"), ...clearedClosing }));
    await assertSucceeds(updateDoc(ref(ALICE), closeFields("resolved")));
    const after = (await stored())!;
    expect(after.closingBy).toBe(BOB);
    expect(after.closingCredible).toBe(true);
  });

  it("kapanış anı ve saklama süresi kurallara uyar", async () => {
    await seed(closingReport(BOB));
    const now = Date.now();
    await assertFails(updateDoc(ref(ALICE), closeFields("resolved", now - HOUR)));
    await assertFails(updateDoc(ref(ALICE), { ...closeFields("resolved", now), purgeAt: ts(now + 40 * DAY) }));
  });
});

describe("Geri al (undo)", () => {
  it(`kapatan ${UNDO} dk içinde geri alabilir; sahiplik yoksa işaret yeniden yardım bekler`, async () => {
    await seed(closingReport(BOB, "resolved", true));
    await assertFails(updateDoc(ref(BOB), { ...undoKeepingClaim, ...claimOf(BOB) }));
    await assertSucceeds(updateDoc(ref(BOB), undo));
    const after = (await stored())!;
    expect(after.status).toBe("open");
    expect(after.closingBy).toBeNull();
  });

  it("ilgilenen kendi önerisini geri alınca sahipliği aynen kalır (bırakmak da serbest)", async () => {
    const claim = claimOf(BOB, 30);
    await seed(closingReport(BOB, "resolved", true, claim));
    // Sahiplik alanları değiştirilemez (ör. yeni bir 3 saat).
    await assertFails(updateDoc(ref(BOB), { ...undoKeepingClaim, claimExpiresAt: ts(Date.now() + 3 * HOUR) }));
    await assertFails(updateDoc(ref(BOB), { ...undoKeepingClaim, claimedAt: ts(Date.now()) }));
    await assertFails(updateDoc(ref(BOB), { status: "open", ...clearedClosing }));
    await assertSucceeds(updateDoc(ref(BOB), undoKeepingClaim));
    const after = (await stored())!;
    expect(after.status).toBe("claimed");
    expect(after.claimedBy).toBe(BOB);
    expect(after.claimedAt.toMillis()).toBe(claim.claimedAt.toMillis());
    expect(after.claimExpiresAt.toMillis()).toBe(claim.claimExpiresAt.toMillis());

    await seed(closingReport(BOB, "resolved", true, claim));
    await assertSucceeds(updateDoc(ref(BOB), undo));
  });

  it("koyan, başkasının taze sahipliğini 'Çözüldü' + 'Geri al' ile düşüremez", async () => {
    // BOB 10 dk'dır ilgileniyor; ALICE (koyan) "Çözüldü" dedi ve geri alıyor.
    const claim = claimOf(BOB, 10);
    await seed(closingReport(ALICE, "resolved", false, { seenBy: [ALICE, CARA], ...claim }));
    await assertFails(updateDoc(ref(ALICE), undo));
    await assertSucceeds(updateDoc(ref(ALICE), undoKeepingClaim));
    const after = (await stored())!;
    expect(after.status).toBe("claimed");
    expect(after.claimedBy).toBe(BOB);
    expect(after.claimedAt.toMillis()).toBe(claim.claimedAt.toMillis());
    expect(after.closingReason).toBeNull();
  });

  it(`sahiplik ${STALE} dk'yı geçtiyse koyan geri alırken bırakabilir`, async () => {
    await seed(closingReport(ALICE, "resolved", false, { seenBy: [ALICE, CARA], ...claimOf(BOB, STALE + 1) }));
    await assertSucceeds(updateDoc(ref(ALICE), undo));
    expect((await stored())!.claimedBy).toBeNull();
  });

  it("sahipliğin süresi dolduysa geri alma işareti açar; süresi dolmuş sahiplik korunamaz", async () => {
    const claimedAt = Date.now() - contract.claimHours * HOUR - 10 * MINUTE;
    const expired = { claimedBy: BOB, claimedAt: ts(claimedAt), claimExpiresAt: ts(claimedAt + contract.claimHours * HOUR) };
    await seed(closingReport(ALICE, "resolved", false, { seenBy: [ALICE, CARA], ...expired }));
    await assertFails(updateDoc(ref(ALICE), undoKeepingClaim));
    await assertSucceeds(updateDoc(ref(ALICE), undo));
    const after = (await stored())!;
    expect(after.status).toBe("open");
    expect(after.claimedBy).toBeNull();
  });

  it("sahiplik yokken geri alma 'claimed' yapamaz", async () => {
    await seed(closingReport(BOB));
    await assertFails(updateDoc(ref(BOB), { ...undoKeepingClaim, ...claimFields(BOB) }));
    await assertFails(updateDoc(ref(BOB), undoKeepingClaim));
  });

  it(`${UNDO} dk sonra geri alınamaz`, async () => {
    await seed(closingReport(BOB, "resolved", false, {}, UNDO + 1));
    await assertFails(updateDoc(ref(BOB), undo));
  });

  it("başkası geri alamaz", async () => {
    await seed(closingReport(BOB));
    await assertFails(updateDoc(ref(ALICE), undo));
    await assertFails(updateDoc(ref(CARA), undo));
  });

  it("geri alma başka alanlara dokunamaz", async () => {
    await seed(closingReport(BOB, "gone", false, { goneReports: [BOB] }));
    await assertFails(updateDoc(ref(BOB), { ...undo, goneReports: [] }));
    await assertFails(updateDoc(ref(BOB), { ...undo, expiresAt: ts(Date.now() + 2 * LIFETIME) }));
    await assertSucceeds(updateDoc(ref(BOB), undo));
  });
});

describe("'Çözüldü dendi' işaret", () => {
  it("yalnızca itiraz, onay, geri alma ve süre dolumuyla değişir", async () => {
    await seed(closingReport(BOB, "resolved", false, { ...seenAgo(20), ...claimOf(BOB, 30) }));
    await assertFails(updateDoc(ref(CARA), claimFields(CARA)));
    await assertFails(updateDoc(ref(BOB), release));
    await assertFails(updateDoc(ref(CARA), confirm([ALICE, CARA])));
    await assertFails(updateDoc(ref(CARA), { goneReports: [CARA] }));
    await assertFails(updateDoc(ref(CARA), closingFields(CARA)));
    await assertFails(updateDoc(ref(BOB), closingFields(BOB, "gone")));
    await assertFails(updateDoc(ref(CARA), { closingBy: CARA, closingAt: serverTimestamp() }));
  });
});

describe("süre dolumu (expire)", () => {
  it("süresi dolmadan hiçbir durumda kapatılamaz", async () => {
    for (const report of [openReport(), claimedReport(BOB), closingReport(BOB, "gone")]) {
      await seed(report);
      await assertFails(updateDoc(ref(CARA), closeFields("expired")));
      await assertFails(updateDoc(ref(CARA), closeFields("gone")));
    }
  });

  it("süresi dolan açık ya da ilgilenilen işareti herkes closed(expired) yapar", async () => {
    for (const report of [openReport(seenAgo(25)), claimedReport(BOB, seenAgo(25))]) {
      await seed(report);
      await assertFails(updateDoc(ref(CARA), closeFields("resolved")));
      await assertFails(updateDoc(ref(CARA), closeFields("gone")));
      await assertSucceeds(updateDoc(ref(CARA), closeFields("expired")));
    }
  });

  it("süresi dolan 'Çözüldü dendi' önerilen sebeple kapanır", async () => {
    await seed(closingReport(BOB, "gone", true, seenAgo(25)));
    await assertFails(updateDoc(ref(CARA), closeFields("expired")));
    await assertFails(updateDoc(ref(CARA), closeFields("resolved")));
    await assertSucceeds(updateDoc(ref(CARA), closeFields("gone")));
    const after = (await stored())!;
    expect(after.closedReason).toBe("gone");
    expect(after.closingBy).toBe(BOB); // öneri geçmiş olarak kalır
  });

  it("süre dolumu başka alanlara dokunamaz", async () => {
    await seed(openReport(seenAgo(25)));
    await assertFails(updateDoc(ref(CARA), { ...closeFields("expired"), goneReports: [CARA] }));
    await assertFails(updateDoc(ref(CARA), { ...closeFields("expired"), expiresAt: ts(Date.now()) }));
    await assertFails(updateDoc(ref(CARA), { ...closeFields("expired", Date.now() - HOUR) }));
  });

  it("süresi dolmuş işarette başka eylem yapılamaz", async () => {
    await seed(openReport(seenAgo(25)));
    await assertFails(updateDoc(ref(BOB), claimFields(BOB)));
    await assertFails(updateDoc(ref(CARA), closingFields(CARA)));
    await assertFails(updateDoc(ref(ALICE), closeFields("resolved")));
    await assertFails(updateDoc(ref(CARA), { goneReports: [CARA] }));
    await seed(closingReport(BOB, "resolved", false, seenAgo(25)));
    await assertFails(updateDoc(ref(BOB), undo));
  });
});

describe("Geri al (silme)", () => {
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

  it("başkası da gördüyse işareti koyan silemez", async () => {
    await seed(openReport({ seenBy: [ALICE, CARA] }));
    await assertFails(deleteDoc(ref(ALICE)));
  });

  it("itiraz almış, 'Çözüldü dendi' ya da kapanmış işaret silinemez", async () => {
    await seed(openReport({ disputed: [BOB], objectors: [CARA] }));
    await assertFails(deleteDoc(ref(ALICE)));
    await seed(closingReport(ALICE));
    await assertFails(deleteDoc(ref(ALICE)));
    await seed(openReport(closeFields("resolved")));
    await assertFails(deleteDoc(ref(ALICE)));
  });
});

describe("config (uzaktan ayarlar)", () => {
  it("giriş yapmış herkes okuyabilir; kimse yazamaz ya da listeleyemez", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "config", "public"), { closingMode: "demote" });
    });
    await assertSucceeds(getDoc(doc(db(CARA), "config", "public")));
    await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), "config", "public")));
    await assertFails(setDoc(doc(db(CARA), "config", "public"), { closingMode: "label" }));
    await assertFails(updateDoc(doc(db(CARA), "config", "public"), { closingMode: "strict" }));
    await assertFails(setDoc(doc(db(CARA), "config", "other"), { closingMode: "strict" }));
    await assertFails(getDocs(collection(db(CARA), "config")));
  });
});

describe("değişmez kural: başkası da gördüyse tek kişi işareti kaldıramaz", () => {
  // ALICE koydu, CARA da gördü. BOB (hesap yaşı ve bütçesi ne olursa olsun) tek başına işareti
  // kapatamaz, ömrünü kısaltamaz, silemez ve harcamasız kanıtlı "… dendi" yapamaz.
  const bobs: Record<string, (() => Record<string, unknown>) | null> = {
    "users kaydı yok": null,
    "1 saatlik hesap": () => newUser(),
    "eski hesap, puanı bitmiş": () => agedUser({ closeUsed: contract.closeBudget.points }),
    "eski hesap, puanı var": () => agedUser(),
  };
  const base = () => ({ ...seenAgo(2), seenBy: [ALICE, CARA] });
  const starts: Record<string, () => Record<string, unknown>> = {
    açık: () => openReport(base()),
    "2 kişi artık yok dedi": () => openReport({ ...base(), goneReports: [DAVE, "u1"] }),
    "BOB 10 dk'dır ilgileniyor": () => claimedReport(BOB, base()),
    "BOB 1 saattir ilgileniyor": () => claimedReport(BOB, base(), 60),
    "DAVE 10 dk'dır ilgileniyor": () => claimedReport(DAVE, base()),
    "BOB 'Çözüldü' dedi": () => closingReport(BOB, "resolved", false, base()),
    "BOB kanıtlı 'Artık yok' dedi": () =>
      closingReport(BOB, "gone", true, { ...base(), goneReports: [DAVE, "u1", BOB] }),
    "ALICE 'Çözüldü' dedi": () => closingReport(ALICE, "resolved", false, base()),
    "DAVE 'Çözüldü' dedi": () => closingReport(DAVE, "resolved", false, base()),
  };

  function forbidden(cur: DocumentData, hasUser: boolean, spendRejected: boolean): [string, () => Promise<unknown>][] {
    const now = Date.now();
    const gone = cur.goneReports as string[];
    const votes = gone.includes(BOB) ? gone : [...gone, BOB];
    const credible = closingFields(BOB, "resolved", true);
    const writes: [string, () => Promise<unknown>][] = [
      ["closed(resolved)", () => updateDoc(ref(BOB), closeFields("resolved"))],
      ["closed(gone)", () => updateDoc(ref(BOB), closeFields("gone"))],
      ["closed(expired)", () => updateDoc(ref(BOB), closeFields("expired"))],
      ["oy + closed(gone)", () => updateDoc(ref(BOB), { goneReports: votes, ...closeFields("gone") })],
      ["ilgilen + closed", () => updateDoc(ref(BOB), { ...claimFields(BOB), ...closeFields("resolved") })],
      ["dokümanı closed olarak yeniden yaz", () => setDoc(ref(BOB), { ...cur, ...closeFields("resolved") })],
      ["ömrü kısalt", () => updateDoc(ref(BOB), { expiresAt: ts(now + HOUR) })],
      ["Hâlâ orada + kısa ömür", () => updateDoc(ref(BOB), { lastSeenAt: ts(now), expiresAt: ts(now + HOUR) })],
      ["ilgilen + kısa ömür", () => updateDoc(ref(BOB), { ...claimFields(BOB), expiresAt: ts(now + HOUR) })],
      ["itiraz + kısa ömür", () => updateDoc(ref(BOB), objection(BOB, cur, { expiresAt: ts(now + HOUR) }))],
      ["harcamasız kanıtlı Çözüldü dendi", () => updateDoc(ref(BOB), credible)],
      ["harcamasız kanıtlı Artık yok dendi", () => updateDoc(ref(BOB), { goneReports: votes, ...closingFields(BOB, "gone", true) })],
      ["sil", () => deleteDoc(ref(BOB))],
    ];
    if (hasUser) {
      writes.push(
        ["başka işaret için harcama", () => updateWithSpend(db(BOB), BOB, ID, credible, closeSpend("r2", 2))],
        ["eksik puan", () => updateWithSpend(db(BOB), BOB, ID, credible, closeSpend(ID, 1))],
      );
    }
    if (spendRejected) {
      writes.push(["tam harcama", () => updateWithSpend(db(BOB), BOB, ID, credible, closeSpend(ID, 2))]);
    }
    return writes;
  }

  for (const [bobName, bob] of Object.entries(bobs)) {
    for (const [startName, start] of Object.entries(starts)) {
      it(`${bobName} · ${startName}`, async () => {
        if (bob) await seedUser(BOB, bob());
        const initial = start();
        await seed(initial);
        const spendRejected = bob !== null && bobName !== "eski hesap, puanı var";

        const tryForbidden = async () => {
          const cur = (await stored())!;
          for (const [name, write] of forbidden(cur, bob !== null, spendRejected)) {
            try {
              await assertFails(write());
            } catch (e) {
              throw new Error(`BOB "${name}" yazabildi (${JSON.stringify({ status: cur.status })}): ${e}`);
            }
          }
        };

        await tryForbidden();
        // BOB'un tek başına yapabildiği her adımdan sonra yeniden dene.
        const steps: (() => Promise<unknown>)[] = [
          async () => {
            const cur = (await stored())!;
            return updateDoc(ref(BOB), confirm([...(cur.seenBy as string[]), BOB]));
          },
          () => updateDoc(ref(BOB), claimFields(BOB)),
          () => updateDoc(ref(BOB), closingFields(BOB)),
          async () => {
            const cur = (await stored())!;
            return updateDoc(ref(BOB), { goneReports: [...(cur.goneReports as string[]), BOB] });
          },
          async () => updateDoc(ref(BOB), objection(BOB, (await stored())!)),
        ];
        for (const step of steps) {
          const ok = await step().then(
            () => true,
            () => false,
          );
          if (ok) await tryForbidden();
        }

        const end = (await stored())!;
        expect(end.status).not.toBe("closed");
        expect(end.expiresAt.toMillis()).toBeGreaterThanOrEqual((initial.expiresAt as Timestamp).toMillis());
        if (end.closingCredible === true) {
          expect(end.closingBy).toBe(initial.closingBy);
          expect(end.closingAt.toMillis()).toBe((initial.closingAt as Timestamp).toMillis());
        }
      });
    }
  }
});

describe("emülatörde doğrulanan kural dili varsayımları", () => {
  it("bir map içindeki serverTimestamp() request.time'a eşittir", async () => {
    await seedUser(ALICE);
    await assertSucceeds(updateDoc(userRef(ALICE), createSpend("x")));
    await assertSucceeds(updateDoc(userRef(ALICE), closeSpend("x", 1)));
    const user = (await stored(`${contract.usersCollection}/${ALICE}`))!;
    expect(user.createLast.t).toBeInstanceOf(Timestamp);
    expect(user.closeLast.t).toBeInstanceOf(Timestamp);
  });

  it("getAfter aynı toplu yazımdaki users yazımını görür, yazımdan önceki hâlini değil", async () => {
    await seedUser(ALICE);
    await assertFails(setDoc(ref(ALICE), openReport()));
    await assertSucceeds(create(ALICE));
  });

  it("liste eşitliği (seenBy == [me()]) sıraya ve içeriğe bakar", async () => {
    await seed(openReport({ seenBy: [CARA, ALICE] }));
    await assertFails(updateDoc(ref(ALICE), closeFields("resolved")));
    await seed(openReport({ seenBy: [ALICE, ALICE] }));
    await assertFails(updateDoc(ref(ALICE), closeFields("resolved")));
    await seed(openReport({ seenBy: [ALICE] }));
    await assertSucceeds(updateDoc(ref(ALICE), closeFields("resolved")));
  });

  it("parametre olarak geçen metin (closesAs(before.closingReason)) karşılaştırılır", async () => {
    await seed(closingReport(BOB, "gone"));
    await assertFails(updateDoc(ref(ALICE), closeFields("resolved")));
    await assertSucceeds(updateDoc(ref(ALICE), closeFields("gone")));
  });

  it("en ağır değerlendirme ifade sınırını aşmaz", async () => {
    // Dolu listeler + kanıtlı 3. "Artık yok" oyu: en uzun kural yolu.
    const seenBy = [ALICE, ...Array.from({ length: contract.maxSeenBy - 1 }, (_, i) => `u${i}`)];
    const gone = Array.from({ length: 19 }, (_, i) => `g${i}`);
    await seedUser(CARA);
    await seed(openReport({ seenBy, goneReports: gone, disputed: [DAVE], objectors: ["u1"] }));
    await assertSucceeds(
      updateWithSpend(db(CARA), CARA, ID, { goneReports: [...gone, CARA], ...closingFields(CARA, "gone", true) }, closeSpend(ID, 2)),
    );
    // Aynı dolu işarette itiraz.
    await assertSucceeds(updateDoc(ref(ALICE), objection(ALICE, (await stored())!, { seenBy })));
  });
});

describe("yalnızca değişen alanlar yazılmalı", () => {
  // iOS, Timestamp'i Date'e çevirip geri yazdığında değer mikro saniye kayabilir. Kurallar
  // değişmemesi gereken alanları diff ile denetlediği için istemci yalnızca değişen alanları yazar
  // (FirestoreReportMapper.changes / Report.changedFields).
  it("değişmemiş zaman damgası 1 µs kaysa bile değişmiş sayılır ve reddedilir", async () => {
    const seen = Timestamp.fromMillis(Date.now() - 10 * MINUTE);
    const createdAt = new Timestamp(seen.seconds, 123_456_000);
    const initial = openReport({ createdAt, lastSeenAt: createdAt, expiresAt: ts(createdAt.toMillis() + 24 * HOUR) });
    await seed(initial);

    const drifted = new Timestamp(createdAt.seconds, createdAt.nanoseconds - 1_000);
    await assertFails(setDoc(ref(BOB), { ...initial, ...claimFields(BOB), createdAt: drifted, lastSeenAt: drifted }));
    await assertSucceeds(updateDoc(ref(BOB), claimFields(BOB)));
  });
});
