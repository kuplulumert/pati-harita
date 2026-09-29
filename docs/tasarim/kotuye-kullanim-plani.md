# Pati Harita: one anti-abuse plan (synthesis of the 3 designs and their red-team reviews)

## 0. What I checked in the repo, and the rule the plan is built on

I read `firebase/firestore.rules`, `ReportLifecycle.swift`, `Report.swift`, `report-contract.json`, `sweep.ts`, the tests, `FirestoreReportRepository.swift`, `FirestoreReportMapper.swift`, `MapViewModel.swift` and the project memory. These facts shape the plan:

- **Closed reports can never change.** Every update requires `isActive(resource.data)`, which means `status in ['open','claimed']`.
- **Security hole: a reporter can delete a report other people confirmed.** `canRetract` checks only reporter, `open` and `goneReports.size()==0`. It never looks at `seenBy`, so this is a one-person, instant removal path.
- **Expired reports come back to life and never leave the map query.** `isConfirm` accepts writes on docs whose `expiresAt` has passed. `sweepStaleReports` is not deployed (Spark), so expired docs keep `status: open` forever and every map listener keeps reading them.
- **"Kept 30 days, then deleted" is not true today.** The TTL policy failed with "billing disabled". `allow read: if signedIn()` covers list queries too, so anyone can dump the whole history: exact coordinates plus uid trails.
- **Actions are online, creates are offline.**
  - Every action runs in `db.runTransaction`, so it is online-only. That means `FieldValue.serverTimestamp()` can be used for any action timestamp and checked with `== request.time`.
  - Creates are an unawaited `setData` that can sit offline. Any per-user limit on creates therefore has to wait for Tier B's batched writes.
- **Squatting also hides reports from the headline count.** `waitingCount` counts only `.waiting`, so claimed reports already drop out of "N hayvan yardım bekliyor".
- **Contract tests constrain the rules text.**
  - They look for the literal `after.goneReports.size() >= N`, for `duration.value(...)` strings, and for `function maxSeenBy() { return 100; }`.
  - `prototype/firebase-kurulum.html` must hold an identical copy of the rules.
- **No data migration is needed.** Production Firestore has no real reports (TestFlight builds run in demo mode), so the schema change costs nothing if the rules and the app ship together.

**The rule Tier A enforces:** once anyone other than the reporter has said they saw the animal, no single person can take the report off the map before it expires.
- Only the reporter can remove a report instantly, and only while `seenBy == [reporter]` (nobody else has confirmed it).
- Anyone else's "Çözüldü" or "Artık yok" only adds a public "… dendi" label. The label never shortens `expiresAt`, and one tap from anyone who sees the animal undoes it.
- A labelled report leaves the map only when a second person agrees or when its normal lifetime ends.

Tier A adds **zero `get()`/`exists()` calls**, so there is no extra billed read.

---

## 1. Threats, ranked

1. **Silent removal by one person (critical, real today).** Two taps remove any report instantly and for good: claim + Çözüldü, or claim + Artık yok. The reporter can also delete a report others confirmed, through `canRetract`. Closed reports cannot be reopened.
2. **Scripted abuse over REST (critical before public launch).** App Check is not enforced, so a script can create unlimited uids, run mass closes and spam, dump the whole collection, and use up the Spark quota. On Spark, running out of quota means the app stops working for everyone until the daily reset.
3. **Exposed locations of vulnerable animals (high, separate issue).** Exact lat/lng and a 10-character geohash for injured animals and puppies are visible to anyone. The data also contains uid trails (who reports, claims and closes where). Everything is listable and, with TTL blocked, kept forever.
4. **A small group with 2–5 phones (high).** Two "Artık yok" votes from anyone close a report instantly today. A group can also label reports in bulk.
5. **Claim squatting (medium).** "Biri ilgileniyor" puts volunteers off and removes the report from the headline count. Only the claimer can resolve for 3 h, and the same person can claim again when it lapses.
6. **Fake reports: spam, lures and never-ending reports (medium to low).** "Hâlâ orada" can extend a report forever. There is no limit per user.

---

## 2. Tier A: do now (Spark, rules + client, one release)

Tier A achieves the following:
- **One hostile phone**, even with a reinstall that yields a new uid, cannot remove any report that someone else created or confirmed. It can only add labels that one tap undoes, and after an objection it cannot label that report again.
- **Two or more non-reporter phones** can only add labels.
- **A claim squatter** blocks nothing except, for 45 minutes, other people's "Çözüldü". A squatted report stays attractive to volunteers and keeps being counted.

### A1. Soft close: "Çözüldü dendi" (new status `closing`), second-person confirmation, undo
- **What:** Every "Çözüldü" or "Artık yok" that does not come from a reporter alone becomes `closing`.
  - The report stays on the map. `expiresAt` does not change, so the report never ends sooner than it would have.
  - `closing` ends in one of four ways:
    - **Confirmation by a second person ("Evet, çözüldü"):** the reporter confirms someone else's close, or, if the reporter made the close, a `seenBy` member does.
    - **Natural expiry:** handled by A5.
    - **Objection:** handled by A2.
    - **Undo:** the person who closed it taps "Geri al" within 10 min.
- **Why:** This removes the 2-tap instant removal. It replaces the "2 h window, then gone" idea because the red team broke that window: closes made at night, with the attacker finalizing the report himself.
- **How it works:**
  - New fields `closingReason` ('resolved' | 'gone'), `closingBy` and `closingAt`.
  - `closingAt` is written as `serverTimestamp()` and the rules require `== request.time`. The ±15 min tolerance of `isNow` could otherwise be used to fake the timeline.
  - The closing fields are kept after `closed` as history, so the owner can filter by `closingBy`.
  - The update gate is split by status. Actions for open or claimed reports can only run on `open|claimed`, and the closing actions only on `closing`. This fixes the latent bug where `hasLiveClaim()` is false on `closing` docs.
  - Claim fields stay on the doc during `closing` so the card can show the timeline.
- **Who can do what:**
  - **Reporter alone** (`seenBy == [reporter]`): instant `closed`, as today.
  - **Reporter after someone else confirmed:** `closing`. A `seenBy` member can confirm it.
  - **Anyone else:** `closing`. See A4 for who may propose.
