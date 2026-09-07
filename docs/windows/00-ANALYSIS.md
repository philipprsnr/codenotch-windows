# Codenotch — What the macOS app does

Written for the Windows port. Every claim here is read off the Swift source in
`Sources/`, which stays in this repository as the reference implementation.
File references are exact; use them, don't re-derive.

Scale: ~10,700 lines of Swift across 63 files, ~7,800 lines of tests across 25
files, 552 test cases. The tests are the most valuable artefact in the repo —
they pin the exact response shape of every vendor endpoint, and most of them
port to C# almost line for line.

---

## 1. The product in one paragraph

A background app pins a small black notch to a screen edge. Each tracked coding
assistant gets a ring showing how much of its usage limit is burned, and a thin
arc spins inside that ring while a session of that assistant is actually
working (amber pulse when it is blocked waiting on you). Hovering a ring opens
a card with every limit window, when each resets, and the live sessions by
name. The app never signs in anywhere: every reading is borrowed from a
credential a tool on the machine already holds.

---

## 2. Feature inventory

### 2.1 Providers (`Sources/Providers/`)

Seven adapters, all implementing `UsageProvider` (`UsageProvider.swift`).

| Provider | id | Credential source | Endpoint / read | Fidelity |
|---|---|---|---|---|
| Claude Code | `claude`, `claude-<slug>` | login keychain, service `Claude Code-credentials[-<8 hex>]` | `GET https://api.anthropic.com/api/oauth/usage`, `Authorization: Bearer`, `anthropic-beta: oauth-2025-04-20` | official |
| Cursor | `cursor` | SQLite `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`, table `ItemTable` | `GET https://cursor.com/api/usage-summary` with `WorkosCursorSessionToken` cookie | official |
| Codex | `codex` | `~/.codex/auth.json` → `tokens.access_token` + `tokens.account_id` | `https://chatgpt.com/backend-api/wham/usage` | official |
| Antigravity | `gemini` | keychain service `gemini`, account `antigravity`, Go-keyring base64 payload | local language server RPC over loopback HTTPS, then `cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary` | official / derived |
| GLM | `glm` | first hit of: `~/.claude/settings.json` (`env.ANTHROPIC_AUTH_TOKEN` + Z.ai base URL), `~/.zcode/v2/config.json`, `~/.zcode/v2/credentials.json`, `~/.local/share/opencode/auth.json` | Z.ai / bigmodel.cn coding-plan monitor | official |
| Grok | `grok` | `~/.grok/auth.json`, entry keyed `issuer::client_id`, issuer must be `https://auth.x.ai` | `https://cli-chat-proxy.grok.com/v1/billing?format=credits` | official |
| OpenCode | `opencode` | `~/.local/share/opencode/auth.json` → `opencode-go` entry | `https://opencode.ai/zen/go/v1/usage` | official |

Plus `WebSessionProvider.swift` (WKWebView + JS in-page fetch, for sites behind
bot management). Currently registered with an empty list — it is a preserved
pattern, not a shipping feature. `Sites.swift` holds the Perplexity definition.

**Multi-account (`ClaudeProfile.swift`).** `~/.claude` plus every
`~/.claude-<slug>` directory that Claude Code has actually written to (judged by
marker files `sessions`, `projects`, `settings.json`, `history.jsonl`,
`.claude.json`). Default first, rest alphabetical, so rings never swap places.
Each profile has its own provider id, its own keychain service (default name
plus `-` plus the first 8 hex digits of SHA-256 of the config directory path),
its own sessions directory and its own row in Settings.

**Every adapter's contract** (`UsageProvider`): `id`, `displayName`, `glyph`,
`fetchSnapshot()`, `account()`, `signInRoute`, `signOut()`, `presentSignIn()`,
`forgetCachedCredential()`. The last five are protocol *requirements*, not
extension members — a deliberate choice documented in the file, because
extension-only methods dispatch statically through `any UsageProvider` and
silently reported every account as absent.

### 2.2 Usage model (`Sources/Model/`)

- `Fidelity` — `.official` / `.derived` / `.manual`; a derived number is
  prefixed `~` in the UI so a guess is never dressed as a vendor figure.
- `LimitWindow` — one metered window: `usedFraction`, or `remaining`, or `used`
  (vendors differ in which end they report), plus `resetsAt`. Summary line
  renders both ends: `"12% Used · 88% left"`.
- `UsageBlock` — a limit that has been *reached* while the headline still shows
  room. Rendered as `"<reason> until 4:13 PM"`.
- `ProviderSnapshot` — id, name, glyph, fidelity, status, windows,
  `headlineID` (which window the ring means, declared by the provider rather
  than inferred from position), optional block. Carries the per-status user
  copy (`statusMessage`, `authPrompt`).
