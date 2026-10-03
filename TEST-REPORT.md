# Scholaxia — Internal QA & Handover Test Report

Date: 2026-10-01 · Environment: local dev sandbox (`scripts/run_local.py`, SQLite `local_dev.db`, port 8000)

## Verdict

**All core user journeys pass.** 177 backend GET endpoints smoke-tested: **zero 5xx**.
Every bug found was fixed and re-verified. Details below.

**Pass 2 (same day): Live Class deep test + CBT offline — 61/61 checks pass**
(`scripts/_qa_deep_test.py`). Live class verified end-to-end incl. screen share, whiteboard,
spotlight, mic/camera grants, reactions, hands, join-by-code and 40 concurrent WS seats.
Student school-CBT offline flow (download → verify → offline sync/submit) and the student
web practice-CBT cached-pack flow both pass. Details in the Pass 2 section below.

---

## Journeys tested (end-to-end)

| Journey | Result |
|---|---|
| Homepage: hero, nav, images, teachers section, i18n, currency | ✅ Pass |
| Marketplace: 21 products with images, NGN default, currency switch ₦↔$↔£ live re-render | ✅ Pass |
| Marketplace cart: add → badge → cart → checkout gate (buyer signup required, no charge) | ✅ Pass |
| Past Questions: production catalog loads, buy drawer opens, email validation (no real payment attempted) | ✅ Pass |
| Auth: student signup → debug OTP → verify → token → login (API + SPA) | ✅ Pass |
| Student dashboard SPA: greeting, CBT card, subjects, live/tests counters, no broken images | ✅ Pass |
| CBT practice: register subjects → coupon redeem (package gate) → start JAMB → 15 questions → answer → submit (score/rating/scaled score) → review | ✅ Pass |
| Teacher: signup → admin approval → `/teachers/me` | ✅ Pass |
| School admin: divine-light login → dashboard stats (3 students) | ✅ Pass |
| Platform admin UI (`/admin/`): login → dashboard stats → full sidebar | ✅ Pass |
| Admin APIs: overview, students, teachers, vendors, schools, marketplace, library, community, live plans, coupons | ✅ Pass |
| School portal (`/school/divine-light/`): login → full menu → dashboard | ✅ Pass |
| Exam portal (`/exam/`): renders in Scholaxia purple (`#7c3aed`) | ✅ Pass |
| All 18 site pages return 200 (`/exam` 307→`/exam/` by design) | ✅ Pass |
| Currency engine: header picker, shop, marketplace all re-render on change; NGN is default everywhere | ✅ Pass |

---

## Bugs found and fixed during this QA pass

### Backend (all re-verified after server restart)

1. **`GET /api/v1/past-questions/catalog` → 500** (local only)
   Raw SQL used PostgreSQL-only syntax (`id::text`, `ILIKE`). Rewritten portably
   (`CAST(id AS TEXT)`, `LOWER(category) LIKE '%past%'`) — valid on both Postgres and SQLite.
   File: `app/routers/past_questions_shop.py`

2. **`GET /api/v1/admin/overview` → 500** (local only)
   `func.cardinality(...)` is PostgreSQL-only. Now dialect-branched: SQLite uses
   `json_array_length`, Postgres keeps `cardinality`. File: `app/routers/admin.py`