- **Client:**
  - Add `ReportStatus.closing` and `ReportPhase.closing(reason:since:byMe:)`. The map query becomes `status in [open, claimed, closing]`; the existing `status+geohash` index covers it.
  - For the person who closed the report: a haptic and a check animation, and the pin disappears from their own map right away.
  - For everyone else, the look depends on who closed it and is computed on the client, which shows facts rather than verdicts:
    - Reporter said it: grey.
    - Someone who had claimed the report said it: normal colour at about 70% opacity.
    - A passerby, or a claim followed by a close within 5 min: full colour with a "?" badge.
  - `emergency`, `injured` and `babies` always keep full colour.
  - Closing reports are left out of "N hayvan yardım bekliyor".
- **UX (Turkish):**
  - Status line: "Çözüldü dendi · 20 dk önce · doğrulanmadı" / "Artık yok dendi · …"
  - Fact lines: "İşareti koyan çözüldü dedi." · "İlgilenen kişi 40 dk sonra çözüldü dedi." · "İlgilenmeden çözüldü dendi." · "3 kişi artık yok dedi."
  - Hint: "Hayvanı görürsen ve hâlâ yardıma ihtiyacı varsa bildir."
  - Toast for the person who closed: "Teşekkürler! Yardımın kaydedildi. İşareti koyan onaylayınca haritadan kalkacak." Their button: "Geri al" (10 dk).
  - For the reporter: "Evet, çözüldü" and "Hayır, hâlâ yardım gerekiyor".
- **Files:**
  - Rules and the copy in `prototype/firebase-kurulum.html`.
  - `shared/report-contract.json`.
  - AnimalKit: `Report.swift`, `ReportLifecycle.swift`.
  - App: `FirestoreReportMapper.swift` (new fields; `claimedAt` and `closingAt` written as `FieldValue.serverTimestamp()`), `FirestoreReportRepository.swift` (query), `DemoReportRepository.swift`, `ReportCard.swift`, `NeedStyle.swift`, `MarkerPin.swift`/`MarkerIconRenderer.swift`, `LegendSheet.swift`, `MapViewModel.swift`.
  - Docs: `README.md`, `docs/architecture.md`.
- **Tests (rules):**
  - The claimer's "Çözüldü" is accepted only as `closing`; writing `closed` is rejected.
  - A `closingAt` that is not the server time (for example `ts(now-10min)`) is rejected.
  - A close that changes `expiresAt` is rejected.
  - Reporter with `seenBy [ALICE]`: `closed` accepted. Reporter with `[ALICE, CARA]`: `closed` rejected, `closing` accepted.
  - Confirmation: the reporter can confirm someone else's closing. The closer cannot confirm their own. A stranger cannot confirm. If the reporter closed, a `seenBy` member can confirm and a non-member cannot.
  - Undo works within 10 min and is rejected after 10 min and for anyone else.
  - Invariant test: for a report with `seenBy [ALICE, CARA]`, loop BOB through every shape of claim-then-write that yields `closed`, a shorter `expiresAt`, or a delete. All must fail.
- **Tests (Swift):**
  - Update `testEveryActionChangesOnlyFieldsAllowedByRules` with the new field sets.
  - Add `testClaimerResolveOnlyProposes`, `testReporterAloneClosesInstantly`, `testAgreeNeedsSecondPerson`, `testUndoWindow`.
  - Extend `testEveryOfferedActionSucceeds` to the closing phase.

### A2. Objection "Hâlâ yardım gerekiyor", with `disputed` and `objectors`
- **What:** On a `closing` report, anyone except the person who closed it can object. The report goes back to `open`, the claim is cleared, the "Artık yok" votes are cleared, the objector's sighting refreshes the lifetime and adds them to `seenBy`, and the closer's uid is added to `disputed`.
  - People in `disputed` cannot claim or propose a close on this report again.
  - Non-reporters can object once per report (`objectors`). The reporter can object any number of times.
  - With 10 entries in `disputed`, nobody can propose a close any more; only expiry ends the report.
- **Why:** This replaces the reversible design's "protection ladder", which the red team broke: the count never went down, it could lock out real rescuers, and a hostile reporter could protect their own fake report. It also replaces the `reopenCount` cap, which one phone could use to lock a report.
  - Adding the closer to `disputed` is mandatory, not optional.
  - Since every objection adds exactly one closer, `objectors` can never exceed `disputed`. The list cannot fill up and block objections.
- **UX (Turkish):**
  - Confirmation dialog: "Hayvan hâlâ yardım bekliyor mu? Bunu yalnızca hayvanı şimdi gördüysen söyle." with [Evet, hâlâ yardım gerekiyor] [Vazgeç]. The dialog reduces mistaken objections from people who remember seeing the animal that morning.
  - Toast: "Teşekkürler, işaret yeniden yardım bekliyor."
  - Errors: "Bu işarette kapatma önerine itiraz edildi; tekrar kapatamazsın." · "Buna zaten itiraz ettin." · "Bu işaret çok itiraz aldı; süresi dolunca kendiliğinden kalkar."
- **Files:** Same as A1.
- **Tests:**
  - Objection returns the report to `open` and clears the claim and `goneReports`.
  - An objection that does not add `closingBy` to `disputed` is rejected.
  - The closer cannot object.
  - The same non-reporter cannot object twice; the reporter can object in round 2.
  - A `disputed` uid cannot claim, cannot propose "Çözüldü", and cannot cast the vote that starts closing.
  - With `disputed.size()==10`, proposals are rejected.
  - The objector's `seenBy` addition and lifetime refresh follow the `isConfirm` rules.

### A3. "Artık yok" hardening
- **What:**
  - The reporter alone closes instantly, as today.
  - The reporter (after others confirmed) or the claimer starts `closing('gone')`. This fixes the red-team harm where volunteers who found the animal gone would otherwise have to mislabel it "resolved".
  - Anyone else casts a vote. The **3rd** vote starts `closing('gone')` (`goneThreshold` goes from 2 to 3), and only if nobody else holds a live claim. Votes can never start closing over a volunteer's live claim.
  - "Hâlâ orada" and objections reset `goneReports` to `[]`, so votes from days apart do not add up.
- **Why:** Two throwaway votes should not close a report, and the claimer shortcut is closed.
- **UX (Turkish):**
  - After a vote: "Teşekkürler. 3 kişi 'Artık yok' derse işaret 'Artık yok dendi' olarak işaretlenir."
  - Card line: "2 kişi artık yok dedi".