- `ProviderStatus` — `.ok`, `.stale(since:)`, `.needsAuth`, `.accessDenied`,
  `.unsupported(reason)`, `.error(reason)`.
- `UsageProviderError` — `needsAuth`, `accessDenied`, `credentialExpired`,
  `badResponse(status:)`, `rateLimited(retryAfter:)`, `nothingMetered(reason)`.
- `UsageBand` — used fraction → colour band.
- `ResetCopy` / `ElapsedCopy` — human phrasing for "resets in 51 min",
  "Resets Thu 12:00 AM", elapsed time.
- `UsageArchive` — last good reading per provider and the persisted rate-limit
  deadline, in `UserDefaults`.
- `Fixtures` — the demo data behind `CODENOTCH_DEMO=1`.

### 2.3 Store and scheduling (`Sources/Model/UsageStore.swift`, 442 lines)

The single most behaviour-dense file. Contains:

- Timer-driven refresh: full rate (60 s) while any monitored session is busy,
  idle rate (5 min) otherwise; `staleAfter` 15 min deliberately well above the
  idle interval so a single failed idle attempt does not dim a ring.
- Per-provider connection versioning by `UUID`, so a response that arrives
  after the user switched a provider off is discarded rather than shown.
- Switching a provider off stops its credential from being read *at all* — the
  filtering is before the fetch, not after — and forgets its archived reading.
- Failure degradation: `supersedesHistory(_:)` decides whether a new status
  makes the remembered reading *untrue* (`needsAuth`, `unsupported` → drop it)
  or merely *old* (`accessDenied`, `error`, rate limit → keep and dim it).
- `signOut`, `signIn`, `reauthorize`, `openAccountSource` — three different
  destinations because the providers differ in what they own.
- Wake-from-sleep refresh via `NSWorkspace.didWakeNotification`.

Rate-limit handling lives in `ClaudeOAuthProvider`: the endpoint answers 429
with an unhelpful `Retry-After: 0`, so the back-off treats that as a floor
raiser — 60 s, doubling per consecutive 429, capped at 15 min — and persists the
deadline so relaunching during a penalty waits instead of spending an attempt.

### 2.4 Activity monitoring (`Sources/Sessions/`)

`AgentActivityMonitor` protocol; one implementation per tool, all publishing
`[AgentSession]` (`id`, `name`, `detail`, `state` ∈ busy/waiting/idle,
`waitingFor`, `since`).

| Monitor | Signal |
|---|---|
| `ClaudeSessionMonitor` | Watches `~/.claude[-slug]/sessions/` with a filesystem event source (debounced 0.12 s) plus a 5 s liveness timer. Each `<pid>.json` is validated against `ProcessLiveness` — pid alive *and* process start time within 5 min of the recorded one, so a recycled pid cannot resurrect a dead session. |
| `CursorActivityMonitor` | Polls `composerHeaders` in the same SQLite store every 2 s. `unfinishedRunAt` is a flag (it holds the composer's creation time, not the run's); `conversationCheckpointLastUpdatedAt` (fallback `lastUpdatedAt`) is the timestamp that decides liveness, against a 15 min window and against Cursor's own process launch time. `hasBlockingPendingActions` / `hasPendingPlan` → waiting. |
| `CodexActivityMonitor` | No status field exists, so it is an explicitly labelled heuristic: newest rollout file mtime (from `~/.codex/state_5.sqlite`) and newest desktop thread (`~/.codex/sqlite/codex-dev.db`, `local_thread_catalog`), busy if written within 8 s. |
| `AntigravityActivityMonitor` | Transcript file mtime. |
| `GrokActivityMonitor` | Same shape. |

`ActivitySummary` reduces the set to one state, waiting outranking busy. The
store's `isBusy` closure feeds the poll schedule from these monitors.

### 2.5 The notch surface (`Sources/Notch/`, ~1,900 lines)

- `NotchPanel` — borderless, non-activating `NSPanel` at `.statusBar` level,
  `canJoinAllSpaces`, `fullScreenAuxiliary`, transparent, no shadow, never key
  or main. Right-click and left-click are intercepted in `sendEvent` /
  `mouseDown` because the SwiftUI hit test would otherwise swallow them.
- `NotchGeometry` — screen selection, panel frame per edge. Pins to
  `visibleFrame` (so a bottom notch rests on the Dock and follows it) but
  centres on `frame` (so a Dock at the bottom does not shift a right-edge
  notch). Rounds the frame outward to whole points so no hairline of wallpaper
  shows between notch and bezel. Detects the *hardware* notch from
  `auxiliaryTopLeftArea` / `auxiliaryTopRightArea` / `safeAreaInsets.top` and
  merges the top placement into it.