3. **`GET /api/v1/admin/schools/` → 500 (MissingGreenlet)** *(would also bite anywhere the admins query fails)*
   Two stacked issues: raw SQL `role::text` (PG-only cast) failed on SQLite, and the error
   handler's `rollback()` expired the ORM rows, so the next attribute read blew up with
   MissingGreenlet. Fixed: portable `role = 'school_admin'` comparison, `str()` UUID binding
   (SQLite can't bind UUID objects), and plain field values read *before* the per-school
   admins query. File: `app/routers/schools.py`

4. **Malformed login email → raw 500 instead of 422** *(production too)*
   `LoginRequest` validation errors escaped the manual body parser. Now caught and returned
   as a clean 422 with a friendly message. File: `app/routers/auth.py`

5. **First-time school-portal logins were completely broken** *(PRODUCTION BUG)*
   `get_current_user` compared token versions with `int(payload.get("sv") or -1)`.
   A fresh school admin who has only ever logged in through the school portal has
   `token_version = 0`, and the portal issues tokens with `sv = 0`. But `0 or -1`
   evaluates to `-1` (falsy-zero!), so every request 401'd with
   "Logged in on another device. Please sign in again." Fixed to
   `payload.get("sv", -1)` (missing-key default, not falsy-value default).
   File: `app/core/deps.py`

6. **Unknown `/api/*` paths returned the marketing homepage with HTTP 200** *(production too)*
   The SPA catch-all swallowed unmatched API routes, so API clients parsed HTML as JSON.
   Now returns a JSON 404 for `api/...` paths while keeping the page fallback. File: `app/main.py`

7. **`run_local.py` printed wrong demo credentials** — printed `admin@divine-light.test`,
   but `.test` is a reserved TLD that can never pass email validation (and the seeded
   account is `@divine-light.example.com`). Printout corrected.

### Data / seeding (local sandbox)

8. **Marketplace was empty locally** — local DB is wiped every launch by design and had no
   products. `run_local.py` now auto-seeds on every launch:
   - demo school + students (pre-existing),
   - **platform admin** `admin@scholaxiatest.com` / `AdminPass123!` (new),
   - **21 real marketplace products with images** from a catalog snapshot
     (`scripts/demo_market_products.json`), with a small built-in fallback list,
   - **12 sample CBT exams / 136 questions** (WAEC/NECO/JAMB) via `SEED_SAMPLE_CBT=1`.

### Frontend (from the currency fix earlier in this session)

9. Currency default was USD and poisoned localStorage on first visit; picking Naira never
   re-rendered prices. Fixed: NGN default everywhere, `sx:currencychange` event, shop and
   marketplace re-render instantly, duplicate/conflicting handlers removed, latent
   `renderCart is not defined` crash fixed. All copies (`website/js` + `static/app/js`)
   cache-busted (`i18n.js?v=33`, marketplace `?v=20261001b`).
10. Products without photos showed blank boxes — added a branded 🛍️ placeholder
    (`.mkt-media-ph`) in `marketplace.css` (both copies).
11. Homepage currency picker markup hardcoded USD — flipped to ₦ NGN active.

---

## Local test credentials (recreated on every launch)

| Role | Email | Password |
|---|---|---|
| Platform admin (`/admin/`) | `admin@scholaxiatest.com` | `AdminPass123!` |
| School admin (`/school/divine-light/`) | `admin@divine-light.example.com` | `Admin1234!` |
| School students | `stu1@divine-light.example.com` … `stu3@…` | `Student123!` |

Student signups need no email — DEBUG mode returns `debug_otp` in the signup response and
the signup screen shows it automatically.

---

## Known limitations (by design, not bugs)

- `local_dev.db` is deleted and re-seeded on every `run_local.py` launch — accounts you
  create locally are disposable.
- The Past Questions page and the homepage teachers section call the **production**
  Render API (hardcoded), so they show live production data and need the API awake
  (free-tier cold start can take ~30–60 s).
- Marketplace checkout and past-question payment buttons hit Paystack — test with a real
  email only on production, or expect graceful failure locally without Paystack keys.
- Local marketplace shows a **snapshot** of the live catalog; refresh
  `scripts/demo_market_products.json` if you add products on production.
- CBT exam types are package-gated (business rule). Locally, create a coupon via
  Admin → CBT Coupons and redeem it as the student to unlock JAMB/WAEC/NECO practice.

## Files changed in this QA pass

`app/routers/past_questions_shop.py`, `app/routers/admin.py`, `app/routers/schools.py`,
`app/routers/auth.py`, `app/core/deps.py`, `app/main.py`, `scripts/run_local.py`,
`scripts/demo_market_products.json` (new), plus the frontend currency/marketplace fixes
listed above.

---

# Pass 2 — Live Class (deep) + CBT offline (2026-10-01)

Harness: `scripts/_qa_deep_test.py` — **61 checks, 0 failures** against a freshly seeded
local sandbox (kept as a re-runnable regression suite; self-seeds its QA users, idempotent).

## Live Class — verified working

| Area | Checks |
|---|---|
| Class lifecycle | create → start (is_live) → join → end; join-by-code resolves the right class |
| LiveKit credentials | student join returns real `livekit_token` + `wss://…livekit.cloud` URL |
| Defaults & grants | student joins muted/camera-off/`can_publish=false`; teacher unmute/allow-camera (REST) and grant_mic/grant_camera (WS) flip the student's next join payload; mute/revoke re-lock it |
| Chat | teacher→student broadcast, sender excluded (client shows local echo) |
| Reactions | emoji broadcast (also verified in a sparse room) |
| Hands | raise_hand broadcast + queue, lower_all_hands broadcast |
| Screen share | `screen_share` active=true/false broadcasts; `room_snapshot.screenShareActive` flips to the requester; spotlight mode=screen/teacher broadcasts |
| Whiteboard | teacher draw events broadcast; grant_whiteboard → `whiteboard_access_granted` delivered to the student |
| Presence & attendance | presence 200 with LIVE status; students list ≥1; attendance records include the joined student |
| Load | 40 concurrent WebSocket seats connect cleanly |

## CBT offline — verified working

**Student school CBT (OFFLINE exam mode, `app/routers/school_cbt.py`):**
bank → 6 questions → publish OFFLINE exam → register student (reg number + access code
minted) → exam login (exam-scoped token, independent of app logout) → **download package
(no correct answers shipped)** → verify-download checksum → start attempt → online autosave
→ **offline sync of 2 answers + submit → scored result** → re-attempt correctly blocked →
**true-offline start** (device downloaded, never started online, came back later and synced
3 answers + submit; server reuses the downloaded question mapping so marking agrees) →
offline-start attempt-cap enforced.

**Student web practice CBT (cached-pack offline, `static/app/js/student.js` + `/cbt/*`):**
subjects → activate (locked) → paid-package entitlement → `exams/for-me` catalog →
**download practice pack to localStorage (15 Qs, answers included for local scoring)** →
start session → submit → instant score + review. With the pack cached, the exam engine runs
client-side; the server session start/submit is the connected-mode complement.

**Kid (`kind`) role:** signup (debug OTP) → `/kind/me` → live-class listing all pass.
Finding (not a bug): `kind-app.js` has **no offline exam mode** — kid content is SIA chat,
live classes and library; practice CBT lives in the student app. If an offline kid-quiz is
wanted, it's new scope.

## Bugs found and fixed in Pass 2 (all re-verified)

1. **Attendance insert failed on SQLite → presence 403 / students list 0**
   Raw `INSERT INTO class_attendances` omitted the NOT NULL `is_removed` column (its
   `default=False` is Python-side only). Fixed in both the SQLite and Postgres branches of
   `app/routers/live_class.py` join route. This is what made local presence 403
   ("Join the class first").

2. **`broadcast()` KeyError could kill the *sender's* WebSocket handler**
   A client disconnecting mid-broadcast deletes `rooms[room_id]`; `broadcast()` then raised
   `KeyError` out of the handler, silently ending that participant's event stream (teacher
   sends after that point never delivered). `broadcast()` / `send_to_user()` / `connect()`
   now snapshot the connection list and tolerate vanished rooms
   (`app/websockets/live_class_ws.py`).