- **Tests:**
  - 2 votes leave the report open.
  - The 3rd vote gives `closing` only; `closed` is rejected.
  - The claimer's vote gives `closing('gone')`.
  - The 3rd vote while BOB's claim is live can only be recorded.
  - "Hâlâ orada" may reset `goneReports` to `[]` but may not change it any other way.
  - Rename the existing test "işareti koyan ya da ilgilenen kişi tek başına kapatabilir".
  - Keep the literal `after.goneReports.size() >= 3` for the contract test.

### A4. Claims become advisory (fixes squatting)
- **What:**
  - Proposing a close no longer requires holding the claim. Anyone can propose "Çözüldü" when:
    - there is no live claim, or
    - they are the claimer or the reporter, or
    - someone else's claim is at least 45 min old (`claimStaleMinutes`).
  - The reporter can release a claim that is at least 45 min old ("İlgilenen gelmedi").
  - `claimedAt` is written as `serverTimestamp()` and required to be `== request.time`, so the 45-minute clock cannot be faked. `claimExpiresAt` is bounded by `request.time + 3h + skew`.
  - The claim stays 3 h, so long vet trips still work.
- **Why:**
  - Claims are free, so tying the right to close to the claim added nothing against attackers. It let squatters block the real rescuer.
  - The red-team fixes that relied on claim takeover or a minimum hold time either stole real volunteers' claims or forced a rescuer to wait after grabbing the animal.
- **Client:**
  - After 45 min, a claim by someone else counts as waiting in `waitingCount` and its walking badge turns grey.
  - Passersby see "Çözüldü" as a secondary button.
  - "Hâlâ orada", "Artık yok" and "Yol tarifi" stay available on claimed reports.
- **UX (Turkish):**
  - From 0 to 45 min: "Biri ilgileniyor · 12 dk önce".
  - After 45 min: "Biri 1 sa önce ilgilenmeye başladı, o zamandan beri haber yok. Sen de gidebilirsin."
  - Reporter button: "İlgilenen gelmedi".
  - Error: "Biri az önce ilgilenmeye başladı. 45 dk içinde haber gelmezse sen de 'Çözüldü' diyebilirsin."
- **Tests:**
  - A claim whose `claimedAt` is not the server time is rejected.
  - A passerby's "Çözüldü" is rejected while the claim is under 45 min old and accepted at 46 min or more (seed `claimedAt` in the past).
  - A passerby's "Çözüldü" on an open report is accepted.
  - The reporter's release is rejected at 10 min and accepted at 46 min; the claimer can always release.
  - Update the test "sahiplik süresi sözleşmedekinden uzun olamaz": it now uses 3 h + 16 min, because of the skew tolerance.

### A5. Lazy expiry (stands in for the sweep on Spark), absolute age cap, no resurrection
- **What:**
  - Any signed-in user can move `open|claimed|closing` to `closed`, but only once `expiresAt <= request.time`. The reason is `expired`, or the `closingReason` for a closing report.
  - Every other action requires `expiresAt > request.time`, so expired docs cannot be brought back.
  - Every write that extends `expiresAt` caps it at `createdAt + 7 d` (`maxReportAgeDays`). `createdAt` never changes, and backdating it only lowers the cap.
- **Why:**
  - Without this, `closing` docs and expired docs stay in the map queries forever and keep costing reads.
  - The red team found that fake or "lure" reports can be kept alive forever; the cap stops that.
- **Client:** After each snapshot, close at most 3 due docs with a random 0–30 s delay, and ignore permission-denied errors from races. `sweep.ts` must also include `closing` and set `closedReason = closingReason`, so it matches once Blaze arrives.
- **UX (Turkish):** "Bu işaret 7 gündür haritada; hâlâ yardım gerekiyorsa yeniden işaretle."
- **Files:** Add `sweep.ts` and its test to the A1 list.
- **Tests:**
  - Expiring before `expiresAt` is rejected for every status.
  - After `expiresAt`, open/claimed become `closed(expired)` and closing becomes `closed(closingReason)`; a wrong reason is rejected.
  - "Hâlâ orada" on an expired doc is rejected.
  - "Hâlâ orada" or a claim that extends past `createdAt + 7d` is rejected.

### A6. Close the retract hole
- **Rule:** `canRetract` also requires `seenBy == [me()]` and an empty `disputed` list.
- **Test:** After CARA confirms, ALICE's delete is rejected.

### A7. Follow-up prompt for the reporter and people who saw the animal (client only)
- **What:**
  - The app stores in `UserDefaults` the IDs of reports this device created, confirmed or objected to (at most 50), each kept until `expiresAt + 24 h`.
  - On foreground, at most every 10 min, it fetches them with `getDocument` (N cheap reads, no index needed).
  - If a report is `closing`, was closed by someone else, and this user can act on it, a sheet appears.
  - The "Ben de gördüm" suggestion within 40 m also matches `closing` reports.
- **UX (Turkish):**
  - For the reporter: "Koyduğun Yaralı kedi işareti için 20 dk önce 'Çözüldü' dendi. Doğru mu?" with [Evet, çözüldü] [Hayır, hâlâ yardım gerekiyor] [Bilmiyorum]. "Bilmiyorum" is the default and the timeline is shown, against the red team's social-engineering "Evet".
  - For people who saw the animal: "Gördüğün Yaralı kedi için 'Çözüldü' dendi. Hâlâ yardım gerekiyor mu?"
  - On the "Ben de gördüm" suggestion: "Yakında bu hayvan için 'Çözüldü' dendi. Hâlâ burada mı?"
- **Files:** `MapViewModel.swift`, a new `WatchedReports.swift`, `ReportPanel.swift`.
- **Tests:** A UI test in the demo repository.

### A8. Prepare for App Check enforcement in this same build, and keep one uid per device
- **What:**
  - In `AppEnvironment.bootstrap`, replace `DeviceCheckProviderFactory` with a factory that returns `AppAttestProvider`, falling back to DeviceCheck, and keep the debug provider in DEBUG. Any build without the provider stops working the moment enforcement is switched on.
  - Never add sign-out. Keep anonymous auto clean-up OFF.
  - Add a hidden uid prefix line in `LegendSheet` so a TestFlight reinstall can be checked.
- **Test:** Manual on TestFlight: delete the app, reinstall, compare the uid prefix.

---

## 3. Tier B: before public launch