- `NotchEdge` — the four edges, and everything that follows from an edge:
  stack direction, tooltip direction, outward unit vector.
- `NotchLayout` (401 lines) — every measurement, quoted from
  `docs/design/frame-124-hover-tooltip.png` in design-frame pixels through
  `Design.px(_:)`. Body depth differs between vertical and horizontal edges
  because the percent label spends stack length on one and depth on the other.
  Includes the settings orb's geometry (concentric with the notch's bottom
  flare, one radius inside it).
- `SideNotchShape` — the pill with inverse rounded corners.
- `NotchPlacement` — the only place that maps one-dimensional stack space
  (`along` / `across`) back onto real screen coordinates.
- `NotchViewModel` (369 lines) — hover index, expansion, sessions, clock.
- `NotchWindowController` (653 lines) — the platform glue: global and local
  mouse monitors plus a 0.3 s cursor poll (which also notices an auto-hiding
  Dock giving space back, since that fires no screen-parameter notification),
  hover grace 0.25 s, fold grace 0.45 s, pointing-hand cursor push, interactive
  rect updates, right-click menu, relocation on screen changes and on provider
  count changes.
- `NotchMotion` — the animation curves and the stagger.
- `NotchHostingView` — hosts SwiftUI inside a plain container view, because as
  the content view SwiftUI gets a say in the window frame and its
  `GeometryReader` root reports an ideal size of 10×10.

### 2.6 Cells and card (`Sources/Features/`, `Sources/DesignSystem/`)