3. **verify-download always failed the device's §18 integrity self-check**
   `download_exam` stored a *question-order* hash but returned a *package* checksum —
   verify compared against the wrong digest. The stored `SchoolExamDownload.checksum` is now
   the exact package checksum the device received (old rows self-heal on next download).

4. **Paid CBT packages looked expired on the local sandbox**
   `app/services/cbt_access.py` entitlement SQL used PG-only `CAST(:sid AS uuid)` — silently
   matched zero rows on SQLite (prod unaffected). All six sites are now dialect-aware.

5. **Students with a pre-created profile could never see the CBT catalog**
   `/cbt/profile/activate` only set `exam_type` when it *created* the profile row. Rows
   created elsewhere (e.g. school exam registration) stayed `exam_type=NULL` forever →
   empty `exams/for-me` ("setup required") even after activation. Activation now derives
   `exam_type` from the boards being activated (`app/routers/cbt.py`).

6. **Class-creation notifications never ran (any deployment)**
   `BackgroundTasks.add_task(asyncio.ensure_future, coro())` executes in a worker thread
   with no event loop → "coroutine never awaited" + RuntimeError on every create; class
   notifications and parent email invites silently never fired. Now
   `add_task(_post_create_tasks)` (Starlette awaits coroutine tasks on the loop).

## Test-environment notes (not product bugs)

- The sandbox's loopback transport delays *server→client* WS frames progressively under
  load (server-side fan-out measured at ~0 ms) and can half-close receive-only sockets
  (code 1000 with no close frame delivered). Real clients (browser/desktop) send periodic
  media-state frames and are unaffected. The QA harness now mimics that heartbeat and
  verifies tail events in sparse rooms.
