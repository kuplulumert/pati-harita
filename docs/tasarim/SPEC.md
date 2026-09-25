# Anti-abuse implementation spec (single source of truth)

This spec consolidates `kotuye-kullanim-plani.md` (plan; Tier A = §2 and §5) and `cozuldu-kalabalik.md`
(clutter refinement = budgeted "credible" closes) plus the owner's extra requirement (per-person cap on new
reports). Where the two design docs disagree, THIS file wins. Read the design docs for rationale and for the
rules sketches (§5a of the plan, §4a of the clutter doc), but implement what is written here.

Constants live in `shared/report-contract.json` (already updated — do not change values without saying so).
All user-facing text is Turkish. Code comments follow the repo style (Turkish, sparse, explain why).

## 0. Invariant

Once anyone other than the reporter has said they saw the animal, no single person can take the report off the
map before it expires. A pending close ("Çözüldü dendi") may *hide* a pin on other people's maps only when it is
**credible** (backed by the closer's daily close budget from an account ≥ 24 h old, or by the reporter), and
hiding is display-only: the document stays `closing` until a second person agrees, an objection reopens it, the
closer undoes it, or it expires.

## 1. Data model

### 1.1 `reports/{id}` — new/changed fields (all keys always present; nulls written as null)

| field | type | notes |
|---|---|---|
| `status` | `'open' \| 'claimed' \| 'closing' \| 'closed'` | new value `closing` |
| `closingReason` | `'resolved' \| 'gone' \| null` | set when entering `closing`; kept as history after `closed` |
| `closingBy` | string \| null | uid of the person who proposed the close (or who vouched — not in this release) |
| `closingAt` | timestamp \| null | **server time** (`FieldValue.serverTimestamp()`), rules require `== request.time` |
| `closingCredible` | bool \| null | true = budget-backed; null iff closingReason null |
| `objectors` | list<string> (≤ 10) | non-reporters who objected once (each at most once per report) |
| `disputed` | list<string> (≤ 10) | closers whose close was objected to; they cannot claim/propose on this report again |
| `claimedAt` | timestamp \| null | now **server time**, rules require `== request.time` on claim |

Closing quartet: either all four null, or reason ∈ {resolved, gone}, by string, at timestamp, credible bool.
`status == 'closing'` ⇒ quartet non-null. `status ∈ {open, claimed}` ⇒ quartet null. `closed` may carry the
quartet as history (when it came from `closing`) or all null (reporter-alone close, or expiry of open/claimed).

Creates write `closingReason/closingBy/closingAt/closingCredible = null`, `objectors = []`, `disputed = []`.

### 1.2 `users/{uid}` (new) — account age + budgets

| field | type | notes |
|---|---|---|
| `createdAt` | timestamp | server time on create; immutable |
| `createWindow` | timestamp | start of the current 24 h create window (server time) |
| `createUsed` | int | reports created in the window |
| `createLast` | map `{t: timestamp, id: string}` \| null | the spend that paid for report `id`; `t == request.time` |
| `closeWindow` | timestamp | start of the current 24 h close-budget window |
| `closeUsed` | int | points spent in the window (≤ 8) |
| `closeLast` | map `{t: timestamp, id: string, w: int}` \| null | spend of `w` points for report `id` |

Readable only by its owner (`get`), never listable, never deletable. `banned` etc. are Tier B (not now).

### 1.3 `config/public` (console-written)

`{ closingMode: 'demote' | 'label' | 'strict' }`. Signed-in users may `get` any `config/{doc}`; nobody writes
from clients. Missing/unknown ⇒ `label` (contract `defaultMode`). Demo mode uses `demote`.

## 2. Rules (firebase/firestore.rules) — required behaviour

Start from the plan §5a sketch, apply the clutter §4a delta (rename cred* → close* per 1.2; `closeLast` map is
`{t,id,w}`), and add the create quota. Required:

1. **Constants as functions** (exact text, contract tests check these strings):
   - `function claimStale() { return duration.value(45, 'm'); }`
   - `function undoWindow() { return duration.value(10, 'm'); }`
   - `function maxAge() { return duration.value(7, 'd'); }`
   - `function maxDisputed() { return 10; }`
   - `function newAccountAge() { return duration.value(24, 'h'); }`
   - `function budgetWindow() { return duration.value(24, 'h'); }`
   - `function maxCreates() { return 10; }`
   - `function maxCreatesFirstDay() { return 5; }`
   - `function closePoints() { return 8; }`
   - `function credibleMaxDisputed() { return 1; }`
   - `function closeCost()` returning the need→cost map in the same `'need': N` layout as `lifetimeHours()`
   - keep existing ones (`maxSeenBy`, lifetimes, `claimDuration`, `retention`, `maxBackdate`, `skew`, `rounding`)
   - `goneThreshold` stays a literal inside `isGoneReport`: `after.goneReports.size() >= 3`.
2. **validShape** per 1.1 (quartet rule, statuses, lists ≤ 10).
3. **Create**: `validCreate(d, reportId)` as today plus: quartet null, `objectors == []`, `disputed == []`, and the
   **create quota**: `getAfter(users/me)` has `createLast.t == request.time && createLast.id == reportId`.
   Compare fields individually (not whole-map equality).
4. **users/{uid}**:
   - `create`: `me() == uid`; keys exactly the 7 fields; `createdAt == request.time`, `createWindow == request.time`,
     `closeWindow == request.time`, `createUsed == 0`, `closeUsed == 0`, `createLast == null`, `closeLast == null`.
   - `update` = `isCreateSpend() || isCloseSpend()`:
     - create spend: affected keys ⊆ {createWindow, createUsed, createLast}; `createLast` keys exactly {t,id};
       `t == request.time`; `id is string`; either (same window: `createWindow` unchanged and
       `createUsed == old + 1`) or (reset: `request.time >= old.createWindow + budgetWindow()`,
       `createWindow == request.time`, `createUsed == 1`); `createUsed <= maxCreates()`; and
       `createUsed <= maxCreatesFirstDay() || old.createdAt <= request.time - newAccountAge()`.
       (Incrementing after the window ended is allowed — it is only stricter.)
     - close spend: same shape with {closeWindow, closeUsed, closeLast}; `closeLast` keys exactly {t,id,w};
       `w in [1, 2]`; same-window `closeUsed == old + w` or reset `closeUsed == w`; `closeUsed <= closePoints()`.
   - `get` own only; `list`/`delete` never.
5. **Report update gate** (split by status, `reportId` passed into functions that need it):
   - `open|claimed` and `expiresAt > request.time`: claim, release, resolve, confirm, goneReport.
   - `closing` and `expiresAt > request.time`: objection, agree, undo.
   - any non-closed with `expiresAt <= request.time`: expire.
6. **claim**: as plan §5a `isClaim` (server-time `claimedAt`, `!(me() in disputed)`, `claimExpiresAt ≤ request.time
   + claimDuration() + skew()`, `extendsTo` with the 7-day cap).
7. **release**: claimer; or reporter when the live claim is ≥ `claimStale()` old.
8. **resolve**: `reporterAlone` (reporter and `seenBy == [me()]`) → `closed(resolved)` directly (as today).
   Otherwise `mayPropose` → `closing('resolved')` with `closingBy == me()`, `closingAt == request.time`,
   `closingCredible == false` or (`== true` and `credible(resource.data, reportId)`).
   `mayPropose(r)`: `!(me() in r.disputed) && r.disputed.size() < maxDisputed() && (!hasLiveClaim(r) ||
   isClaimer(r) || isReporter(r) || request.time >= r.claimedAt + claimStale())`.
   `credible(r, reportId)`: `r.disputed.size() <= credibleMaxDisputed() && (isReporter(r) || u.createdAt <=
   request.time - newAccountAge()) && u.closeLast.t == request.time && u.closeLast.id == reportId &&
   u.closeLast.w == closeCost()[r.need]` where `u = getAfter(users/me).data`. Only evaluate getAfter when
   `closingCredible == true` (short-circuit).
9. **confirm ("Hâlâ orada")**: plan §5a `isConfirm` (may reset `goneReports` to `[]`, `extendsTo` cap).
10. **goneReport ("Artık yok")**: plan §5a/clutter §4a: plain vote; reporterAlone → `closed(gone)`;
    `closing('gone')` (credible or not, same `credible()` check) when `mayPropose` and (reporter or claimer or
    (no live claim and 3rd vote)).
11. **objection ("Hâlâ yardım gerekiyor")**: plan §5a `isObjection`, plus `closingCredible` → null in the same write.
12. **agree ("Evet, çözüldü" / "Evet, artık yok")**: plan §5a `isAgree` unchanged (reporter confirms someone
    else's close; if the reporter closed, a `seenBy` member who is not the reporter confirms). → `closed(closingReason)`.
13. **undo**: closer, `request.time < closingAt + undoWindow()` → `open`, quartet null, claim cleared.
14. **expire**: anyone, `expiresAt <= request.time` → `closed(expired)` for open/claimed, `closed(closingReason)`
    for closing.
15. **retract (delete)**: reporter, status open, `seenBy == [me()]`, `goneReports` empty, `disputed` empty.
16. `match /config/{doc} { allow get: if signedIn(); }`.
17. Reads of reports unchanged (`allow read: if signedIn()`), list limits are Tier B.

Emulator checks the design docs flagged: `serverTimestamp()` nested in a map equals `request.time`;
`getAfter` in a batch; `r.seenBy == [me()]`; passing a string parameter to `closesAs`; expression limits.

## 3. Firebase tests (firebase/tests)

- Update `helpers.ts`: contract type; `openReport` gains the new fields; `claimFields` uses `serverTimestamp()`;
  helpers to seed users docs (aged / new / with spends) and to create a report via a batch that also spends quota;
  `closingReport(by, reason, credible)` seed; `closingFields(...)`.
- Rewrite existing tests that encode the old behaviour (claimer resolve closes instantly, 2-vote gone, etc.) and
  add tests for every rule in §2, including all tests listed in the plan §2 (A1–A6) and clutter §4 "Rules tests",
  plus create-quota tests: 6th create on a new account rejected, 11th on an aged one rejected, reset after 24 h,
  one spend cannot pay for two reports in one batch, a create without a spend is rejected, `createLast.t` not
  server time rejected, users doc cannot be deleted/listed/read by others, `createdAt` immutable.
- The invariant test: for a report with `seenBy [ALICE, CARA]`, BOB (any account age, any budget) can never
  produce `closed`, a shorter `expiresAt`, a delete, or `closingCredible == true` without a matching close spend.
- `contract.test.ts`: add checks for every new constant string in §2.1, statuses, and `closeCost` values inside
  the `closeCost()` body.
- `functions/src/sweep.ts`: expire `closing` too, with `closedReason = closingReason`; update its test.
- `prototype/firebase-kurulum.html`: the `<pre id="rules">` copy must equal the new rules (HTML-escaped).
- `firestore.indexes.json`: the map query `status in [open, claimed, closing]` + geohash is covered by the
  existing (status, geohash) index; keep indexes valid.

Run: `cd firebase && npm test` (needs Java 21: prepend `C:\Users\kuplu\.jdks\jdk-21.0.12.1+1\bin` to PATH and set
JAVA_HOME; OneDrive makes the first emulator start slow — retry once on a startup timeout) and
`npm run typecheck --prefix functions`. Functions tests: check how CI runs them (`.github/workflows/ci.yml`).

## 4. AnimalKit (ios/Packages/AnimalKit) — pure Swift, no Firebase

Public API the app will use (names may be refined, but keep them if possible):

- `ReportStatus`: + `.closing`.
- `struct Closing: Hashable, Sendable { reason: ClosedReason; userID: String; at: Date; credible: Bool }` (public init).
- `Report`: + `closing: Closing?`, `objectors: [String]`, `disputed: [String]` (public internal(set)); public
  init gains `closing: Closing? = nil, objectors: [String] = [], disputed: [String] = []` **at the end** so
  existing call sites compile. `isWaiting(at:)`, `isClaimStale(at:)` helpers. `isActive(at:)` unchanged
  (closing is active).
- `ReportField`: + `closingReason, closingBy, closingAt, closingCredible, objectors, disputed`; `changedFields`
  covers them (closing quartet fields compare the corresponding `Closing` members).
- `ReportPhase`: + `.closing(reason: ClosedReason, since: Date, byMe: Bool, credible: Bool)`.
  `phase()`: closed → `.closed(closedReason ?? .resolved)`; expired → `.closed(closing?.reason ?? .expired)`;
  closing → `.closing(...)`; then claim logic as today.
- `ReportAction`: + `.dispute` ("Hâlâ yardım gerekiyor"), `.confirmClosing` ("Evet, çözüldü"; UI may say
  "Evet, artık yok" for gone), `.undoClosing` ("Geri al"), `.expire` (internal, never offered).
- `ReportError`: + `.disputed`, `.claimTooFresh`, `.alreadyObjected`, `.tooManyDisputes`, `.notExpired`,
  `.notYourClosing` (with Turkish descriptions from the design docs).
- `ReportLifecycle` constants: `goneThreshold = 3`, `claimStale = 45 min`, `undoWindow = 10 min`,
  `maxAge = 7 d`, `maxDisputed = 10` (+ existing).
- `ReportLifecycle.apply(_:to:by:at:credible: Bool = false) throws -> Report` mirroring §2 exactly, including
  lazy-expiry `.expire` (requires expiresAt ≤ now) and "actions other than expire require expiresAt > now".
  Resolve/gone by `reporterAlone` close directly; otherwise start `closing` with `credible`.
- Helpers: `reporterAlone(_:userID:)`, `mayPropose(_:by:at:)`, `wouldStartClosing(_ action:, on:, by:, at:) -> Bool`
  (tells the repository to compute credibility and spend budget), `canConfirmClosing(_:by:)`, `canDispute(_:by:)`,
  `lifeCap(_:)`, `isDue(_:at:)` (non-closed and expiresAt ≤ now).
- `availableActions(for:userID:at:)` per plan §5b (closing: closer gets `[.undoClosing]` inside the undo window
  else `[]`; others get `.confirmClosing` if allowed and `.dispute` if allowed; waiting/claimed as plan §5b with
  passerby `.resolve` when `mayPropose`; reporter gets `.release` on a stale claim; `.reportGone` if not voted and
  not closing). Order: the first action is the primary one (claim/resolve/confirmClosing).
- `Need`: `isSerious`, `closeCost` (2/1), `demoteMinutes` (120/60).
- New `UserBudget.swift`:
  - `struct UserRecord: Hashable, Sendable { createdAt, createWindow, createUsed, closeWindow, closeUsed }`
    + `static func new(at:)`.
  - `enum Budget` with constants from the contract (`window = 24 h`, `newAccountAge = 24 h`, `maxCreates = 10`,
    `maxCreatesFirstDay = 5`, `closePoints = 8`, `credibleMaxDisputed = 1`, `resetMargin = 15 min`).
  - `enum BudgetSpend: Equatable, Sendable { case sameWindow, newWindow }`.
  - `createLimit(_:at:)`, `remainingCreates(_:at:)`, `nextCreateAt(_:at:) -> Date?` (nil if a create is
    available), `spendCreate(_:at:) -> (record: UserRecord, spend: BudgetSpend)?`,
    `spendClose(_:cost:at:) -> (record: UserRecord, spend: BudgetSpend)?`.
    A window counts as ended only when `now >= window + 24 h + resetMargin` (client clock may run ahead of the
    server); otherwise same-window increments are used.
  - `enum CloseCredibility: Equatable, Sendable { case credible, noRecord, disputed, newAccount, budgetUsed }` and
    `ReportLifecycle.credibility(of:by:record:at:)` (order: noRecord, disputed (`disputed.count > 1`),
    newAccount (not reporter and account < 24 h), budgetUsed, credible).
- New `ClosingDisplay.swift`:
  - `enum ClosingMode: String, Sendable { case demote, label, strict }` (+ `static let fallback = .label`).
  - `enum ClosingLook: Equatable, Sendable { case unverified, fading(leavesAt: Date?), hidden }`.
  - `ClosingDisplay.demoteAt(closingAt:need:) -> Date`: `need.demoteMinutes` counted only during 07:00–24:00 at
    fixed UTC+3 (see clutter §4b; unit-test the table there).
  - `ClosingDisplay.look(of:mode:viewer:answered:at:) -> ClosingLook?` (nil unless `status == .closing`):
    closer (`closing.userID == viewer`) → `.hidden` (pin leaves the closer's own map at once; street-zoom dot
    still lets them undo); not credible or mode `strict` → `.unverified`; mode `label` → `.fading(leavesAt: nil)`;
    mode `demote` → `.fading(leavesAt: at)` before `at`, afterwards `.hidden` — except stakeholders (viewer is
    reporter or in `seenBy`, not the closer, and `answered == false`) who keep `.fading(leavesAt: at)`.
  - `ClosingDisplay.countsAsWaiting(_:viewer:mode:at:) -> Bool`: waiting phase, or a stale claim by someone else,
    or a closing report whose non-stakeholder look is `.unverified`.
  - `streetDotMaxRadius = 600` m.
- `Formatting`: `clock(_ date:, now:) -> String` → `"14.20"` today, `"yarın 08.00"` tomorrow (Europe/Istanbul).
- Tests: update existing tests to the new behaviour; add the tests listed in plan §2 (Swift) and clutter §4b
  (demoteAt table, credibility matrix, spend at the window boundary, look per mode, countsAsWaiting), budget
  tests, `ContractTests` for every new contract value (extend `ReportContract` in `SharedFixtures.swift`), and
  keep `testEveryActionChangesOnlyFieldsAllowedByRules` / `testEveryOfferedActionSucceeds` meaningful for all
  phases.

Swift 5 language mode, iOS 17 / macOS 14 package platforms (check Package.swift). No compiler is available on
this Windows machine: CI (macOS) is the only compiler. Be conservative with syntax and APIs.

## 5. App (ios/PatiHarita) — behaviour

Data layer:
- `ReportRepository` protocol grows: user-record observation + `ensureUserRecord`, closing-mode observation,
  quota-aware `create` (fails fast with a quota error when no allowance is left; server rejection still reported
  via `onFailure`), `perform` returns an outcome that includes the `CloseCredibility` used (for the toast),
  `fetchReports(ids:)` for the follow-up prompt.
- `FirestoreReportRepository`:
  - map query `status in [open, claimed, closing]`.
  - `create`: `WriteBatch` = report `setData` + `users/me` create spend (`createUsed` increment or reset,
    `createWindow` unchanged or `serverTimestamp()`, `createLast: {t: serverTimestamp(), id}`) — works offline.
  - `perform`: transaction reads report and `users/me`; if `ReportLifecycle.wouldStartClosing`, compute
    credibility; when credible also update `users/me` close spend (`closeLast: {t: serverTimestamp(), id, w}`)
    and write `closingCredible: true`. Retry once with the other window branch on permission-denied near a
    window boundary. `claimedAt` / `closingAt` written as `serverTimestamp()` when they change to non-nil.
  - `ensureUserRecord`: transaction; create the users doc if missing (right after anonymous sign-in).
  - listener on `users/me` and `config/public`.
  - lazy expiry: after a snapshot, for at most 3 due reports (`ReportLifecycle.isDue`) run `.expire` after a
    random 0–30 s delay; ignore failures.
- `FirestoreReportMapper`: new fields (read and write), `NSNull()` for null quartet on create, users-doc mapping.
- `DemoReportRepository`: in-memory equivalents (demo user record created 3 days ago so closes are credible; mode
  `demote`); seed one extra sample that is already `closing` (non-credible, by someone else, e.g. a dog "Mama / su"
  with "Çözüldü dendi") so the objection flow can be shown; keep the injured cat with 3 seers (UI test relies on it).
- `AppEnvironment`: App Check factory that returns `AppAttestProvider` (fallback DeviceCheck) in release; debug
  provider in DEBUG. Never add sign-out.

UI:
- Markers: "?" badge for closing looks `.unverified`/`.fading` (in the walking-badge slot); `.fading` food/other
  drawn at 60 % opacity (min with the freshness fade), serious needs keep full colour; `.hidden` → not drawn
  except as a small grey dot when the visible radius ≤ 600 m (dot: `displayPriority .defaultLow`, lowest
  zPriority; set displayPriority in `apply()`, not only `viewFor`); stale claims show a grey walking badge.
  Accessibility values: "Çözüldü dendi, doğrulanmadı" / "Çözüldü dendi, birazdan kalkacak" /
  "Çözüldü dendi, haritadan kalktı" (append to the existing seen-count value). Keep the `report-marker`
  identifier and the "Need, Species" label (UI tests rely on them); dots keep the same identifier/label.
- Top chip count uses `ClosingDisplay.countsAsWaiting`.
- Card: closing status line ("Çözüldü dendi · 20 dk önce · doğrulanmadı" / "… · Haritadan kalkış: 14.20" /
  "… · haritadan kalktı"), fact lines from the design docs, buttons per `availableActions`; `.dispute` asks for
  confirmation ("Hayvan hâlâ yardım bekliyor mu? Bunu yalnızca hayvanı şimdi gördüysen söyle." →
  [Evet, hâlâ yardım gerekiyor] [Vazgeç]); stale-claim text for others after 45 min; safety line on the card:
  "Yalnız gitme, kimseyle tartışmaya girme." (small, secondary).
- Toasts per `CloseCredibility` and mode (clutter doc §5); closer's toast offers "Geri al" and stays 10 s.
  Create-limit toast: "Son 24 saatte 10 işaret koydun. Yeni işaret hakkın saat 14.20'de açılır. Yakındaki bir
  işaret aynı hayvansa 'Ben de gördüm' diyebilirsin." (numbers/time computed; first day says 5). When ≤ 3
  creates remain, the report panel shows "Bugün 3 işaret hakkın kaldı". Offline create rejected by the quota:
  "Bu işaret günlük sınır nedeniyle kaydedilemedi."
- Follow-up prompt (plan A7): `WatchedReports` in `UserDefaults` (≤ 50 IDs created/confirmed/claimed/objected on
  this device, kept until `expiresAt + 24 h`, plus per-report "answered"); on foreground at most every 10 min
  fetch them; if one is `closing` by someone else and this user can act, show a sheet (texts in plan A7 / clutter
  §5; default button "Bilmiyorum", which marks answered). The 40 m "Ben de gördüm" suggestion also matches
  closing reports and offers the objection.
- Legend: new rows for "?" badge, faded pin, grey dot, night rule, stale claim; "Nasıl çalışır?" step 3 text.
- UI test (`ReportFlowUITests`): keep steps 01–09 green; add: passerby "Çözüldü" on a seeded report shows the
  "Yardımın kaydedildi" toast (time-agnostic assertion) → screenshot `10-cozuldu-dendi`; open the seeded closing
  report, card shows "Çözüldü dendi" → screenshot `11-cozuldu-dendi-karti`; tap "Hâlâ yardım gerekiyor", confirm →
  toast "yeniden yardım bekliyor" → screenshot `12-itiraz`. Make assertions robust (identifiers for new buttons).

## 6. Out of scope now

Tier B (App Check enforcement, list limits, bans, young-account half budget), Tier C (push, reputation), vouch
("Doğru, çözülmüş"), coarse location for babies, web prototype `prototype/index.html` behaviour.
