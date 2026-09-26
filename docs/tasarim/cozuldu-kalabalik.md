# "Çözüldü" without clutter: budgeted closes that leave the map

This replaces the default in plan §7, decision 1.

**Short answer to the owner's question:** yes. Under the plan's current default, a rescued animal whose reporter never comes back stays on everyone's map for 10–70 h. With this proposal, in the common case (a volunteer whose app is at least one day old taps "Çözüldü"), the pin leaves other people's maps after 1 hour of daytime for food and "Diğer", and after 2 hours for the other needs. One phone can do this only a few times a day. A fast removal never deletes anything before the report's normal expiry, and the owner can undo all of them with one switch.

Where the parts come from:
- **From "evidence":**
  - a per-uid daily budget in `users/{uid}`, tied to one report with `getAfter`;
  - hiding is decided by each viewer's app, and nothing is written as final;
  - a remote switch, now read with a live listener.
- **From "display":**
  - nothing is finalized early;
  - night hours do not count;
  - the people who can check (the reporter and anyone who confirmed the animal) keep seeing the pin;
  - the `displayPriority` fix.
- **From "lifetime-cap":**
  - the fast path gets no reward on the map (no green tick);
  - the daytime clock counts minutes, not whole hours;
  - the budget is weighted by need (the red team's "bigger allowance for food/other").
- **Dropped:**
  - evidence from how long a claim was held (10 or 20 min);
  - STRONG/WEAK per-report tiers;
  - claim slots;
  - early finalize in the rules;
  - the widened "Evet, çözüldü";
  - grey ticks that cost nothing.
- **New:**
  - a "Çözüldü" that is not backed by budget no longer changes the pin's colour or the count. It only adds a "?".
  - optionally, a second volunteer can back an unverified close with their own budget ("Doğru, çözülmüş").

---

## 1. The recommendation (for the owner)

1. **The volunteer who taps "Çözüldü"**
   - They do not need to tap "İlgileniyorum" first.
   - The pin leaves their own map at once.
   - The thank-you message says when it will leave everyone else's map: "yaklaşık 1 saat", "yaklaşık 2 saat", or "saat 08.00 civarında" at night.
   - "Geri al" works for 10 minutes.
2. **What everyone else sees during those 1–2 daytime hours**
   - The pin shows a small "?" and the card says "Çözüldü dendi · Haritadan kalkış: 14.20".
   - Food and "Diğer" pins turn pale. Emergency, injured, babies, vet and shelter pins keep their full colour.
   - The pin no longer counts in "N hayvan yardım bekliyor".
   - After that it is gone from their map. A small grey dot shows only when someone zooms into a few streets, so a person standing there can tap "Hâlâ yardım gerekiyor".
3. **Night does not count.**
   - Only 07:00–24:00 Turkish time counts toward the 1–2 hours.
   - A rescue at 02:00 leaves others' maps at 08:00 (food, other) or 09:00 (other needs).
   - A rescue at 23:30 leaves at 07:30 or 08:30.
4. **The limit that stops abuse**
   - Each phone has **8 points per 24 hours** for fast removal. Food and "Diğer" cost 1 point; every other need costs 2.
   - The app must be at least one day old. This does not apply when you close an animal you reported yourself.
   - A report that already had 2 objections cannot be removed early.
5. **Everything else only adds a "?"**
   - This covers a brand-new app, a used-up budget, or a report that already had 2 objections.
   - The "Çözüldü" is recorded, but the pin keeps its colour and still counts as waiting.
   - It stays until one of these happens: the reporter confirms, another volunteer taps "Doğru, çözülmüş" (spending their own points), or the report expires.
   - A troll can put a "?" on every pin, and that hides nothing.
6. **Nothing is deleted early.**
   - Until the pin's normal expiry, anyone who sees the animal can tap "Hâlâ yardım gerekiyor". The pin then comes back at full size with a fresh lifetime.
   - The reporter and people who confirmed the animal keep seeing the pin until they answer "Doğru mu?" the next time they open the app.
   - The reporter's "Evet, çözüldü" still removes it at once.
7. **The owner's switch** is `config/public.closingMode` in the console:
   - `demote`: normal behaviour.
   - `label`: the plan's old behaviour, where the label stays until expiry.
   - `strict`: every "Çözüldü" is only a "?".
   - A change reaches open apps within seconds and other apps the next time they open, and brings back every hidden pin.
8. **When to turn it on**
   - Turn it on for TestFlight now.
   - For the public, turn it on only on the day App Check enforcement (Tier B, B1) goes live. Until then, use `label`.
   - The budget itself ships now and works on the free plan, because closing a report already needs a connection.

**When a genuinely rescued animal leaves other people's maps.** Common case: resolved 2 h after it was last seen, the reporter never returns, and the volunteer's app is at least 1 day old and has points left.

| Need (lifetime) | Plan default (typical / max) | Rescue between 07:00 and 23:00 | Rescue at 02:00 | Average over all daytime rescues |
|---|---|---|---|---|
| Acil (12 h) | 10 / 12 h | 2 h | 7 h (until 09:00) | 2.8 h |
| Yaralı (24 h) | 22 / 24 h | 2 h | 7 h | 2.8 h |
| Yavru (72 h) | 70 / 72 h | 2 h | 7 h | 2.8 h |
| Veteriner (48 h) | 46 / 48 h | 2 h | 7 h | 2.8 h |
| Barınak (72 h) | 70 / 72 h | 2 h | 7 h | 2.8 h |
| Mama (12 h) | 10 / 12 h | 1 h | 6 h (until 08:00) | 1.4 h |
| Diğer (24 h) | 22 / 24 h | 1 h | 6 h | 1.4 h |

- The averages in the last column come from the evening edge: a close between 22:00 and 24:00 on a 2-hour need waits overnight.
- On a mix of 100 rescues (food 40, injured 20, other 10, emergency 10, babies 10, vet 5, shelter 5), pin-hours on other people's maps drop from about 2,440 to about 210. That is **about 90% less** for rescues that qualify.

---

## 2. Scenarios

Pin looks on the map of a viewer who is neither the reporter nor someone who confirmed the animal:
- **Label**: the pin stays with a "?". It is pale for food/other and keeps full colour for the other needs. It is **not counted** as waiting.
- **Hidden**: the pin is not drawn. The exceptions are a grey dot at street zoom, and the reporter and people who confirmed the animal, who see it until they answer.
- **"?" pin**: normal colour and size plus "?". It **is counted** as waiting.

In the table, W means 1 h for food/other and 2 h for the other needs, counted in daytime hours only.

| Scenario | Tier A build (mode `demote`; TestFlight, attackers using the real app) | After Tier B (public; B1 App Check + B3; mode `demote`) |
|---|---|---|
| **Legit: reporter alone** (nobody else confirmed) | Closed at once (plan). 0 h. | Same. |
| **Legit: reporter after others confirmed** | No age check, costs points. Label for W, then hidden. People who confirmed it keep seeing it until they answer. Any one of them saying "Evet" closes it at once (plan's isAgree). | Same. |
| **Legit: claimer, reporter never returns** | App ≥ 1 day old with points left: label for W, then hidden. A close between 00:00 and 07:00 hides at 08:00 or 09:00. Otherwise (app < 1 day, budget used, ≥ 2 objections): "?" pin, full colour and counted, until expiry (10–70 h), the reporter's "Evet", or a second volunteer's "Doğru, çözülmüş". | Same, except accounts 24–72 h old have 4 points, so a third serious rescue in one day becomes "?". |
| **Legit: passerby** (no claim) | Identical to the claimer row; a claim is not needed. Blocked only while someone else's claim is under 45 min old (A4). | Same. |
| **Attacker: quick close** | Aged uid: label for W, then hidden until an objection or expiry. On a fresh report that is up to 10 h (emergency), 11 (food), 22 (injured), 23 (other), 46 (vet), 70 (babies/shelter). At most 8 points per 24 h, so 4 serious or 8 food/other pins per phone. New or reinstalled uid: "?" only, **0 hidden** for 24 h. | Accounts over 72 h: same. Accounts 24–72 h: 2 serious or 4 light. Banned: 0. |
| **Attacker: claim, wait, resolve** | Same as quick close; credibility ignores claims. 20 parallel claims then 20 closes: 4 serious (or 8 light) hidden, and the other 16 become counted "?" pins. Side effect, a plan residual: his fresh claims block other people's "Çözüldü" for 45 min. | Same, with the budgets above. |
| **Attacker at night** | At most 8 points. He can get 16 once by straddling his 24 h window boundary, then 0 for the next 24 h. Every one stays labelled until 08:00 (light) or 09:00 (serious). The reporter and people who confirmed it see it and get asked when they open the app. After that it is hidden until objection or expiry. Example: a report created at 23:00 and hit at 01:00 is hidden for 2 h (emergency), 3 (food), 14 (injured), 15 (other), 38 (vet), 62 (babies/shelter). | Same, with 4-point young accounts and bans. |
| **3-phone group** | 24 points a day: 12 serious or 24 light hidden. A "3 × Artık yok" close costs only the third voter's points. "?" labels are unlimited and change nothing. Report capture is a plan residual: one phone reported first, a second phone in the confirmer list says "Evet", and the report is closed at once with no points. Unlimited for reports the group reported first. | 24 points a day (12 with young accounts). Report capture is limited by B3's proposal budget (3/8 per day per uid). |
| **REST script** (for completeness) | Before B1, unlimited uids can be created and are old enough after 24 h. That is why public mode stays `label` until B1. In `label`, budget-backed closes show only the plan's labels and other closes are "?", so this is no worse than the plan. | Needs App Check tokens replayed from a jailbroken device. The sign-up quota of 20 per IP per hour gives about 480 uids per IP per day, so about 1,900 points per IP per day from day 2 and about 3,800 from day 4. Residual; see §6. |

**Attacker cost, one phone, in plain numbers**
- One hidden report costs one close transaction (about 5 s of taps) plus 1 or 2 of the 8 daily points of a uid that is at least 24 h old.
- On the real app a phone holds one uid at a time, so no amount of effort beats 8 points per 24 h.
- A reinstall or erase resets the wait to 24 h.
- Worst case per phone per day: 4 fresh babies or shelter reports hidden for about 70 h each, about 280 report-hours.
- How the designs compare for one phone before Tier B:

| Design | What one phone can do |
|---|---|
| Plan default | 0 hidden, but unlimited pale, uncounted labels |
| Display-first as written | About 330 grey ticks per hour |
| Lifetime-cap as written | 24 per night, 72 per day |
| Evidence as written | 4 per day, but 2 phones could finalize anything |
| **This proposal** | **8 points per day, never finalized; unlimited "?" labels hide nothing** |

**Safety tier:**
- Against one phone running the real app, this is safe now (Tier A with the users doc).
- Against REST scripts it is safe only after B1. So `demote` for the public is a launch blocker tied to B1.
- B3's ban flag and the 4-point tier for young accounts should ship the same day.

---

## 3. Exact constants

**Budget (rules + contract)**
- `credPoints` = 8 per window.
- `credSpan` = 24 h, rolling. A new window starts at the first spend after the previous window ended, so at most 16 points can fall around one boundary.
- `credCost`: emergency 2, injured 2, babies 2, vet 2, shelter 2 ("serious"); food 1, other 1 ("light").
- `credMinAge` = 24 h from `users.createdAt`, which is server time. It does not apply when the closer is the report's reporter.
- `credMaxDisputed` = 1: a close is budget-backed only while `disputed.size() <= 1`.

**Display (client + contract)**
- `demoteMinutes`: 120 for serious needs, 60 for light needs.
- Daytime clock: 07:00–24:00 Europe/Istanbul, fixed UTC+3, counted to the minute. 00:00–07:00 does not count.
- While labelled: serious needs keep full colour; light needs are drawn at 60% opacity (combined with the existing freshness fade by taking the minimum).
- Grey dot for hidden closings: drawn only when the visible radius is 600 m or less. It is a 14 pt disc with a 20 pt image and a larger hit area, `displayPriority .defaultLow`, and the lowest `zPriority`.
- `closingMode` ∈ {`demote`, `label`, `strict`}. Default when unknown: `label`.
  - TestFlight: `demote`.
  - Public before B1: `label`.
  - Public after B1 + B3: `demote`.

**Unchanged from the plan:** undo 10 min, claimStale 45 min, claim 3 h, goneThreshold 3, maxAge 7 d, maxDisputed 10, A7 cadence 10 min.

**Tier B:** accounts 24–72 h old get 4 points, older accounts 8, banned accounts 0. Sign-up quota about 20 per IP per hour.

`shared/report-contract.json`:
```json
"needs": {
  "emergency": { "lifetimeHours": 12, "closeCost": 2, "demoteMinutes": 120 },
  "injured":   { "lifetimeHours": 24, "closeCost": 2, "demoteMinutes": 120 },
  "babies":    { "lifetimeHours": 72, "closeCost": 2, "demoteMinutes": 120 },
  "vet":       { "lifetimeHours": 48, "closeCost": 2, "demoteMinutes": 120 },
  "shelter":   { "lifetimeHours": 72, "closeCost": 2, "demoteMinutes": 120 },
  "food":      { "lifetimeHours": 12, "closeCost": 1, "demoteMinutes": 60 },
  "other":     { "lifetimeHours": 24, "closeCost": 1, "demoteMinutes": 60 }
},
"credibleClose":  { "points": 8, "windowHours": 24, "minAccountHours": 24, "maxDisputed": 1 },
"closingDisplay": { "dayStartHour": 7, "dayEndHour": 24, "utcOffsetHours": 3,
                    "streetDotMaxRadiusMeters": 600,
                    "modes": ["demote", "label", "strict"], "defaultMode": "label" }
```

---

## 4. Rules delta vs plan §5a, and the AnimalKit delta

### 4a. `firebase/firestore.rules` (delta on §5a; everything not shown is unchanged)

```
// ---- New constants (next to undoWindow() / maxAge()) ----
// Kanıtlı kapatma: kapatanın hesabı en az bu kadar eski olmalı (işareti koyan için aranmaz).
function credMinAge() { return duration.value(24, 'h'); }
// Kanıtlı kapatma bütçesi: 24 saatlik pencerede en fazla bu kadar puan.
function credPoints() { return 8; }
function credSpan() { return duration.value(1, 'd'); }
// Puan: ağır ihtiyaçlar 2, hafifler 1.
function credCost() {
  return {
    'emergency': 2,
    'injured': 2,
    'babies': 2,
    'vet': 2,
    'shelter': 2,
    'food': 1,
    'other': 1
  };
}
// Bundan fazla itiraz almış işarette kapatma kanıtlı sayılmaz.
function credMaxDisputed() { return 1; }
function userPath() { return /databases/$(database)/documents/users/$(me()); }

// ---- reportKeys(): + 'closingCredible' ----

// ---- validShape(d): the closing trio becomes a quartet ----
        && ((d.closingReason == null && d.closingBy == null && d.closingAt == null
               && d.closingCredible == null)
            || (d.closingReason in ['resolved', 'gone'] && d.closingBy is string
               && d.closingAt is timestamp && d.closingCredible is bool))
// validCreate(d): unchanged. d.closingReason == null already forces closingCredible == null.

// ---- Kanıtlı kapatma: bütçeden bu an ve bu işaret için harcanmış puan ----
// users/{me} yalnızca closingCredible == true istendiğinde okunur (1 okuma).
function credible(r, reportId) {
  let u = getAfter(userPath()).data;
  return r.disputed.size() <= credMaxDisputed()
    && (isReporter(r) || u.createdAt <= request.time - credMinAge())
    && u.credLast == {'t': request.time, 'id': reportId, 'w': credCost()[r.need]};
}

function startsClosing(reason, reportId) {
  let after = request.resource.data;
  return after.status == 'closing'
    && after.closingReason == reason
    && after.closingBy == me()
    && after.closingAt == request.time                    // serverTimestamp()
    && (after.closingCredible == false
        || (after.closingCredible == true && credible(resource.data, reportId)));
}

function isResolve(reportId) {
  return (reporterAlone(resource.data)
          && changedKeys().hasOnly(['status', 'closedReason', 'closedAt', 'purgeAt'])
          && closesAs('resolved'))
    || (mayPropose(resource.data)
          && changedKeys().hasOnly(['status', 'closingReason', 'closingBy', 'closingAt',
                                    'closingCredible'])
          && startsClosing('resolved', reportId));
}

function isGoneReport(reportId) {
  let before = resource.data;
  let after = request.resource.data;
  let keys = changedKeys();
  return !(me() in before.goneReports)
    && after.goneReports == before.goneReports.concat([me()])
    && (keys.hasOnly(['goneReports'])
        || (reporterAlone(before)
            && keys.hasOnly(['goneReports', 'status', 'closedReason', 'closedAt', 'purgeAt'])
            && closesAs('gone'))
        || (keys.hasOnly(['goneReports', 'status', 'closingReason', 'closingBy', 'closingAt',
                          'closingCredible'])
            && startsClosing('gone', reportId)
            && mayPropose(before)
            && (isReporter(before) || isClaimer(before)
                || (!hasLiveClaim(before) && after.goneReports.size() >= 3))));
}

// isObjection(): hasOnly list gains 'closingCredible'
//   ['status','closingReason','closingBy','closingAt','closingCredible','claimedBy','claimedAt',
//    'claimExpiresAt','goneReports','objectors','disputed','lastSeenAt','expiresAt','seenBy']
// isUndo(): hasOnly list gains 'closingCredible'
//   ['status','closingReason','closingBy','closingAt','closingCredible','claimedBy','claimedAt','claimExpiresAt']
// (validShape forces closingCredible back to null together with closingReason.)
// isAgree(), isExpire(): UNCHANGED. closingCredible stays as history. isAgree is NOT widened.

// OPTIONAL (same schema, can ship later): "Doğru, çözülmüş"/"Doğru, artık yok".
// Doğrulanmamış kapatmayı, kapatan dışında biri kendi bütçesinden kanıtlı yapar ve sorumluluğu üstlenir.
// Asla closed yapmaz; itiraz ve süre kuralları aynen geçer.
function isVouch(reportId) {
  let before = resource.data;
  let after = request.resource.data;
  return before.closingCredible == false
    && before.closingBy != me()
    && !(me() in before.disputed)
    && changedKeys().hasOnly(['closingBy', 'closingAt', 'closingCredible'])
    && after.closingBy == me()
    && after.closingAt == request.time                    // serverTimestamp(); W yeniden başlar
    && after.closingCredible == true
    && credible(before, reportId);
}

match /reports/{reportId} {
  allow read: if signedIn();                              // Tier B: split get / list (B2)
  allow create: if signedIn() && validCreate(request.resource.data);
  allow update: if signedIn()
    && validShape(request.resource.data)
    && identityUnchanged()
    && ((isWaiting(resource.data) && isLive(resource.data)
          && (isClaim() || isRelease() || isResolve(reportId) || isConfirm()
              || isGoneReport(reportId)))
        || (resource.data.status == 'closing' && isLive(resource.data)
          && (isObjection() || isAgree() || isUndo() || isVouch(reportId)))
        || isExpire());
  allow delete: if signedIn() && canRetract(resource.data);
}

// ---- users/{uid}: hesap yaşı + kapatma bütçesi (Tier A; B3 aynı dokümanı genişletir) ----
match /users/{uid} {
  allow get: if signedIn() && me() == uid;
  allow create: if signedIn() && me() == uid
    && request.resource.data.keys().hasAll(['createdAt', 'credWindow', 'credUsed', 'credLast'])
    && request.resource.data.keys().hasOnly(['createdAt', 'credWindow', 'credUsed', 'credLast'])
    && request.resource.data.createdAt == request.time      // serverTimestamp()
    && request.resource.data.credWindow == request.time
    && request.resource.data.credUsed == 0
    && request.resource.data.credLast == null;
  // Tek izinli değişiklik: bir işaret için puan harcamak. İşaret kuralı credLast'ı getAfter ile
  // bu an ve bu işaretle eşleştirir; bir toplu yazımdaki tek harcama iki işarete yetmez.
  allow update: if signedIn() && me() == uid
    && request.resource.data.diff(resource.data).affectedKeys()
         .hasOnly(['credWindow', 'credUsed', 'credLast'])
    && request.resource.data.credLast.keys().hasAll(['t', 'id', 'w'])
    && request.resource.data.credLast.keys().hasOnly(['t', 'id', 'w'])
    && request.resource.data.credLast.t == request.time     // serverTimestamp() inside the map
    && request.resource.data.credLast.id is string
    && request.resource.data.credLast.w in [1, 2]
    && ((request.time < resource.data.credWindow + credSpan()
          && request.resource.data.credWindow == resource.data.credWindow
          && request.resource.data.credUsed
               == resource.data.credUsed + request.resource.data.credLast.w)
        || (request.time >= resource.data.credWindow + credSpan()
          && request.resource.data.credWindow == request.time
          && request.resource.data.credUsed == request.resource.data.credLast.w))
    && request.resource.data.credUsed <= credPoints();
  allow delete: if false;
}

// ---- Uzaktan gösterim modu (yalnızca konsoldan yazılır) ----
match /config/{doc} {
  allow get: if signedIn();
}
```

**Tier B additions**, on top of the B3 users doc:
```
// credible(): add
    && u.get('banned', false) != true
// users update: young accounts get half the points
    && (request.resource.data.credUsed <= 4
        || resource.data.createdAt <= request.time - duration.value(72, 'h'))
// B3's closingByNew is dropped: closingCredible replaces it. B3's objection budget stays.
// `banned` is console-only: create uses hasOnly without it, and update's affectedKeys guard stops removal.
```

**Checked against the real repo and §5a**
- **Today's rules file is still the pre-plan version.** `firebase/firestore.rules` has:
  - `isActive` = open|claimed;
  - the claimer's "Çözüldü" closes at once;
  - `isNow(claimedAt)` with ±15 min;
  - `goneReports.size() >= 2`;
  - the retract hole.

  This delta applies to §5a and must ship in the same release.
- **Only two server-stamped values are trusted:** `closingAt == request.time` (§5a) and `credLast.t == request.time`. The design never reads `claimedAt`. So the ±15 min backdate that today's `isNow(claimedAt)` allows cannot fake credibility, even if §5a's claim fix slipped.
- **§5a already freezes the closing fields while `closing`.**
  - isAgree and isExpire touch only the four `closed*` fields.
  - isObjection and isUndo null the whole group.
  - `seenBy` is also frozen, because isConfirm runs only under `isWaiting`.

  Adding `closingCredible` to the two lists keeps this true.
- **isAgree stays exactly as in §5a.** The evidence proposal's "any seenBy member" version let two phones finalize any report, because joining `seenBy` costs one "Hâlâ orada" tap with no presence check.
- **`reportId` must be passed as an argument.** Functions declared at the documents level cannot see the nested `{reportId}` wildcard. `$(database)` is visible there.
- **Every create must now write `closingCredible: null`,** because `validShape` uses `hasAll(reportKeys())`. That means `FirestoreReportMapper.data(for:)` and `helpers.ts` `openReport`. Production has no docs (TestFlight is in demo mode), so no migration is needed. Old builds' creates would be rejected, so rules and app ship together.
- **A missing users doc denies the write:** `getAfter(...).data` fails. The client sends `true` only after reading an existing users doc in the same transaction.
- **One spend cannot pay for two reports:** `credLast.id` names one report, and the users rule allows exactly one increment per commit.
- **`getAfter` runs, and is billed, only when `closingCredible == true`,** because `&&` short-circuits. It uses 1 of the 10 access calls.
- **Cost:** a budget-backed close adds 2 reads (the transaction's read of users/me, plus getAfter) and 1 write. There is 1 users-doc create per install, and the config listener costs 1 read per attach plus 1 per change.
- **Contract test (`firebase/tests/contract.test.ts`)**
  - Its checks are substring `toContain`, so the second `duration.value(24, 'h')` is harmless.
  - The per-need lifetime regex (`'food': 12\b`) scans the whole file. Add checks for `function credPoints() { return 8; }`, `function credMaxDisputed() { return 1; }` and `duration.value(1, 'd')`.
  - Check `closeCost` only inside the `credCost()` body.
- **Map:** `displayPriority` is set only in `viewFor` (`ReportMapView.swift:363`). A pin that becomes a dot on the 30 s tick would keep `.required`. Set it in `apply()` (line 242): `.required` for pins and labels, `.defaultLow` for dots.
- **Check in the emulator:**
  - `serverTimestamp()` nested in the `credLast` map equals `request.time`;
  - map equality that contains a timestamp;
  - `u.get('banned', false)`;
  - `timestamp + duration` comparisons.

### 4b. AnimalKit delta (on top of plan §5b)

```swift
// Need.swift
public var isSerious: Bool { [.emergency, .injured, .babies, .vet, .shelter].contains(self) }
public var closeCost: Int { isSerious ? 2 : 1 }
public var demoteMinutes: Int { isSerious ? 120 : 60 }

// Report.swift
public struct Closing: Hashable, Sendable { var reason: ClosedReason; var userID: String; var at: Date; var credible: Bool }
// ReportField += closingCredible;  ReportPhase.closing(reason:since:byMe:credible:)

// CloseBudget.swift (new): users/{uid}
public struct CloseBudget: Hashable, Sendable { public var createdAt: Date; public var windowStart: Date; public var used: Int }

// ReportLifecycle.swift
public static let credibleMinAge: TimeInterval = 24 * 3600
public static let credibleWindow: TimeInterval = 24 * 3600
public static let crediblePoints = 8
public static let credibleMaxDisputed = 1
public static let dayStartHour = 7, dayEndHour = 24
public static let turkeyUTCOffset: TimeInterval = 3 * 3600

public enum CloseCredibility: Equatable { case credible, newAccount, budgetUsed, disputed, noAccount }

public static func credibility(of r: Report, by u: String, budget: CloseBudget?, at now: Date) -> CloseCredibility {
    guard let b = budget else { return .noAccount }
    guard r.disputed.count <= credibleMaxDisputed else { return .disputed }
    guard r.reporterID == u || now.timeIntervalSince(b.createdAt) >= credibleMinAge else { return .newAccount }
    return spend(b, cost: r.need.closeCost, at: now) == nil ? .budgetUsed : .credible
}
/// The users-doc write that goes with a budget-backed close; nil if over budget.
public static func spend(_ b: CloseBudget, cost: Int, at now: Date) -> CloseBudget? {
    var n = b
    if now < b.windowStart.addingTimeInterval(credibleWindow) { n.used += cost } else { n.windowStart = now; n.used = cost }
    return n.used <= crediblePoints ? n : nil
}
/// Leaves other people's maps after `need.demoteMinutes` of daytime (07:00–24:00, fixed UTC+3).
public static func demoteAt(closingAt: Date, need: Need) -> Date {
    var remaining = TimeInterval(need.demoteMinutes * 60), t = closingAt
    let start = TimeInterval(dayStartHour * 3600), end = TimeInterval(dayEndHour * 3600)
    while true {
        let local = (t.timeIntervalSince1970 + turkeyUTCOffset).truncatingRemainder(dividingBy: 86_400)
        if local < start { t += start - local; continue }          // night: jump to 07:00
        if remaining <= end - local { return t + remaining }
        remaining -= end - local; t += end - local                  // 24:00, then night
    }
}

public enum ClosingMode: String, Sendable { case demote, label, strict }   // config/public.closingMode
public enum ClosingLook: Equatable { case unverified, fading(leavesAt: Date?), hidden }

public static func look(of r: Report, mode: ClosingMode, isStakeholder: Bool, at now: Date) -> ClosingLook? {
    guard r.status == .closing, let c = r.closing else { return nil }
    guard c.credible, mode != .strict else { return .unverified }
    guard mode == .demote else { return .fading(leavesAt: nil) }
    let at = demoteAt(closingAt: c.at, need: r.need)
    return (now < at || isStakeholder) ? .fading(leavesAt: at) : .hidden
}
public static func countsAsWaiting(_ r: Report, userID: String?, mode: ClosingMode, at now: Date) -> Bool {
    if r.isWaiting(at: now) { return /* plan: .waiting phase, plus A4 stale claims */ r.phase(for: userID, at: now) == .waiting }
    return r.expiresAt > now && look(of: r, mode: mode, isStakeholder: false, at: now) == .unverified
}

// ReportAction += .vouchClosing ("Doğru, çözülmüş" / "Doğru, artık yok"), optional
// apply(_:to:by:at:credible:)
//   .resolve / .reportGone: startClosing(..., credible: credible)
//   .vouchClosing: guard status == .closing, closing.credible == false, closing.userID != u,
//                  !disputed.contains(u) → closing = Closing(reason: same, userID: u, at: now, credible: true)
// availableActions(), .closing(byMe: false):
//   plan's list + (.vouchClosing if !credible && !isReporter && credibility(...) == .credible)
```

**Unit tests:**
- `demoteAt`:

  | Close time | Need | Leaves others' maps |
  |---|---|---|
  | 12:00 | food | 13:00 |
  | 23:30 | food | 07:30 |
  | 23:30 | injured | 08:30 |
  | 22:30 | injured | 07:30 |
  | 02:00 | food | 08:00 |
  | 02:00 | babies | 09:00 |
  | 06:59 | food | 08:00 |

- The `credibility` matrix.
- `spend` at the window boundary.
- `look` for each mode.
- `countsAsWaiting`.
- `ContractTests` for the new constants.

**App files**
- `FirestoreReportRepository.swift`:
  - the close transaction reads `users/me`, then writes the report and `users/me` with `credLast: {t: serverTimestamp(), id, w}`;
  - near the window boundary, if permission is denied, retry once with the other window branch;
  - create `users/me` once, in a transaction that checks it does not exist;
  - a live listener on `config/public`.
- `FirestoreReportMapper.swift`: `closingCredible`, written as `NSNull()` on create.
- `DemoReportRepository.swift`.
- `MapViewModel.swift`:
  - the mode;
  - a look for each report;
  - `waitingCount` via `countsAsWaiting` (line 81);
  - an observable flag for street-zoom dots;
  - toasts by `CloseCredibility`;
  - the duplicate check also looks at hidden closings.
- `ReportMapView.swift`: `displayPriority` in `apply()`.
- `MarkerPin.swift`: "?" badge in the walking-badge slot, the pale variant, and the dot.
- `ReportCard.swift`, `LegendSheet.swift`, `ReportPanel.swift`, and a new `WatchedReports.swift`. A7 must also store IDs of reports this device **claimed**, and record per report that the device answered.

**Firebase test files:** `prototype/firebase-kurulum.html` (copy of the rules), `helpers.ts`, `contract.test.ts`.

**Rules tests**
- A budget-backed close is accepted with an aged users doc and a matching `credLast`.
- It is rejected in each of these cases:
  - no users doc;
  - a 23 h old account (not the reporter);
  - `credLast` naming another report;
  - an old `t`;
  - `w=1` on a serious need;
  - the 9th point;
  - two reports with one spend in one batch;
  - `disputed.size()==2`.
- The reporter's close on a 1 h old account is accepted.
- Window branches: a reset before 24 h is rejected, and the same-window branch after 24 h is rejected.
- users doc: a create with a non-server `createdAt` is rejected, and so are an update touching `createdAt`, a delete, and a list.
- `closingCredible` is frozen except for objection/undo (which null it) and vouch.
- Vouch is accepted for an aged non-closer and rejected on an already-credible close, for the closer, and for a disputed uid.
- Regression: a non-reporter confirmer cannot move a non-reporter's closing to `closed`.
- Invariant: for `seenBy [ALICE, CARA]`, BOB with no users doc can never produce `closingCredible == true`.

---

## 5. Turkish UX strings

**Sahibe kısa cevap:** "Evet, planın ilk hâlinde öyle olurdu: işareti koyan geri dönmezse çözülen hayvan 10–70 saat haritada kalırdı. Yeni hâlinde, uygulaması en az bir günlük olan gönüllü 'Çözüldü' dediğinde işaret mama ve 'Diğer'de 1, diğerlerinde 2 gündüz saati sonra herkesin haritasından kalkar. Gece yarısıyla sabah 7 arası sayılmaz. Her telefonun günlük hakkı sınırlı, o yüzden kimse haritayı toptan boşaltamaz. İşaret süresi dolana kadar silinmez; hayvanı gören biri 'Hâlâ yardım gerekiyor' derse geri gelir."

**Kapatan kişiye bildirim** (düğme: [Geri al], 10 dk):
- Kanıtlı, gündüz: "Teşekkürler! Yardımın kaydedildi. İşaret yaklaşık 1 saat sonra başkalarının haritasından da kalkacak." (ağır ihtiyaçlarda: "yaklaşık 2 saat sonra")
- Kanıtlı, gece: "Teşekkürler! Yardımın kaydedildi. İşaret saat 08.00 civarında başkalarının haritasından da kalkacak." (saat hesaplanır)
- Uygulamanın ilk günü: "Teşekkürler! Yardımın kaydedildi. Uygulamanın ilk gününde 'Çözüldü' başkalarına 'doğrulanmadı' olarak görünür; işareti koyan onaylayınca kalkar."
- Hak doldu: "Teşekkürler! Son 24 saatte çok işaret kapattın; bu işaret, koyan onaylayana kadar 'doğrulanmadı' olarak görünecek."
- İtirazlı işaret: "Teşekkürler! Bu işarete daha önce itiraz edildiği için 'doğrulanmadı' olarak görünecek."
- Mod `label`: "Teşekkürler! Yardımın kaydedildi. İşaret 'Çözüldü dendi' olarak görünecek; işareti koyan onaylayınca ya da süresi dolunca kalkacak."

**Kart**
- "?" işaret (sayılır):
  - Durum satırı: "Çözüldü dendi · 20 dk önce · doğrulanmadı"
  - "Doğrulanmadığı için hâlâ yardım bekleyenler arasında sayılıyor. Gidip bakarsan durumu buradan bildir."
- Soluk işaret (kalkmadan önce):
  - Durum satırı: "Çözüldü dendi · 20 dk önce"
  - "Haritadan kalkış: 14.20" / "Haritadan kalkış: yarın 08.00"
- Gri nokta (kalktıktan sonra):
  - Durum satırı: "Çözüldü dendi · 3 sa önce · haritadan kalktı"
  - "Hayvanı şimdi gördüysen ve hâlâ yardıma ihtiyacı varsa bildir."
- Olgu satırları (plandan):
  - "İşareti koyan çözüldü dedi."
  - "İlgilenen kişi 40 dk sonra çözüldü dedi."
  - "İlgilenmeden çözüldü dendi."
  - "3 kişi artık yok dedi."
  - Doğrulamadan sonra: "Başka bir gönüllü de doğruladı."
- Düğmeler:
  - Herkes: [Hâlâ yardım gerekiyor]
  - İşareti koyan: [Evet, çözüldü]
  - "?" işarette uygun kişiler: [Doğru, çözülmüş] / [Doğru, artık yok]
- Doğrulama onayı:
  - Soru: "Hayvanın yardım aldığını ya da artık orada olmadığını kendin gördün mü?"
  - Düğmeler: [Evet, gördüm] [Vazgeç]
  - Bildirim: "Teşekkürler! İşaret yaklaşık 1 saat sonra haritadan kalkacak."
- İtiraz (plandan):
  - Onay: "Hayvan hâlâ yardım bekliyor mu? Bunu yalnızca hayvanı şimdi gördüysen söyle."
  - Bildirim: "Teşekkürler, işaret yeniden yardım bekliyor."

**Takip sorusu (A7, uygulama açılınca)**
- İşareti koyana: "Koyduğun Yaralı kedi işareti için 20 dk önce 'Çözüldü' dendi. Doğru mu? (Haritadan kalkış: 14.20)" [Evet, çözüldü] [Hayır, hâlâ yardım gerekiyor] [Bilmiyorum]. Varsayılan: Bilmiyorum.
- Görenlere: "Gördüğün Yaralı kedi için 'Çözüldü' dendi. Hâlâ yardım gerekiyor mu?" [Hâlâ yardım gerekiyor] [Bilmiyorum]
- Aynı yerde "Hayvan gördüm" (40 m, aynı tür): "Burada 2 saat önce bir kedi için 'Çözüldü' dendi. Aynı hayvan mı, hâlâ yardım gerekiyor mu?" [Evet, hâlâ yardım gerekiyor] [Hayır, başka bir hayvan]

**Lejant**
- "? rozetli işaret: Biri 'Çözüldü' dedi ama doğrulanmadı. Hâlâ yardım bekleyenlerden sayılır."
- "Soluk işaret: 'Çözüldü' dendi, kısa süre sonra haritadan kalkacak. Acil, yaralı, yavru, veteriner ve barınak işaretleri solmaz."
- "Gri nokta (yakınlaşınca): 'Çözüldü' denip haritadan kalkan işaret. Hayvan hâlâ oradaysa dokunup bildir."
- "Gece yarısından sabah 7'ye kadar bu süre işlemez."

**"Nasıl çalışır?" 3. adım:** "Yardım edince 'Çözüldü' de. İşaret senin haritandan hemen, başkalarınınkinden kısa süre sonra kalkar."

**Erişilebilirlik değerleri:** "Çözüldü dendi, doğrulanmadı" / "Çözüldü dendi, birazdan kalkacak" / "Çözüldü dendi, haritadan kalktı"

**Üst çip:** metin aynı kalır ("N hayvan yardım bekliyor"). "?" işaretler sayıya dahildir.

---

## 6. What is still not solved, and why that is acceptable

1. **Budgeted hiding.**
   - One aged phone can hide 4 serious or 8 light reports a day. Three phones can hide 12 or 24.
   - Across a city that is small. Aimed at a hostile neighbour's few streets, which get a few reports a day, it can suppress them for most of each report's life (up to about 70 h for babies or shelter).
   - Acceptable because:
     - it is bounded;
     - it is never final;
     - the reporter and people who confirmed the animal still see the pin and are asked about it;
     - the street dot and the 40 m "Hayvan gördüm" match both lead to an objection;
     - the owner can filter `closingCredible == true` by `closingBy` in the console.
   - Real fixes:
     - C1 push to the reporter and confirmers when a report enters `closing`;
     - C4 reputation (throttle uids whose closes get overturned).
2. **REST scripts before B1** get unlimited aged uids. That is why `demote` for the public is a launch blocker tied to B1. With `label`, the app is no worse than the plan.
3. **Token-replay farms after B1.** Aged uids driven by App Check tokens replayed from a jailbroken device give about 1,900–3,800 points per IP per day.
   - This residual was already accepted in the plan.
   - Mitigations: the switch (restores everything at once, because nothing is final), moderation filters, B3 bans.
   - It is really closed only by C3 (identities created through Functions, device bits).
4. **Report capture with 2 phones** (plan residual, unchanged): the reporter proposes and an accomplice among the confirmers says "Evet". B3's proposal budget limits it; C1 push helps the other confirmers notice.
5. **Legit clutter that remains.**

   | Case | What happens |
   |---|---|
   | Rescues in a volunteer's first 24 h (unless they reported the animal) | "?" pin, counted, until expiry, the reporter's "Evet" or another volunteer's "Doğru" |
   | A 5th serious rescue in 24 h | Same as above |
   | Reports with 2 objections | Same as above |
   | Rescues after about 22:00–23:00 | Leave others' maps at 07:30–09:00 |
   | The reporter and confirmers | Keep seeing the pin until they answer |
   | Street-zoom grey dots | Stay until expiry |

   - The first-24-h case is worst on public launch day. Start the users doc a day before, for TestFlight.
   - The optional "Doğru, çözülmüş" is the cheap way to clear the "?" backlog.
   - The share of real rescues that stay "?" is not known. Measure `closingCredible == false` vs `true` on TestFlight before tuning.
6. **Reads.** Hidden closings stay in map queries until expiry (at most 72 h, capped at 7 days).
   - This is the price of being able to undo them.
   - Once push exists (Tier C), a rules-level finalize for budget-backed closings after about 24 h (the lifetime-cap idea) becomes safe and cuts these reads.
7. **Each viewer sees a slightly different map.** The reporter and confirmers see pins that others do not. Screenshots and support conversations will differ.
8. **Assumptions to re-check.**
   - "One uid per phone" holds only while there is no sign-out, account switching or Sign in with Apple.
   - Turkey stays on fixed UTC+3.
   - Rules cannot check presence, because GPS is supplied by the client.
9. **Griefing in the pro-animal direction** (plan residual). Hostile objections, or reaching 2 objections on a report, keep real rescues on the map as "?" until expiry. It costs volunteers wasted trips, not animals. B3's objection budget limits it.