- **B1. App Check enforcement and the auth surface (console):**
  - Register App Attest (team T5MF2GW4JQ) and set the token TTL to 30–60 min.
  - Enforce App Check for **Cloud Firestore** once metrics show about 100% verified requests from a build connected to Firebase.
  - Enforce it for **Authentication** too, if the project offers it. It may need Identity Platform.
  - Lower Auth → Settings → sign-up quota to about 20 per IP per hour. Going lower hurts Turkish mobile CGNAT, where many users share one IP.
  - In the GCP console, restrict the iOS API key to bundle `app.patiharita.ios` and to the needed APIs (Identity Toolkit, Secure Token, Firestore, App Check, Installations). This is weak but free.
  - Honest limit: rules cannot see App Check, tokens are bearer tokens, and Firestore has no replay protection.
- **B2. Limit reads:**
  - `allow get: if signedIn();`
  - `allow list: if signedIn() && resource.data.status in ['open','claimed','closing'] && request.query.limit <= 200;`
  - The client adds `.limit(to: 200)` to each geohash range. Check in the emulator that an `in` query is accepted.
  - This stops the full-collection dump and the listing of closed history. A7's `get` by ID keeps working.
- **B3. `users/{uid}`: account age, budgets, ban flag:**
  - `createdAt == request.time` (serverTimestamp), no delete, and `banned` can only be set from the console.
  - Daily counters, each **bound to one report**: `last == {t, id}` is checked through `getAfter()` from the report rule. This fixes the red-team finding that one increment in a batch could pay for many writes.
  - Budgets for new accounts (under 72 h) / aged accounts:
    - creates 10/30
    - close proposals 3/8
    - objections 5/15
  - Banned uids cannot create, claim, propose or object.
  - New accounts cannot cast the 3rd "Artık yok" vote. Their proposals get a rules-checked `closingByNew: true` so the card can say "yeni bir kullanıcı çözüldü dedi".
  - Creates become a WriteBatch using `FieldValue.increment`. Reset the 24 h window only through an online write. Show rejected offline reports using the existing `onFailure`.
  - Plan for about 3 reads and 2 writes per gated action.
  - Optional: one live claim per uid. If you add it, check the old slot with `get()`, not `getAfter()`, which the red team caught.
- **B4. Moderation playbook (console):**
  - Filter by `closingBy == X`, `disputed array-contains X` and `objectors array-contains X`, and review reports with non-empty `disputed` weekly.
  - Before B3 exists, a `banned/{uid}` collection with `!exists(...)` on create, propose and object costs 1 read per gated write and still works.
- **B5.** Carry out the owner's location decision (§7, decision 2).
- **B6. Fix the docs:** the README and architecture claims about the 10-minute sweep and 30-day TTL are false on Spark. Add the privacy-policy wording.

## 4. Tier C: later, with Blaze and Cloud Functions

- **C1. Push notifications.** A Functions trigger sends FCM to the reporter and `seenBy` when a report enters `closing`. This is the most valuable Tier C item, because it closes the "nobody noticed" gap.
  - Once push exists, add a 24 h reopen by the reporter or `seenBy` members, at most once per uid.
- **C2. Sweep and deletion.** Deploy the sweep including `closing`, enable TTL on `purgeAt`, and shorten how long closed reports are kept (for example 7 days) for privacy.
- **C3. Identity creation through a callable Function.** It uses a limited-use App Check token (`consumeAppCheckToken`) and, optionally, DeviceCheck's 2 bits per device to cap new identities per device and ban devices. The rules then accept only `verified` users docs.
- **C4. Server-side reputation.**
  - Count closings that were later overturned, and throttle those uids automatically.
  - Give strikes only when several independent people dispute. Reporter-only strikes can be used against volunteers, so they are dropped.
  - Send the owner a digest.
  - Anomaly detection: the same uids closing many reports, and bursts in one area.
  - If a uid is banned later, reopen the closes it made.
- **C5. Location privacy on the server.** Store the exact point server-side. Replace raw uids in public fields with per-report pseudonymous IDs. Fix geohash/lat-lng consistency.

---

## 5. Tier A in detail: rules, Swift and contract

### 5a. `firebase/firestore.rules` (full replacement; unchanged parts marked)