`ProviderRing` (track + progress arc from 12 o'clock, glyph, activity arc),
`TooltipCard` (473 lines — shell with tail, header, per-window rows with bars,
blocked row, session list capped at `defaultSessionCap`), `SettingsHandle`
(the orb: arc at rest, gear on hover). `Palette` / `Typography` / `Design` hold
colours sampled from the design frame and one `scale` that drives every size.
`GlyphOutline.swift` (532 lines) holds the traced provider marks as normalised
paths, each with a per-mark scale factor because equal boxes are not equal
marks.

### 2.7 Settings and app shell (`Sources/Settings/`, `Sources/App/`)

- `Preferences` — `UserDefaults`-backed: disconnected provider set, notch
  visibility (always / on hover / hidden), notch edge, app presence (Dock /
  menu bar / neither), last seen version, launch at login via `SMAppService`.
  Includes a one-time migration from the pre-rename defaults domain
  `com.vinz.usagenotch`, and `eraseAllData()`.
- `SettingsView` (434 lines) — Integrations (per-provider row: account,
  source, connect toggle, sign out with caveat, switch account, "Allow
  access…" when macOS refused), Appearance, General (login item, automatic
  updates, check now, version), About.
- `WhatsNewView` / `ReleaseNotes` — per-version changelog shown once.
- `AppDelegate` (243 lines) — wires everything: profile discovery, provider
  construction, store, monitors, preference bindings, first-launch onboarding,
  demo mode, `CODENOTCH_DISCOVER=<url>` endpoint-discovery mode.
- `StatusItemController` — the menu bar item (template image, 18pt).
- `Updater` — Sparkle wrapper: silent automatic checks and installs, with a
  human-readable outcome for the settings sheet because Sparkle's own error
  copy names no cause.
- `Log` — `os.Logger`, subsystems `com.vinz.codenotch`, categories `usage` and
  `sessions`.

### 2.8 Build and release

XcodeGen (`project.yml`) → `.xcodeproj`, driven by `Makefile`: `gen`, `build`,
`test`, `run`, `clean`, and the maintainer-only `archive` → `dmg` →
`notarize` → `verify-release` → `appcast` chain. Signed with a stable Developer
ID identity specifically so the keychain "Always Allow" grant survives
rebuilds. Hardened runtime on, App Sandbox off (the sandbox would break both
the keychain read and the reads of Cursor's and Codex's files).

---

## 3. Platform-dependency inventory

What the port actually has to solve. Roughly: 40% of the code is portable
logic, 35% is UI that must be rewritten, 25% needs a Windows equivalent.

### 3.1 Pure logic — ports directly, tests port with it

`UsageModel`, `UsageBand`, `ResetCopy`, `ElapsedCopy`, `UsageArchive` (minus
its storage backend), the JSON/JWT parsing in every `*Credentials` and
`*Usage` file, `ClaudeProfile`'s discovery and identity rules,
`ProcessLiveness`'s reuse-tolerance rule, `ActivitySummary`, `NotchLayout`,
`NotchEdge`, `NotchPlacement`, `NotchGeometry`'s frame maths, `GlyphOutline`,
`UsageStore`'s scheduling and degradation rules.

### 3.2 Needs a Windows equivalent

| macOS API | Used in | Windows equivalent |
|---|---|---|
| `SecItemCopyMatching`, `kSecAttrModificationDate` | `ClaudeCredentials`, `KeychainItem`, `AntigravityCredentials` | Credential Manager (`CredReadW`, `LastWritten`) — **but likely unnecessary for Claude, see `DATA-SOURCES.md`** |
| `NSHomeDirectory()` + `Library/Application Support` | every credential file path | `%USERPROFILE%`, `%APPDATA%`, `%LOCALAPPDATA%` |
| `sqlite3` C API (`SQLiteStore.swift`) | Cursor, Codex | `Microsoft.Data.Sqlite`, read-only, **WAL-aware** (never `immutable=1`) |
| `/bin/ps -Ao pid,command` | `AntigravityBridge.discover` | WMI `Win32_Process.CommandLine` |
| `/usr/sbin/lsof -nP -a -p <pid> -iTCP -sTCP:LISTEN` | `AntigravityBridge.listeningPorts` | `GetExtendedTcpTable(TCP_TABLE_OWNER_PID_LISTENER)` |
| `kill(pid, 0)`, `sysctl KERN_PROC_PID` | `ProcessLiveness` | `Process.GetProcessById` + `Process.StartTime` |
| `DispatchSource.makeFileSystemObjectSource` | `ClaudeSessionMonitor` | `FileSystemWatcher` |
| `NSWorkspace.runningApplications` + bundle id | `CursorActivityMonitor` | `Process.GetProcessesByName` + module path check |
| `NSWorkspace.openApplication(bundleID:)` | `UsageStore.openAccountSource` | resolve install path (registry / well-known) and `Process.Start` |
| `NSWorkspace.didWakeNotification` | `UsageStore` | `SystemEvents.PowerModeChanged` (Resume) |
| `NSScreen.visibleFrame` (Dock-aware) | `NotchGeometry` | `GetMonitorInfo` → `MONITORINFO.rcWork` (taskbar-aware) |
| `NSApplication.didChangeScreenParametersNotification` | `NotchWindowController` | `WM_DISPLAYCHANGE`, `WM_DPICHANGED`, `WM_SETTINGCHANGE` |
| `NSEvent.addGlobalMonitorForEvents` | `NotchWindowController` | `GetCursorPos` poll (already the backup path) or `WH_MOUSE_LL` |
| `NSPanel` non-activating, `.statusBar` level | `NotchPanel` | layered/transparent WPF window + `WS_EX_NOACTIVATE`, `WS_EX_TOOLWINDOW`, `HWND_TOPMOST` |
| SwiftUI hit-test hole / click-through | `NotchPanel`, `NotchHostingView` | `WM_NCHITTEST` → `HTTRANSPARENT`, or `WS_EX_TRANSPARENT` toggling |
| `NSStatusItem` | `StatusItemController` | tray icon (`NotifyIcon`) |
| `NSApp.setActivationPolicy` | `AppDelegate`, `AppPresence` | `ShowInTaskbar` + `WS_EX_TOOLWINDOW` |
| `SMAppService.mainApp` | `Preferences` | `HKCU\...\CurrentVersion\Run` (Velopack has a helper) |
| `UserDefaults` | `Preferences`, `UsageArchive` | JSON file under `%APPDATA%\Codenotch\` |
| `os.Logger` | `Log` | Serilog → rolling file under `%LOCALAPPDATA%\Codenotch\logs\` |
| Sparkle | `Updater` | Velopack |
| `CryptoKit.SHA256` | `ClaudeProfile` | `System.Security.Cryptography.SHA256` |
| `URLSession` + `LocalhostTrust` | `AntigravityBridge` | `HttpClient` + loopback-scoped `RemoteCertificateValidationCallback` |
| `WKWebView` | `WebSessionProvider` | WebView2 — out of scope for v1 |

### 3.3 Has no Windows counterpart at all

- **The hardware notch.** `HardwareNotch`, `joinedNotch`, the top-edge merge
  and `orbConvexArcRadius` exist for MacBook display cut-outs. On Windows the
  top edge is just an edge. Keep the code paths, feed them `null`.
- **`accessDenied` as a first-class status.** It models the macOS keychain
  "Deny" button. If Windows credentials turn out to be file-based, this status
  loses its trigger — but it must stay in the model, because the Antigravity
  path may still hit Credential Manager, and because file ACL denial is the
  same shape of problem.
- **Spaces / full-screen auxiliary windows.** Windows virtual desktops behave
  differently; a topmost tool window is normally per-desktop.