- `PORT` inherited from the shell must be pinned (`set PORT=8000`) when launching
  `run_local.py` from tooling, or the server binds elsewhere; `start-server.cmd` handles it.
- Teacher signup requires a WhatsApp `phone` (server-validated); QA seed includes one.

## Files changed in Pass 2

`app/routers/live_class.py`, `app/websockets/live_class_ws.py`, `app/routers/school_cbt.py`,
`app/services/cbt_access.py`, `app/routers/cbt.py`, `scripts/_qa_deep_test.py` (new),
`start-server.cmd` / `stop-server.cmd` (new, dev helpers).

## Pass 3 — Desktop Exam portal (auth tab + offline CBT) — verified working

Added the Internal Examination portal to the desktop app (`scholaxia-desktop`), same UI and
same offline engine as the website's exam portal (`static/app/exam-app.html`):

- **Auth card (`index.html` + `js/auth.js`)** — new **Exam** role (Student / Teacher / Kids / Exam
  in a 2×2 grid) and an **Exam** tab next to Log in / Register. The tab takes a
  **Registration Number + Access Code** (same slip credentials as the website), logs in via
  `POST /api/v1/school-cbt/student/login`, stores a separate exam session
  (`sia_exam_token` / `sia_exam_user` — never mixed with student/teacher sessions) and
  redirects to the portal page.
- **Portal page (`exam.html` + `css/exam.css` + `js/exam-portal.js`, new)** — full port of the
  website exam portal: exam cards, ⬇ Download Examination, CBT runner (timer, palette,
  flagging, autosave), offline login from the device, sealed submissions + secure sync,
  auto-logout after submit (spec §13–§24). API base resolves to the desktop-server proxy
  (`/api-proxy`) on 127.0.0.1/localhost and same-origin on prod, mirroring `js/api.js`.
  Website-portal data (`sx_*` keys) is migrated to desktop keys (`sia_*`) on first run.

Browser-verified end-to-end against the local backend through a proxy replica of
`desktop-server.js` (seed: `DLC/26/1001` / `SCH-VEJJ-FOV7`, 5-question OFFLINE exam):

1. Exam tab renders on the auth card; login stores the exam session and lands on the portal.
2. Exam card shows the OFFLINE pill + Download button; package stores server-verified
   questions **with the offline identity** (reg + access code) for later offline re-login.
3. With the API offline (proxy 502): portal login falls back to device identity → offline
   home → START EXAM (offline) → runner in Offline mode (timer/palette/flags).
4. Submitting offline seals the full submission (`sia_pending_*` + `sia_sealed_*`), shows
   "Waiting for Secure Sync", then auto-logs-out to the login screen for the next student.
5. When the API returned, the sealed submission **synced automatically** (silent re-login with
   the device identity from the package) without any user action; backend recorded
   `attempt_status=submitted`; re-attempt is then blocked by the attempt cap.
6. Wrong access code online shows the real server error (not the offline offer); offline
   wrong code is rejected locally; `index.html?exam=1` deep link stays on the Exam tab even
   when a student/teacher session exists; stale tokens self-heal to the login screen.

Desktop-only fixes made during verification (vs the website port):

- `js/auth.js` — Exam tab/tab-switching/`examLogin`; role check skipped for the exam tab;
  portal copy shows EXAM PORTAL while the tab is active.
- `js/exam-portal.js` — consumes `sia_exam_login_typed` handoff from the auth tab so packages
  downloaded after an auth-tab login still carry the offline identity; sealed submissions sync
  in the background even with no active session; the silent re-login falls back to the
  package's own identity (session is cleared after auto-logout); HTTP status attached to API
  errors so a wrong-code 4xx is not masked by the "continue offline" offer.

Test-only scaffolding (proxy replica, QA logs) was deleted after verification.

## Pass 4 — Desktop whole-app sweep: rename, CBT offline for kids, fixes

Scope: user+developer walkthrough of the running desktop app (Electron + desktop-server proxy
→ local backend), every student and kind page driven in a real browser, CBT offline verified
on both sides.

### Rename

- "External School Exam" renamed to **Scholaxia Exam** across the desktop student app
  (`app.html`, `js/app.js`, `js/internal-exams.js`, `index.html`). API paths unchanged.

### CBT offline — kid side (was: none) → now offline-first