```
rules_version = '2';

// Pati Harita — Firestore güvenlik kuralları.
//
//   open ──İlgileniyorum──▶ claimed ──(Vazgeç / 3 sa)──▶ open
//   open|claimed ──Çözüldü / Artık yok──▶ closing ("… dendi"; haritada kalır, ömrü kısalmaz)
//   closing ──Hâlâ yardım gerekiyor (kapatan dışında herkes)──▶ open
//   closing ──Evet, çözüldü (ikinci kişi)──▶ closed      closing ──Geri al (kapatan, 10 dk)──▶ open
//   open|claimed ──Çözüldü / Artık yok (koyan; başka gören yoksa)──▶ closed
//   open|claimed|closing ──expiresAt geçti (herkes, sunucu saatiyle)──▶ closed
//
// Değişmez kural: başkasının da gördüğü bir işareti tek bir kişi süresinden önce kaldıramaz.

service cloud.firestore {
  match /databases/{database}/documents {

    function signedIn() { return request.auth != null; }
    function me() { return request.auth.uid; }

    function lifetimeHours() {
      return {
        'emergency': 12,
        'injured': 24,
        'babies': 72,
        'vet': 48,
        'food': 12,
        'shelter': 72,
        'other': 24
      };
    }
    function lifetime(need) { return duration.value(lifetimeHours()[need], 'h'); }
    function claimDuration() { return duration.value(3, 'h'); }
    function retention() { return duration.value(30, 'd'); }
    function maxBackdate() { return duration.value(24, 'h'); }
    function skew() { return duration.value(15, 'm'); }
    function rounding() { return duration.value(1, 'm'); }
    function maxSeenBy() { return 100; }
    // Başkası bu kadar süredir ilgileniyorsa herkes "Çözüldü" diyebilir.
    function claimStale() { return duration.value(45, 'm'); }
    // Kapatma önerisini yapanın "Geri al" süresi.
    function undoWindow() { return duration.value(10, 'm'); }
    // Hiçbir işaret oluşturulmasından bu kadar sonra haritada kalamaz.
    function maxAge() { return duration.value(7, 'd'); }
    // İtiraz alan en fazla kapatma önerisi; dolunca yalnızca süre kapatır.
    function maxDisputed() { return 10; }

    function isNow(t) {
      return t is timestamp && t > request.time - skew() && t < request.time + skew();
    }

    // ---- Doküman şekli ----

    function reportKeys() {
      return ['species', 'need', 'lat', 'lng', 'geohash', 'status', 'closedReason',
              'reporterId', 'createdAt', 'lastSeenAt', 'expiresAt', 'claimedBy',
              'claimedAt', 'claimExpiresAt', 'goneReports', 'seenBy', 'closedAt', 'purgeAt',
              'closingReason', 'closingBy', 'closingAt', 'objectors', 'disputed'];
    }

    function validShape(d) {
      return d.keys().hasAll(reportKeys()) && d.keys().hasOnly(reportKeys())
        && d.species in ['cat', 'dog', 'bird', 'other']
        && d.need in lifetimeHours()
        && d.lat is number && d.lat >= -90 && d.lat <= 90
        && d.lng is number && d.lng >= -180 && d.lng <= 180
        && d.geohash is string && d.geohash.matches('^[0-9b-hjkmnp-z]{10}$')
        && d.status in ['open', 'claimed', 'closing', 'closed']
        && d.reporterId is string
        && d.createdAt is timestamp
        && d.lastSeenAt is timestamp
        && d.expiresAt is timestamp
        && d.goneReports is list && d.goneReports.size() <= 20
        && d.seenBy is list && d.seenBy.size() >= 1 && d.seenBy.size() <= maxSeenBy()
        && d.objectors is list && d.objectors.size() <= maxDisputed()
        && d.disputed is list && d.disputed.size() <= maxDisputed()
        && ((d.claimedBy == null && d.claimedAt == null && d.claimExpiresAt == null)
            || (d.claimedBy is string && d.claimedAt is timestamp && d.claimExpiresAt is timestamp))
        && (d.status != 'claimed' || d.claimedBy != null)
        // Kapatma önerisi: üçü birlikte dolu ya da boş; closed'da geçmiş olarak kalır.
        && ((d.closingReason == null && d.closingBy == null && d.closingAt == null)
            || (d.closingReason in ['resolved', 'gone'] && d.closingBy is string && d.closingAt is timestamp))
        && (d.status != 'closing' || d.closingReason != null)
        && (d.status in ['closing', 'closed'] || d.closingReason == null)
        && ((d.status == 'closed'
              && d.closedReason in ['resolved', 'gone', 'expired']
              && d.closedAt is timestamp
              && d.purgeAt is timestamp)
            || (d.status != 'closed'
              && d.closedReason == null
              && d.closedAt == null
              && d.purgeAt == null));
    }

    // ---- Durum yardımcıları ----

    function isWaiting(r) { return r.status in ['open', 'claimed']; }
    function isLive(r) { return r.expiresAt > request.time; }
    function hasLiveClaim(r) { return r.status == 'claimed' && r.claimExpiresAt > request.time; }
    function isClaimer(r) { return hasLiveClaim(r) && r.claimedBy == me(); }
    function isReporter(r) { return r.reporterId == me(); }
    // Hayvanı koyandan başka gören yok.
    function reporterAlone(r) { return isReporter(r) && r.seenBy == [me()]; }

    function changedKeys() { return request.resource.data.diff(resource.data).affectedKeys(); }

    function identityUnchanged() {
      return !changedKeys().hasAny(['species', 'need', 'lat', 'lng', 'geohash',
                                    'reporterId', 'createdAt']);
    }

    function closesAs(reason) {                       // unchanged
      let after = request.resource.data;
      return after.status == 'closed'
        && after.closedReason == reason
        && isNow(after.closedAt)
        && after.purgeAt > after.closedAt
        && after.purgeAt <= after.closedAt + retention() + rounding();
    }

    // expiresAt aynı kalır ya da `limit`e kadar uzar; oluşturmadan itibaren maxAge'i aşmaz.
    function extendsTo(before, after, limit) {
      return after.expiresAt == before.expiresAt
        || (after.expiresAt > before.expiresAt
            && after.expiresAt <= limit
            && after.expiresAt <= before.createdAt + maxAge());
    }

    // "Hayvanı şimdi gördüm": lastSeenAt yenilenir, ömür uzar, kişi seenBy'a bir kez eklenir.
    function refreshes(before, after) {
      return isNow(after.lastSeenAt)
        && after.lastSeenAt > before.lastSeenAt
        && extendsTo(before, after, after.lastSeenAt + lifetime(before.need) + rounding())
        && (after.seenBy == before.seenBy
            || (!(me() in before.seenBy)
                && before.seenBy.size() < maxSeenBy()
                && after.seenBy == before.seenBy.concat([me()])));
    }

    // Bu kişi işareti "closing"e alabilir mi? Taze (45 dk'dan genç) başkasının sahipliğine saygı.
    function mayPropose(r) {
      return !(me() in r.disputed)
        && r.disputed.size() < maxDisputed()
        && (!hasLiveClaim(r) || isClaimer(r) || isReporter(r)
            || request.time >= r.claimedAt + claimStale());
    }

    function startsClosing(reason) {
      let after = request.resource.data;
      return after.status == 'closing'
        && after.closingReason == reason
        && after.closingBy == me()
        && after.closingAt == request.time;          // FieldValue.serverTimestamp()
    }

    // ---- Oluşturma ----

    function validCreate(d) {
      return validShape(d)
        && d.reporterId == me()
        && d.status == 'open'
        && d.claimedBy == null
        && d.closingReason == null
        && d.goneReports.size() == 0
        && d.objectors.size() == 0
        && d.disputed.size() == 0
        && d.seenBy == [me()]
        && d.createdAt < request.time + skew()
        && d.createdAt > request.time - maxBackdate()
        && d.lastSeenAt == d.createdAt
        && d.expiresAt > d.createdAt
        && d.expiresAt <= d.createdAt + lifetime(d.need) + rounding();
    }

    // ---- open|claimed üzerindeki eylemler ----

    function isClaim() {
      let before = resource.data;
      let after = request.resource.data;
      return changedKeys().hasOnly(['status', 'claimedBy', 'claimedAt', 'claimExpiresAt', 'expiresAt'])
        && !hasLiveClaim(before)
        && !(me() in before.disputed)
        && after.status == 'claimed'
        && after.claimedBy == me()
        && after.claimedAt == request.time            // serverTimestamp()
        && after.claimExpiresAt > request.time
        && after.claimExpiresAt <= request.time + claimDuration() + skew()
        && extendsTo(before, after, after.claimExpiresAt);
    }

    // Vazgeç: ilgilenen; ya da 45 dk'dır haber vermeyen sahipliği işareti koyan kaldırır.
    function isRelease() {
      let before = resource.data;
      let after = request.resource.data;
      return changedKeys().hasOnly(['status', 'claimedBy', 'claimedAt', 'claimExpiresAt'])
        && (isClaimer(before)
            || (isReporter(before) && hasLiveClaim(before)
                && request.time >= before.claimedAt + claimStale()))
        && after.status == 'open'
        && after.claimedBy == null;
    }

    // Çözüldü: koyan tek tanıksa hemen kapanır; diğer her durumda "Çözüldü dendi".
    function isResolve() {
      return (reporterAlone(resource.data)
              && changedKeys().hasOnly(['status', 'closedReason', 'closedAt', 'purgeAt'])
              && closesAs('resolved'))
        || (mayPropose(resource.data)
              && changedKeys().hasOnly(['status', 'closingReason', 'closingBy', 'closingAt'])
              && startsClosing('resolved'));
    }

    // Hâlâ orada: ömrü uzatır; eski "Artık yok" oylarını sıfırlayabilir.
    function isConfirm() {
      let before = resource.data;
      let after = request.resource.data;
      return changedKeys().hasOnly(['lastSeenAt', 'expiresAt', 'seenBy', 'goneReports'])
        && (after.goneReports == before.goneReports || after.goneReports.size() == 0)
        && refreshes(before, after);
    }

    // Artık yok: koyan tek tanıksa hemen; koyan/ilgilenen "Artık yok dendi"; diğerleri oy verir,
    // 3. oy (başkasının canlı sahipliği yoksa) "Artık yok dendi" yapar.
    function isGoneReport() {
      let before = resource.data;
      let after = request.resource.data;
      let keys = changedKeys();
      return !(me() in before.goneReports)
        && after.goneReports == before.goneReports.concat([me()])
        && (keys.hasOnly(['goneReports'])
            || (reporterAlone(before)
                && keys.hasOnly(['goneReports', 'status', 'closedReason', 'closedAt', 'purgeAt'])
                && closesAs('gone'))
            || (keys.hasOnly(['goneReports', 'status', 'closingReason', 'closingBy', 'closingAt'])
                && startsClosing('gone')
                && mayPropose(before)
                && (isReporter(before) || isClaimer(before)
                    || (!hasLiveClaim(before) && after.goneReports.size() >= 3))));
    }

    // ---- closing üzerindeki eylemler ----

    // Hâlâ yardım gerekiyor: kapatan dışında herkes; koyan sınırsız, diğerleri bir kez.
    function isObjection() {
      let before = resource.data;
      let after = request.resource.data;
      return before.closingBy != me()
        && changedKeys().hasOnly(['status', 'closingReason', 'closingBy', 'closingAt',
                                  'claimedBy', 'claimedAt', 'claimExpiresAt', 'goneReports',
                                  'objectors', 'disputed', 'lastSeenAt', 'expiresAt', 'seenBy'])
        && after.status == 'open'
        && after.closingReason == null
        && after.claimedBy == null
        && after.goneReports.size() == 0
        && after.disputed == before.disputed.concat([before.closingBy])
        && ((isReporter(before) && after.objectors == before.objectors)
            || (!isReporter(before)
                && !(me() in before.objectors)
                && after.objectors == before.objectors.concat([me()])))
        && refreshes(before, after);
    }

    // Evet, çözüldü: ikinci kişi onaylar. Kapatan başkasıysa koyan; kapatan koyansa hayvanı gören biri.
    function isAgree() {
      let before = resource.data;
      return ((isReporter(before) && before.closingBy != me())
              || (before.closingBy == before.reporterId && !isReporter(before)
                  && (me() in before.seenBy)))
        && changedKeys().hasOnly(['status', 'closedReason', 'closedAt', 'purgeAt'])
        && closesAs(before.closingReason);
    }

    // Geri al: kapatma önerisini yapan 10 dk içinde.
    function isUndo() {
      let before = resource.data;
      let after = request.resource.data;
      return before.closingBy == me()
        && request.time < before.closingAt + undoWindow()
        && changedKeys().hasOnly(['status', 'closingReason', 'closingBy', 'closingAt',
                                  'claimedBy', 'claimedAt', 'claimExpiresAt'])
        && after.status == 'open'
        && after.closingReason == null
        && after.claimedBy == null;
    }

    // Süresi dolan işareti herkes kapatabilir (Spark'ta temizlik fonksiyonu yok); asla erken değil.
    function isExpire() {
      let before = resource.data;
      return before.status in ['open', 'claimed', 'closing']
        && before.expiresAt <= request.time
        && changedKeys().hasOnly(['status', 'closedReason', 'closedAt', 'purgeAt'])
        && ((before.status != 'closing' && closesAs('expired'))
            || (before.status == 'closing' && closesAs(before.closingReason)));
    }

    // Geri al (silme): yalnızca koyanın, kimsenin görmediği/dokunmadığı işareti.
    function canRetract(r) {
      return isReporter(r) && r.status == 'open' && r.seenBy == [me()]
        && r.goneReports.size() == 0 && r.disputed.size() == 0;
    }

    match /reports/{reportId} {
      allow read: if signedIn();                       // Tier B: split get / list
      allow create: if signedIn() && validCreate(request.resource.data);
      allow update: if signedIn()
        && validShape(request.resource.data)
        && identityUnchanged()
        && ((isWaiting(resource.data) && isLive(resource.data)
              && (isClaim() || isRelease() || isResolve() || isConfirm() || isGoneReport()))
            || (resource.data.status == 'closing' && isLive(resource.data)
              && (isObjection() || isAgree() || isUndo()))
            || isExpire());
      allow delete: if signedIn() && canRetract(resource.data);
    }
  }
}
```

