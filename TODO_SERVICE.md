# Quests App — Voice Memo to Quest PWA

A personal voice-memo-to-quest system: record a voice memo, transcribe it
automatically, extract priority and category via keyword detection, and
display it in a scrollable list. Installable as a PWA on iPhone Home Screen.

Research and investigation done in `~/Projects/quests-app/`.

---

## 1. What & Why

Open a PWA, hold the record button, speak a quest ("buy groceries", "fix the
kitchen shelf"), release. The server transcribes it, scans for keywords to
assign priority and category, and saves it. The quest appears in the list.
When the app is closed, a Web Push notification tells you a new quest landed.

No external API costs. No LLM for categorisation. Fully self-hosted.

---

## 2. Architecture

```
┌─ Docker Container (single) ──────────────────────────────┐
│  FastAPI (Python 3.13-slim)                              │
│  ├── POST /api/recordings    → transcribe + save         │
│  ├── GET  /api/quests        → list quests (sorted)      │
│  ├── PATCH /api/quests/:id   → update status             │
│  ├── DELETE /api/quests/:id  → delete quest              │
│  ├── GET  /api/events        → SSE stream (foreground)   │
│  ├── POST /api/push/register → Web Push subscription     │
│  ├── POST /api/push/unregister                            │
│  ├── GET  /manifest.json     → PWA manifest              │
│  ├── GET  /sw.js             → Service worker            │
│  └── GET  /                  → index.html (PWA)          │
│                                                           │
│  faster-whisper (base model, int8, CPU)                   │
│  SQLite (on mounted volume)                               │
└───────────────────────────────────────────────────────────┘
     │
     ↓ Port 4020+ (next available, standard homekase pattern)
     │
┌─ PWA (single index.html) ────────────────────────────────┐
│  ┌─────────────────────────────┐                          │
│  │  Quests                     │                          │
│  │─────────────────────────────│                          │
│  │ [swipeable quest items]     │ ← SSE when open          │
│  │  swipe left = cancel        │   Web Push when closed   │
│  │  swipe right = done         │                          │
│  │                             │                          │
│  │  ┌───────────────────────┐  │                          │
│  │  │   Hold to Record      │  │                          │
│  │  └───────────────────────┘  │                          │
│  └─────────────────────────────┘                          │
└───────────────────────────────────────────────────────────┘
```

### Why single container?

Single-user app. No need for separate worker/queue. faster-whisper runs
in-process via Python bindings — no separate Docker image for STT.

---

## 3. Tech Stack

| Layer | Choice | Why |
|-------|--------|-----|
| Server | Python FastAPI | Consistent with assistant agent, async, lightweight |
| DB | SQLite | Single-user, zero-config, file on mounted volume |
| Transcription | `faster-whisper` (base, int8, CPU) | ~1-3s for 30s memo, free, local, no API key |
| Categorisation | Keyword regex matching | No LLM, instant, deterministic |
| Real-time (foreground) | Server-Sent Events (SSE) | Simple, native EventSource API |
| Real-time (background) | Web Push (VAPID) | Only option for "app closed" on iOS |
| Frontend | Single `index.html` + vanilla JS + CSS | No build step, no framework |
| PWA | manifest.json + service worker | Installable, offline shell |

---

## 4. Database Schema

```sql
CREATE TABLE quests (
    id          UUID PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
    title       TEXT NOT NULL,
    description TEXT,
    priority    TEXT NOT NULL DEFAULT 'medium'
                CHECK (priority IN ('high', 'medium', 'low')),
    category    TEXT NOT NULL DEFAULT 'personal'
                CHECK (category IN ('work', 'personal', 'health', 'errands',
                                    'learning', 'social', 'home')),
    status      TEXT NOT NULL DEFAULT 'pending'
                CHECK (status IN ('pending', 'done', 'cancelled')),
    transcript  TEXT,
    created_at  TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at  TEXT NOT NULL DEFAULT (datetime('now')),
    completed_at TEXT
);

CREATE INDEX idx_quests_status ON quests(status);
CREATE INDEX idx_quests_priority ON quests(priority);
CREATE INDEX idx_quests_created_at ON quests(created_at DESC);
```

SQLite `randomblob` for UUID generation (no extension needed).

---

## 5. Keyword Categorisation

No LLM. Scan transcript text for keyword matches.

### Priority detection

```python
PRIORITY_KEYWORDS = {
    "high": ["urgent", "asap", "emergency", "critical", "immediately", "now"],
    "medium": ["important", "need to", "should", "don't forget", "remember"],
}
# First match wins. Default: "medium".
```

### Category detection

```python
CATEGORY_KEYWORDS = {
    "work":    ["meeting", "deadline", "project", "client", "email", "call"],
    "health":  ["doctor", "medicine", "gym", "exercise", "appointment"],
    "errands": ["buy", "pick up", "shop", "groceries", "store"],
    "home":    ["fix", "repair", "clean", "install", "shelf", "door"],
    "learning": ["read", "study", "learn", "course", "book"],
    "social":  ["call", "visit", "dinner", "party", "birthday"],
}
# First match wins. Default: "personal".
```

### Title extraction

Use first N words of transcript (up to first punctuation or 5 words) as
title. Or use a simple heuristic: strip filler words ("um", "uh", "so",
"hey", "okay"), take the first meaningful phrase.

---

## 6. API Endpoints

```
POST   /api/recordings        Upload audio → transcribe → categorise → save
GET    /api/quests             List quests (query: ?status=pending&sort=priority)
GET    /api/quests/:id         Get single quest
PATCH  /api/quests/:id         Update quest (status, priority, etc.)
DELETE /api/quests/:id         Delete quest
GET    /api/events             SSE stream for real-time quest updates
POST   /api/push/register      Register Web Push subscription (VAPID)
POST   /api/push/unregister    Unregister push subscription
GET    /manifest.json          PWA manifest
GET    /sw.js                  Service worker
GET    /                       Serve index.html
GET    /static/*               Static assets (icons, etc.)
```

### POST /api/recordings

Request: `multipart/form-data` with `audio` field (WebM/Opus or MP4/AAC).

Processing pipeline:
1. Receive audio upload
2. Transcribe via faster-whisper (`base`, int8, CPU)
3. Scan transcript for priority keywords
4. Scan transcript for category keywords
5. Extract title from transcript
6. Save quest to SQLite
7. Broadcast via SSE to connected clients
8. Send Web Push to all registered subscriptions
9. Return created quest JSON

---

## 7. iOS PWA Constraints & Workarounds

### Background recording (LOCKING PHONE)

**Not possible.** iOS suspends the PWA tab seconds after locking.
MediaRecorder stops. No workaround exists — it's an OS restriction.

Workaround:
- Show warning if user tries to leave/lock during recording
- Auto-save partial recording on `visibilitychange`
- For 5-30s memos, foreground recording is fine
- Thoroughly clean up tracks on stop (prevent stuck-MediaRecorder bug)

### Notifications when app is closed

**SSE cannot deliver when app is closed** — requires open connection.
Must use Web Push (VAPID) for background notifications.

Hybrid approach:
- **App open (foreground):** SSE for instant real-time updates
- **App closed (background):** Web Push via VAPID + service worker

### iOS Web Push requirements (all mandatory)

1. iOS 16.4+ (March 2023)
2. PWA **must be installed to Home Screen** (no push in regular Safari)
3. `display: "standalone"` in manifest.json
4. HTTPS origin (Tailscale Serve provides this)
5. VAPID key pair (ECDSA P-256) — no Apple Developer account needed
6. Service worker registered at origin root
7. User gesture required for `Notification.requestPermission()`
8. `userVisibleOnly: true` mandatory (no silent push)
9. Apple validates VAPID JWT strictly: `aud` = `https://web.push.apple.com`

### EU caveat

Apple removed standalone PWA support under DMA (iOS 17.4+).
PWAs open as Safari tabs, push notifications don't work in EU.

### MediaRecorder codec detection

- iOS 18.4+: WebM/Opus supported in MediaRecorder
- iOS 14.5-18.3: MP4/AAC fallback (always supported)
- Detect and prefer WebM/Opus, fall back to MP4/AAC

### Known PWA bug

MediaRecorder can get "stuck" in PWA mode if tracks aren't properly
cleaned up. Must thoroughly `stop()` all tracks and release the stream
on every recording end (including errors and visibility changes).

---

## 8. Transcription Details

### faster-whisper configuration

| Setting | Value | Notes |
|---------|-------|-------|
| Model | `base` | 8.1% WER, sub-second for 30s memo |
| Compute type | `int8` | 4x less RAM than float32, ~30-50% faster on CPU |
| Language | `en` | Skip detection overhead (set if English-only) |
| Beam size | `1` | Faster, good enough for short memos |
| RAM | ~500MB | Model + audio buffers |
| Docker size | ~220MB | CPU-only image |

### Why `base` over `small`?

For keyword detection on short sentences, 8.1% WER is sufficient.
"urgent" misspelled as "urgnt" won't break keyword matching if we
use fuzzy matching or character-distance tolerance.

Upgrade path: change one config value to `small` if accuracy is insufficient.

---

## 9. PWA Frontend Design

### Single page layout

```
┌─────────────────────────────┐
│  ⚔ Quests              [⚙] │  ← header with settings icon
│─────────────────────────────│
│                             │
│  ┌───────────────────────┐  │
│  │ 🟡 [HIGH] Buy groceries│  │  ← priority color + badge
│  │    "Need milk, eggs..."│  │  ← truncated description
│  │    2 min ago           │  │  ← relative time
│  └───────────────────────┘  │
│                             │
│  ┌───────────────────────┐  │
│  │ 🟢 [MED] Fix shelf    │  │
│  │    "The kitchen shelf…"│  │
│  │    15 min ago          │  │
│  └───────────────────────┘  │
│                             │
│  ┌───────────────────────┐  │
│  │ ⚪ [LOW] Read book    │  │
│  │    "The one about..."  │  │
│  │    1 hour ago          │  │
│  └───────────────────────┘  │
│                             │
│  ┌───────────────────────┐  │
│  │                       │  │
│  │   🎤 Hold to Record   │  │  ← pinned at bottom
│  │                       │  │
│  └───────────────────────┘  │
└─────────────────────────────┘
```

### Swipe gestures

- **Swipe left** on quest item → Mark as `cancelled`
- **Swipe right** on quest item → Mark as `done`
- Visual feedback: green trail right, red trail left
- Undo toast appears for 5 seconds after action

### Visual design

- Priority colors: high = amber/yellow, medium = green, low = gray
- Pending quests shown by default
- Filter tabs: All | Pending | Done | Cancelled
- Record button: large, circular, pulsing animation while recording

---

## 10. homekase Service Integration

### Files to create/modify

| File | Action | Purpose |
|------|--------|---------|
| `lib/services/quests-app.sh` | **Create** | Installer: `deploy_quests_app()` + `remove_quests_app()` |
| `lib/services/service.sh` | **Modify** | Add `"quests-app:Voice memo quest PWA"` to SERVICES array |
| `services/quests-app/` | **Create** | App source code, Dockerfile, docker-compose.yml |

### deploy_quests_app() follows standard pattern

```bash
deploy_quests_app() {
  require_root
  header "Installing Quests App"

  local PORT DATA_PATH TS URL BIND_ADDR
  PORT="$(port_wizard "quests-app" 1)"
  DATA_PATH="$(ask_input "Quests App data path" "/data/config/quests-app")"
  TS="$(tailscale_serve_setup "${PORT}")"
  URL="$(service_url "${PORT}")"
  BIND_ADDR="$(bind_address "${TS}")"

  write_service_dir "quests-app"
  write_compose_file "quests-app" "services:
  quests-app:
    build: .
    container_name: quests-app
    restart: unless-stopped
    ports:
      - \"\${BIND_ADDR}\${PORT}:8000\"
    volumes:
      - \${DATA_PATH}:/data
    networks:
      - homelab-net
    labels:
      com.homekase.service: quests-app
      com.homekase.port: \"\${PORT}\"
      com.homekase.tailscale: \"\${TS}\"
      com.homekase.backup.type: snapshot
      com.homekase.backup.data: \"\${DATA_PATH}\"
      com.homekase.backup.db-type: sqlite

networks:
  homelab-net:
    external: true"

  write_env_file "quests-app" "PORT=${PORT}
DATA_PATH=${DATA_PATH}
TS=${TS}
URL=${URL}
BIND_ADDR=${BIND_ADDR}"

  mkdir -p "${DATA_PATH}"
  start_service "quests-app"

  config_app_set quests-app installed true
  config_app_set quests-app port "${PORT}"
  config_app_set quests-app data_path "${DATA_PATH}"
  config_app_set quests-app tailscale "${TS}"

  ok "Quests App running on port ${PORT}  →  ${URL}"
}
```

### remove_quests_app() follows standard pattern

```bash
remove_quests_app() {
  require_root
  header "Removing Quests App"
  local port
  port="$(config_app_get quests-app port 2>/dev/null || true)"
  [[ -n "${port}" ]] && tailscale_serve_remove "${port}"
  remove_service_dir "quests-app"
  config_app_remove quests-app
  ok "Quests App removed."
}
```

---

## 11. Project Structure

```
services/quests-app/
├── Dockerfile              # Python 3.13-slim + faster-whisper
├── docker-compose.yml      # Single container, homelab-net
├── pyproject.toml          # fastapi, uvicorn, faster-whisper, pywebpush
├── main.py                 # FastAPI app (all endpoints)
├── db.py                   # SQLite setup + queries
├── transcribe.py           # faster-whisper wrapper
├── categorise.py           # Keyword matching logic
├── push.py                 # Web Push (VAPID) helper
├── static/
│   ├── index.html          # Single-page PWA
│   ├── manifest.json       # PWA manifest
│   ├── sw.js               # Service worker
│   ├── app.js              # Frontend logic (record, list, swipe, SSE, push)
│   ├── style.css           # Styles
│   └── icons/              # PWA icons (192x192, 512x512)
└── quests.db               # SQLite database (created at runtime, in /data)
```

### Dockerfile sketch

```dockerfile
FROM python:3.13-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg libsndfile1 && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY pyproject.toml .
RUN pip install --no-cache-dir .

COPY . .

EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
```

### pyproject.toml dependencies

```
fastapi
uvicorn[standard]
faster-whisper
pywebpush
python-multipart
```

---

## 12. Implementation Phases

### Phase 1 — Foundation (1 day)
- [ ] Scaffold `services/quests-app/` directory
- [ ] FastAPI app with `/api/recordings`, `/api/quests`, `/api/quests/:id`
- [ ] SQLite setup + schema migration
- [ ] faster-whisper integration (transcribe audio → text)
- [ ] Keyword categorisation (transcript → priority + category)
- [ ] Dockerfile + docker-compose.yml
- [ ] Test: upload audio, get quest back

### Phase 2 — PWA Frontend (1.5 days)
- [ ] Single `index.html` with quest list + record button
- [ ] MediaRecorder with iOS codec detection (WebM → MP4 fallback)
- [ ] Audio upload to server
- [ ] Quest list rendering (sorted by priority, then date)
- [ ] Swipe left/right gestures (mark done/cancel)
- [ ] `manifest.json` + service worker for installability
- [ ] PWA icons

### Phase 3 — Real-time + Notifications (1 day)
- [ ] SSE endpoint (`/api/events`) broadcasting new quests
- [ ] Frontend EventSource listener (update list when open)
- [ ] VAPID key generation + Web Push subscription endpoint
- [ ] Service worker push handler
- [ ] Notification permission request flow (iOS Home Screen check)
- [ ] Send push on new quest creation

### Phase 4 — homekase Integration (0.5 day)
- [ ] `lib/services/quests-app.sh` (deploy + remove)
- [ ] Register in `lib/services/service.sh` SERVICES array
- [ ] Test `homekase add quests-app` end-to-end
- [ ] Test `homekase remove quests-app`

### Phase 5 — Polish (0.5 day)
- [ ] Recording UX: warning on background, auto-save partial
- [ ] Filter tabs (All / Pending / Done / Cancelled)
- [ ] Relative time display ("2 min ago")
- [ ] Undo toast after swipe actions
- [ ] Error handling (upload failure, transcription failure)
- [ ] Delete quest from list (long press or button)

---

## 13. Open Questions / Future Considerations

- **Language support:** English only for now? Could add `language` config for multi-language transcription
- **Recording length limit:** Max 60s? 120s? Prevent accidental long recordings
- **Quest editing:** Edit title/description from the PWA after creation?
- **Due dates:** Add date picker? Or keep it simple (no due dates)?
- **Search:** Full-text search across transcripts?
- **Export:** Export quests as JSON/CSV?
- **Multiple devices:** Multiple phones recording to same server? (push subscriptions per device)
- **EU PWA limitation:** How to handle iOS 17.4+ in EU where push doesn't work? Fallback to email?
- **Backup:** SQLite file backup via homekase snapshot system (already supported with `db-type: sqlite`)

---

## 14. References

- Investigation notes: `~/Projects/quests-app/PWA.md`, `NOTES.md`
- Homekase service patterns: `docs/SERVICE_PATTERNS.md`
- Assistant agent patterns: `services/assistant/agent/` (FastAPI, async httpx, SSE)
- faster-whisper docs: https://github.com/SYSTRAN/faster-whisper
- iOS PWA Push: https://developer.apple.com/documentation/usernotifications/sending-web-push-notifications-in-web-apps-and-browsers
- Web Push VAPID: https://web.dev/articles/push-notifications-overview