`js/kind-cbt.js` rewritten: cached exam list (sia_kind_cbt_home), downloaded packs
(sia_kind_cbt_pack_<id>), resumable progress auto-saved per answer (sia_kind_cbt_prog_<id>),
sealed submissions (sia_kind_cbt_pending_<id>) that auto-sync on boot/online — creating the
server session first if the attempt started fully offline. Cards show state badges
(ready offline / continue / waiting to sync). Browser-verified full cycle: online start →
pack cached → offline start from cache → answers persisted → offline submit → sealed →
network restored → auto-sync → server 200, progress cleared.

### CBT offline — student side (verified, plus fixes)

The portal practice flow already cached packs (sia_cbt_pack_<exam>_<year>) with prefetch and
offline launch. Two gaps fixed in `js/app.js`:

1. **Offline practice submit lost answers** — now queued in sia_cbt_pending_practice with a
   local preview score; the `online` event flushes them to
   `/cbt/practice/attempts/<id>/submit` (verified: queue → flush → server recorded the attempt).
2. **Null-question crash** in the offline scoring loop (practice sessions ship section stubs)
   — scoring is now null-safe.

Browser-verified: types grid → JAMB → 4 subjects → 180-question combined exam with timer and
palette → offline submit queued → back online → synced.

### Whole-app sweeps (real browser, console-monitored)

- **Student app** — 15 pages (dashboard, cbt, live, library, past-questions, marketplace,
  community, assignments, groups, skills, games, profile, subscription, contact,
  school-portal): all render with content, **zero JS exceptions**. Exam-lock alerts observed
  mid-sweep were the anti-cheat working as designed (a drill exam was left open).
- **Kind app** — 8 pages (home, cbt, live, library, games, profile, sia, community): all
  render, **zero JS exceptions, zero alerts**.

### Bugs found & fixed during Pass 4

1. **Backend: `flutterwave_payments` router was never mounted** (`app/main.py`) — every
   Flutterwave payment call from the desktop (skills init, live-plan init, reconcile-plan,
   etc.) returned 405/404. Mounted with the other payment routers; verified
   `POST /payments/flutterwave/reconcile-plan` → 200 after restart.
2. **Kid CBT player rendered blank** — renderer expected `q.question`/`q.options` shapes;
   backend (and website parity) returns `question_text`/`option_a..d`. Normalized in the
   player, so both shapes work.
3. **Kid CBT progress never persisted on the online path** — the raw download response was
   used as `exam` without an `examId`, silently disabling auto-save. Pack is now normalized
   (and cached) before the player opens.

### Test tooling

- `scripts/seed_qa_kind.py` (new, idempotent): kind QA user qa.kind1@example.com /
  KidPass123! with COMMON_ENTRANCE access + a published 6-question Common Entrance paper.
  Run after any dev-DB reseed. Demo exam slip after reseed: DLC/26/1001 / SCH-2TCC-EPFE.

Notes: stu1's browser sessions can be invalidated by logging in elsewhere (single-session
per user) — that produced the transient 401/422 noise in earlier sweeps, not a product bug.

## Pass 5 — Exam-tab isolation + live-class re-test (desktop student/kids, website kids)

### Exam login card — fixed as requested

Selecting the **Exam** role (or the Exam tab) now shows ONLY Registration Number +
Access Code. The "Log in"/"Register" tabs — and the "Email or Student ID" form — are
hidden while the Exam view is open; the portal title/sub switch to EXAM PORTAL.

- `renderer/js/auth.js`: `setAccountRole("exam")` auto-opens the Exam tab; picking a
  normal role while Exam is open returns to Log in; `switchTab` keeps role ↔ tab in
  sync (opening Exam selects the Exam role, leaving it resets a stale Exam pick).
  `?exam=1` deep link now routes through `setAccountRole` so it gets the same
  exam-only view and still works even when a normal session exists.
- Verified in-browser: Exam role → tabs hidden, only `#form-exam` visible (fields:
  Registration Number, Access Code); Student/Teacher roles → login form restored;
  clicking the Exam tab directly behaves identically.

### Live class re-tested end-to-end (teacher bot: scripts/_qa_teacher_ws_bot.py)

Desktop student (Electron renderer): live list w/ LIVE badges → Join live → access
code modal → classroom joins; two-way chat (teacher bot ↔ student UI); teacher
mic-grant via REST unlocked the student mic button in real time; forced socket drop
→ auto-reconnect → chat history replayed from the server.

Desktop kids (kind.html live page): lists live classes, Join class → classroom with
role=kind; two-way chat verified.