Check these rules-language points in the emulator before relying on them:
- `serverTimestamp()` equals `request.time` inside a transaction. This is the standard pattern; use `serverTimestamp()` from `firebase/firestore` in the tests.
- List equality `r.seenBy == [me()]`.
- `closesAs(before.closingReason)`, a string passed as a parameter.
- Evaluation stays within the 1,000-expression limit.

I avoided the ternary operator on purpose.

### 5b. AnimalKit changes

```swift
// Report.swift
public enum ReportStatus: String, Sendable { case open, claimed, closing, closed }

/// "Çözüldü dendi" / "Artık yok dendi": doğrulanmamış kapatma önerisi.
public struct Closing: Hashable, Sendable {
    public var reason: ClosedReason        // .resolved | .gone
    public var userID: String
    public var at: Date                    // Firestore'a serverTimestamp() yazılır
}
// Report: + closing: Closing?, objectors: [String], disputed: [String]
// ReportField: + closingReason, closingBy, closingAt, objectors, disputed (changedFields'e ekle)

public enum ReportPhase: Hashable, Sendable {
    case waiting
    case helpedByMe(until: Date)
    case helpedByOther(since: Date)
    case closing(reason: ClosedReason, since: Date, byMe: Bool)   // haritada kalır
    case closed(ClosedReason)
}
// phase(): closed → .closed; expiresAt <= now → .closed(closing?.reason ?? .expired);
//          status == .closing → .closing(...); sonra mevcut claim mantığı.
// isActive(at:) aynı kalır (closing aktif sayılır); + isWaiting(at:) = status ∈ {open, claimed} && expiresAt > now

// ReportLifecycle.swift
public enum ReportAction { case claim, release, resolve, confirmStillThere, reportGone,
                           dispute /* "Hâlâ yardım gerekiyor" */, confirmClosing /* "Evet, çözüldü" */,
                           undoClosing /* "Geri al" */, expire /* gösterilmez */ }
// ReportError += .disputed, .claimTooFresh, .alreadyObjected, .notExpired

public static let goneThreshold = 3
public static let claimStale: TimeInterval = 45 * 60
public static let undoWindow: TimeInterval = 10 * 60
public static let maxAge: TimeInterval = 7 * 24 * 3600
public static let maxDisputed = 10

static func reporterAlone(_ r: Report, _ u: String) -> Bool { r.reporterID == u && r.seenBy == [u] }
static func mayPropose(_ r: Report, _ u: String, at now: Date) -> Bool {
    guard !r.disputed.contains(u), r.disputed.count < maxDisputed else { return false }
    guard let c = r.activeClaim(at: now) else { return true }
    return c.userID == u || r.reporterID == u || now >= c.claimedAt.addingTimeInterval(claimStale)
}
static func lifeCap(_ r: Report) -> Date { r.createdAt.addingTimeInterval(maxAge) }

// apply(): guard by action group — waiting actions need isWaiting(at: now); dispute/confirmClosing/
// undoClosing need status == .closing && expiresAt > now; expire needs status != .closed && expiresAt <= now.
case .claim:        guard claim == nil, !report.disputed.contains(u) → claim; expiresAt = max(old, min(claimExp, lifeCap))
case .release:      guard isClaimer || (isReporter && claim != nil && now >= claim.claimedAt + claimStale)
case .resolve:      reporterAlone ? close(.resolved) : (mayPropose ? startClosing(.resolved) : throw)
case .confirmStillThere: refresh (expiresAt = max(old, min(now + lifetime, lifeCap)), seenBy append); goneReports = []
case .reportGone:   append vote; reporterAlone ? close(.gone)
                    : if mayPropose && (isReporter || isClaimer || (claim == nil && votes >= goneThreshold)) → startClosing(.gone)
case .dispute:      guard closing.userID != u, isReporter || !objectors.contains(u)
                    → status .open, closing nil, claim nil, goneReports [], disputed += closing.userID,
                      objectors += u (unless reporter), refresh()
case .confirmClosing: guard (isReporter && closing.userID != u)
                      || (closing.userID == reporterID && !isReporter && seenBy.contains(u)) → close(closing.reason)
case .undoClosing:  guard closing.userID == u && now < closing.at + undoWindow → status .open, closing nil, claim nil
case .expire:       close(status == .closing ? closing!.reason : .expired)

// availableActions():
//  .closing(byMe: true)  → now < since+undo ? [.undoClosing] : []
//  .closing(byMe: false) → (canConfirmClosing ? [.confirmClosing] : []) + (reporter || !objectors.contains(u) ? [.dispute] : [])
//  .waiting              → [.claim (if !disputed), .confirmStillThere] + (mayPropose ? [.resolve] : [])  // passerby: secondary
//  .helpedByMe           → [.resolve, .release]
//  .helpedByOther        → (mayPropose ? [.resolve] : []) + [.confirmStillThere] + (reporter && stale ? [.release] : [])
//  + .reportGone if not already voted (not in closing)
```