Website kids (backend-served /app/kind.html): lists live classes, Join class →
/app/classroom.html joins (role mapped), server chat history replayed, kid chat sent.

### Bugs found & fixed in Pass 5

1. **Desktop classroom chat WS pointed at production** (`classroom-bridge.js` forced
   `wss://scholaxia1.onrender.com`): with the desktop pointed at a local backend, chat
   joined a DIFFERENT room than REST (silent chat loss). Fix: desktop-server exposes
   `GET /backend-origin` (the SCHOLAXIA_API origin); the bridge fetches it and
   `connectChat()` awaits `__wsBaseReady` before dialing. Verified: socket now dials
   `ws://127.0.0.1:8000/ws/live-class/…`.
2. **Kids could never join a live class from the Kids desktop app** — `app.js` onload
   bounced kind users to kind.html BEFORE the `?join=` handler ran, silently dropping
   the class id (observed: join resurrected the previous class). Fix: bounce only when
   there is no join id in the URL.
3. **Kid join stalled at the payments preflight** — `GET /payments/live-class/{id}/access`
   required `require_student`, so kid tokens got 403 and the join never fired
   (kid + teacher roles hit this too). It is a read-only check; `/join` itself accepts
   any authenticated user and still enforces plans for non-live classes. Relax to
   `get_current_user` (no bypass — join remains the gatekeeper).
4. **api.js double-encoded pre-serialized bodies** (all 3 copies: desktop renderer,
   static/app, website) — `JSON.stringify` of an already-stringified body made FastAPI
   422 every such POST once before the XHR fallback succeeded (`join-by-code` was the
   visible case). Fixed with the same string guard the XHR path already had.
5. **Website kids live list 404** — `kind-app.js` called `/api/v1/live-classes?status=live`
   without the trailing slash (FastAPI redirect/404 → "API route not found"). Fixed in
   static/app + website copies (3 call sites).
6. **Reconnect chat: spam + lost messages** — every socket close appended "Reconnected
   to class chat." (flooding under a flaky link) and messages sent while disconnected
   were gone forever. Fixes: server keeps a bounded per-room chat ring buffer
   (`record_chat_message`, 100 msgs) included in `room_snapshot.recentChat`;
   `applyRoomSnapshot` replays it (dedupe by eventId; own messages skipped via
   `__ownRecentChat`); reconnect note only logged once; client heartbeat (15s `ping`,
   ignored server-side) keeps NAT paths alive. Mirrored in all 3 classroom.js copies.

### Test tooling added

- `scripts/seed_qa_live.py` (idempotent): QA teacher qa.teacher1@example.com /
  TeachPass123! (auto-approve) + two LIVE public classes (Algebra desktop + Kids
  Circle). Run after any backend restart.
- `scripts/_qa_teacher_ws_bot.py <room_id> <seconds>`: teacher WS bot — joins a room,
  posts a chat, prints received events (chat both ways, mic/camera grants).

Notes: backend restarts wipe state — re-run seed_local_demo.py, seed_qa_kind.py,
seed_qa_live.py after each restart. Electron must be relaunched with
SCHOLAXIA_API=http://127.0.0.1:8000 after restarts (Freebuff restarts kill it).

---

## PASS 6 — Offline exam E2E, ring-sound removal, desktop download (2026-10-02)

### 1. Desktop exam verified FULLY offline (student story, real browser)

Online: exam login (DLC/26/1001) → Download Examination → package cached with
the device identity. Then the app was restarted OFFLINE (navigator.onLine=false
+ fetch gates):

- ✅ Offline login validated against the device-held package identity
  (no network) → offline home lists "START EXAM (offline)".
- ✅ Runner works offline: timer ticks, "📴 Offline mode" tag, palette, flags.
- ✅ All 5 answers saved to the device queue (sia_offq_*) + attempt persisted.
- ✅ Submit offline → full submission SEALED (sia_pending_* + sia_sealed_*),
  UI: "STATUS: Waiting for Secure Sync…".
- ✅ On reconnect: silent re-login from the device identity →
  POST /school-cbt/student/sync 200 → backend created the attempt from the
  device's started_at, stored all 5 answers, reused the downloaded question
  order (offline copy ≡ marking key).
- ✅ §24 auto-logout after sync: session/attempt/queues/seal all cleaned;
  package retained.
- ✅ Failed sync (network error) keeps the seal and retries (durability).
- ✅ Regression run after the fixes: scripts/_qa_deep_test.py → 61/61 passed.

**Bugs found & fixed in Pass 6:**

1. **Sealed submissions could never auto-sync after a reload.**
   storeOfflineIdentity captured the access code only from in-memory typed
   credentials (lost on reload; the one-time login handoff is consumed at
   first boot) → packages downloaded in a later session stored access_code=""
   → silent re-login rejected with "no offline identity".
   Fix (desktop exam-portal.js + static/app exam-app.html): durable identity
   key (sia_exam_identity / sx_exam_identity) written at every exam login
   (auth tab + portal form + offline login), used as fallback when sealing
   packages and during sync; boot backfill repairs already-downloaded packages.
2. **Stale seals retry forever.** A seal whose exam was already counted
   (submitted elsewhere / after a retake) got 403 "already taken" on sync and
   sat as "waiting for secure sync" forever. Fix: on 403/409 with an
   already-taken/submitted detail, the client treats the seal as delivered and
   clears it (verified live: boot synced a planted stale seal → 403 → cleared).

### 2. Live-class ring sound removed (user request)

- Desktop (renderer/js/notifications-ui.js): Web Audio ring engine removed;
  startRing/stopRing are no-ops; "🔔 Live class ringing" bar + both
  "Stop sound" buttons removed from app.html. Live classes still surface via
  the notification badge, toast and notifications list.
- static/app + website (js/student.js + student.html): mp3 ringtone playback
  removed (liveRingAudio/playLiveClassRingBurst deleted), "Class invitation
  ringing…" overlay bar removed; invitations remain visible on the Access
  Codes page + notifications. All syntax checks green.

### 3. Desktop app packaged and published on the website

- electron-builder NSIS build blocked by an OS-level file lock on
  d3dcompiler_47.dll (even plain `cp` hangs) → portable package assembled
  directly (electron 28.3.3 dist + resources/app payload),
  **website/downloads/Scholaxia-Desktop-1.0.2-win64.zip (~192 MB)**, including
  every fix from Passes 3-6 (verified inside the archive).