`FirestoreReportMapper.changes(from:to:)` writes `FieldValue.serverTimestamp()` for `claimedAt` and `closingAt` whenever they change to a non-nil value.

### 5c. Contract and test harness

`shared/report-contract.json`:

```json
"claimHours": 3,
"claimStaleMinutes": 45,
"undoMinutes": 10,
"maxReportAgeDays": 7,
"goneThreshold": 3,
"maxDisputed": 10,
"statuses": ["open", "claimed", "closing", "closed"]
```

- **`contract.test.ts`:** add checks that the rules contain:
  - `duration.value(45, 'm')`, `duration.value(10, 'm')`, `duration.value(7, 'd')`
  - `function maxDisputed() { return 10; }`
  - `d.status in ['open', 'claimed', 'closing', 'closed']`
  - `after.goneReports.size() >= 3` (already checked; the value changes)
- **`helpers.ts`:**
  - Extend the contract type.
  - `openReport` gains `closingReason: null, closingBy: null, closingAt: null, objectors: [], disputed: []`.
  - `claimFields` uses `serverTimestamp()`.
  - Add `closingFields(reason)` and a `closingReport(by, reason)` seed.
- **Swift:** add the new fields to `ContractTests.swift` and `SharedFixtures.ReportContract`.

---

## 6. What a motivated group can still do