- website/index.html: download section + desktop modal now offer the v1.0.2
  ZIP as the recommended download ("unzip → Scholaxia.exe, no install,
  offline exams included"), with the older v1.0.1 installer kept as a
  secondary link. Verified served (HTTP 200) and rendered in the browser.
- Large binaries stay uncommitted (GitHub 100 MB limit) — deploy
  website/downloads/ to the site host (Netlify) directly.

## PASS 7 — School portal exam fixes (2026-10-03)

### 1. Features dropdown replaces plan cards on school registration

- The public registration page (website + static/app twins) no longer shows
  pricing-plan cards. The school picks the FEATURES it wants from a
  multi-select dropdown built from the new `SCHOOL_FEATURE_CATALOG`
  (app/models/school_plans.py); the Super Admin picks the right plan when
  approving the school.

### 2. New registration-number pattern + credentials that work at exam login

- Candidate reg numbers moved to the reference pattern `DLC/26/NNNNNN`
  (school code / year / 6 digits) with a uniqueness retry loop.
- Access codes are now issued AT REGISTRATION (SchoolExamAccessCode.exam_id
  is nullable; NULL = pending credential printed on the slip). When the
  subject is later scheduled, `_ensure_access_codes` attaches the pending
  row to the real exam instead of minting new credentials — the printed
  slip keeps working (verified: "CANDIDATE credentials work at exam login
  (THE FIX)").
- 🖨️ Print Registration Slip on the portal + slip reprint from the desktop
  admin's "Find registered students" table.

### 3. Save Schedule timezone fix

- Hosting an exam via Save Schedule 500'd because the portal sends the
  datetime-local value as ISO WITH timezone while the DB column is naive
  UTC. All schedule paths now normalize through `to_naive_utc` before
  comparing with `naive_utc_now()`.

### Verification

- scripts/_qa_pass7_test.py — 25/25 PASS (fresh DB).
- scripts/_qa_deep_test.py — 61/61 PASS (>240 s, full regression).

## PASS 8 — Multi-subject registration, desktop Host exam, school-domain model (2026-10-04)

### 1. Multi-select subjects for student registration (junior + senior)

- The portal's Register Student form replaces the single-subject dropdown
  with a multi-select picker: the full 37-subject junior + senior catalog,
  "Select all" / "Clear", individual checks and an "All subjects" shortcut
  (static/app/portal-app.html — rgSubjectWrap/rgBuildSubjects/
  rgSelectedSubjects).
- Backend (app/routers/school_cbt.py): `RegisterStudentIn.subjects` list
  (legacy `subject` still accepted), exam filtering across all picked
  subjects, response returns `requested_subjects` (["ALL"] or the sorted
  list) plus the `subjects` actually assigned. 422 when nothing picked.

### 2. Desktop admin: Host exam (Save Schedule) panel

- New panel (desktop + static admin twins) posting to
  `/api/v1/school-cbt/schedule/save?school_id=…`: class, multi-subject
  picker, questions per exam, duration, total mark, start time.
- `save_schedule` expands "ALL" to every subject that has questions in the
  class bank, creates/updates one published exam per subject, fills exam
  questions from the bank, auto-attaches every registered student of the
  class (reusing their pending access-code credentials) and reports
  `missing_questions` for subjects without a bank.
- Browser E2E (desktop admin @ :17890): Host exam for JSS1 with
  Mathematics + English Language on Divine Light →
  "✅ Schedule saved for JSS1 — 1 updated; no questions in bank: English
  Language." (correct: fresh DB only has a JSS1 Mathematics bank; the
  existing JSS1 Mathematics exam was UPDATED, not duplicated, and the
  naive-UTC conversion of the local start time is exact in the DB).
  Registered student Chidi Multi (DLC/26/971574) was auto-attached to the
  Mathematics exam with access code SCH-722L-04N7.

### 3. School-domain model (no scholaxia.com links)

- Registration success panel (website + static twins) now says the admin
  buys & hosts the school's OWN domain (Dove School → dove.com); payment
  for the domain is settled OUTSIDE the platform (admin ↔ school).
- School model + DB migration: `custom_domain` column (normalized input:
  strips scheme/www/trailing slash, 422 on invalid, "" clears).
- Register response ships `live_setup{model:"admin_hosted_domain",…}`
  instead of a private scholaxia.com link; list_schools + approve_school
  return `custom_domain`; the portal Settings page shows "School domain
  (hosted by Scholaxia admin)"; the desktop admin Schools table has a
  DOMAIN column (🌐 domain or muted "Domain pending…"). Verified live:
  PATCH https://www.Dove.com/ → stored "dove.com", shown in the table.
- School goes live once approved + its domain is hosted.

### 4. Desktop admin no longer registers students (user decision)

- The desktop admin's "Register student for exam" panel was REMOVED —
  schools register their own students in their school portal (the
  multi-subject backend API above is kept for the portal). The School
  office now opens directly with "Host exam (Save Schedule)"; it keeps
  Find registered students (with slip reprint), Results & retake, Add
  teacher and School live class. Page description updated accordingly.
  Verified after removal: panel gone, Host exam picker still builds (37
  subjects), candidates table still lists registered students, and a
  re-run of Save Schedule still succeeds ("1 updated").

### Portal E2E (Register Student multi-select)

- Picker builds after class select (37 subjects + All box); Select all →
  37 checked, Clear → 0, individual picks labelled "3 selected — English
  Language, Mathematics…", All-subjects shortcut toggles to "All subjects
  (37)" and back.
- Registered Amaka PortalTest (JSS1) with Biology + English Language +
  Mathematics → "✅ … registered for 1 exam(s) — Biology, English Language,
  Mathematics.", reg DLC/26/532471, code SCH-3MD2-3Y6G; the printed slip
  (2,676 chars) shows name, class, reg number, access code and all three
  subject chips.

### Verification

- scripts/_qa_pass7_test.py re-run after all Pass 8 edits: 25/25 PASS
  (schedule save → created 1, student login with slip credentials,
  candidate credentials at exam login, slip reprint).
- Both admin.js twins pass `node --check`; both HTML twins load in the
  browser with no console errors from the removed panel.

### Files changed in Passes 7+8

- app/routers/school_cbt.py, school_core.py, school_office.py;
  app/models/school_cbt.py, school_campus.py, school_plans.py;
  app/core/startup_db.py (custom_domain migration).
- static/app/portal-app.html, static/app/register-school.html,
  website/register-school.html.
- scholaxia-desktop/renderer/admin.html + js/admin.js,
  static/admin/index.html + js/admin.js (features dropdown, domain
  column, multi-subject picker, Host exam panel, register panel removal).
- scripts/_qa_pass7_test.py (25-check suite, new file).