- **Labels in bulk.** Tier A cannot limit how much one uid does, because that needs Tier B's users doc. One phone can put "Çözüldü dendi" on every report in a district at night. Nothing disappears early, one tap undoes each label, and the labeller cannot repeat on a report after an objection. But in quiet areas, volunteers may skip labelled pins until the report expires. Tier B budgets and Tier C push are the real fix.
- **Report capture with one accomplice.** A hostile person reports animals first. Legitimate people then confirm that report through "Ben de gördüm". Later the hostile person proposes a close as reporter and an accomplice in `seenBy` confirms it (or the roles are reversed), and the report is gone. This takes two devices. A7 prompts the people who confirmed; Tier C adds reopen with push.
- **Griefing in the pro-animal direction.**
  - A hostile person can object once per report to real rescues. The rescued animal stays on the map until it expires, and the rescuer can no longer close that report.
  - A hostile person can tap "Hâlâ orada" on new reports so the reporter loses the instant close.
  - Both cost volunteers wasted trips, not animals.
- **Squat refresh.** Releasing and claiming again every 45 min keeps "Biri ilgileniyor" fresh and delays other people's "Çözüldü" and the 3-vote close on that one report. It never hides the report.
- **Scripter.** Before enforcement, a script can do all of the above with unlimited uids, plus spam, a full dump, and a quota outage. After enforcement it can still replay bearer tokens taken from a jailbroken device (30–60 min each), anonymous sign-up over REST may not be gated, and it can build aged uid farms. On Spark the quota cliff means an outage, not a bill. Only Blaze plus C3 really closes this.
- **Rules cannot check presence.** GPS is supplied by the client, so every action can be done from the sofa.
- **Fake or lure reports** can be kept alive for at most 7 days. Add a safety line to the card: "Yalnız gitme, kimseyle tartışmaya girme."
  *Later change (card redesign):* the line left the card, where people learned to skip it. The same guidance now
  arrives when someone commits to going: a one-time "Yardıma gidiyorsun" alert on the first "İlgileniyorum" or
  "Yol tarifi" ("Yalnız gitme, kimseyle tartışmaya girme, özel mülke girme. Hayati tehlike varsa 112'yi ara."),
  the night reminder (unchanged), the onboarding rule (unchanged) and "Mümkünse biriyle git." appended to the
  claim toast on acil/yaralı/yavru reports.
- **Keychain.** Keeping the uid across a reinstall is observed behaviour, not a guarantee. Erase All Content or a second device gives a new uid, but every Tier A guarantee is stated in terms of devices and uids anyway.

**Separate risk: exposed locations.**
- **What is exposed:** any anonymous user sees the exact lat/lng and geohash-10 of injured animals and litters. They can list the whole collection, including closed history, which is kept forever while TTL is blocked. The data also carries uid trails (`reporterId`, `claimedBy`, `seenBy`, `goneReports`, `closingBy`, `disputed`), from which someone can work out who rescues where and when.
- **Mitigation 1:** B2's list restriction with a limit, together with App Check enforcement, removes the bulk dump and the history.
- **Mitigation 2:** for vulnerable needs, the public doc stores a coarse point: the geohash-7 cell centre (about 150 m), with rounded coordinates so geohash range queries still work. The exact point goes in `reports/{id}/private/loc`, readable by the reporter, the live claimer, and (after B3) accounts at least 72 h old. The rule costs one `get()` of the parent report. Later, per-report pseudonymous uids through `hashing.sha256` (to be checked).

---

## 7. Decisions for the owner

1. **How "Çözüldü dendi" behaves.**
   - *Recommended default:* the report stays until its normal expiry unless a second person confirms it. It is shown faded but visible; emergency, injured and babies keep full colour. It is left out of "N hayvan yardım bekliyor".
   - *Alternative:* the label ends at most 24 h after it was set. This means less clutter for rescued litters and 72 h reports, but one person can then cut a report's lifetime short.
2. **Location precision for vulnerable needs.**
   - *Recommended default:* exact location for emergency, injured, vet, food, shelter and other. For "Yavruları var", a coarse public point (about 150 m) plus the exact point on claim, shipped with B3. Revisit "Yaralı" after watching real abuse. Do B2 in any case.
3. **Move to Blaze, with a small budget alert, before public launch?**
   - *Recommended: yes.* It enables push notifications to reporters (the missing piece for labels), TTL deletion of closed history, the sweep, and identities created only through Functions. It also turns a quota attack into a small bill instead of an outage for everyone.

Adjustable constants, not decisions: `goneThreshold` 3, `claimStaleMinutes` 45, `undoMinutes` 10, `maxReportAgeDays` 7, `maxDisputed` 10.

---

## Appendix: what was kept from each design and what was dropped

| Idea | From | Outcome |
|---|---|---|
| Non-reporter closes become a soft "closing" state | all three | **Kept.** No 2 h or 8 h auto-finalize; it ends only by expiry or a second person (the red team broke the timed windows at night, and the 8 h window shortened reports). |
| Reporter-only instant close | reversible, sybil | **Kept, narrowed** to `seenBy == [reporter]` (report-capture fix), and the retract hole is closed. |
| `reopenCount` and 24 h reopen | rules-only, reversible | **Moved to Tier C with push** (the count could lock a report, and reopen-by-anyone created never-ending reports). Closed stays final in Tier A. |
| Protection ladder (count of objectors) | reversible | **Replaced** by `disputed`, which is always appended and caps closes, not disputes; plus one objection per non-reporter and unlimited for the reporter. |
| Claim needed to close, minimum hold time, claim takeover | all three | **Dropped.** Claims are advisory, with a 45 min fresh-claim window and reporter release of stale claims. |
| Threshold 3, no claimer shortcut | reversible, sybil | **Kept.** The claimer's "Artık yok" leads to closing; votes cannot start closing over a live claim; votes reset when someone confirms or objects. |
| Weight-0 votes stored in `goneReports`; one claim per report per uid (`claimers`) | rules-only, sybil | **Dropped.** They filled the list and used up honest voters' votes. |
| Server-time `claimedAt` / `closingAt` | red-team fix | **Kept.** |
| Lazy expiry; cap on total report lifetime | rules-only, reversible, red team | **Kept** in Tier A. |
| users doc: age, budgets, ban | all three | **Tier B**, with spends bound to one report (`last == {t,id}`) against batch multiplication. |
| Strikes, flags log, "quiet" bans | rules-only, sybil | **Dropped / Tier C.** Strikes and dispute flags could be turned against real volunteers, and the "quiet" ban was not quiet. |
| App Attest, no sign-out, sign-up quota, list limits | all three and red teams | **Provider in the Tier A build; enforcement and read limits in Tier B.** |