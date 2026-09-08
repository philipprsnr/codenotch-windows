# Windows data sources — verification worksheet

Every row is an **expectation** until someone checks it on a real Windows 11
machine with the tool installed and signed in. Rule C4: implementing against an
`UNVERIFIED` row is allowed; claiming it works is not.

Mark a row `VERIFIED <yyyy-mm-dd> <tool version>` when checked, or correct it.

`~` below means `%USERPROFILE%`.

---

## Blocking unknown

**Where does Claude Code keep its OAuth token on Windows?**

On macOS it is the login keychain, service `Claude Code-credentials`, with a
`-<8 hex>` suffix per non-default config directory (`ClaudeProfile.swift`).
Windows has no equivalent that Claude Code is known to use, and the plausible
answer is a plain file beside the rest of its configuration.

| Candidate | Notes |
|---|---|
| `~\.claude\.credentials.json` | The shape used where no OS keychain integration exists. Would remove the entire credential-store layer from v1. |
| Windows Credential Manager | Would need `CredReadW` in M5 rather than M7, and raises the same "which duplicate is newest" problem `KeychainItem.swift` solves. |
| DPAPI-protected file | Needs `CryptUnprotectData`; readable only by the same user, which is fine. |

**How to check:** install Claude Code on Windows, sign in, then
`dir /a %USERPROFILE%\.claude`, and `cmdkey /list` for anything mentioning
Claude. Record the answer here before M5 starts.

Status: **UNVERIFIED**

---

## v1 providers

| Provider | macOS source | Expected Windows source | Status |
|---|---|---|---|
| Claude Code — token | keychain `Claude Code-credentials` | see above | UNVERIFIED |
| Claude Code — profiles | `~/.claude`, `~/.claude-<slug>` | `~\.claude`, `~\.claude-<slug>` — same convention, since it is Claude Code's own | UNVERIFIED |
| Claude Code — sessions | `~/.claude/sessions/<pid>.json` | `~\.claude\sessions\<pid>.json` | UNVERIFIED |
| Cursor — state store | `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb` | `%APPDATA%\Cursor\User\globalStorage\state.vscdb` (VS Code convention) | UNVERIFIED |
| Cursor — process identity | bundle id `com.todesktop.230313mzl4w4u92` | process name `Cursor`, module path under `%LOCALAPPDATA%\Programs\cursor\` | UNVERIFIED |
| Codex — auth | `~/.codex/auth.json` | `~\.codex\auth.json` | UNVERIFIED |
| Codex — CLI state | `~/.codex/state_5.sqlite` | `~\.codex\state_5.sqlite` | UNVERIFIED |
| Codex — desktop threads | `~/.codex/sqlite/codex-dev.db` | `~\.codex\sqlite\codex-dev.db` | UNVERIFIED |

Note on rollout paths: `CodexStore.newestRollout` expands a leading `~` in the
stored path. On Windows the stored paths may be absolute Windows paths, or may
still carry POSIX separators if written by a WSL-hosted CLI. Check both.

---

## v2 providers

| Provider | macOS source | Expected Windows source | Status |
|---|---|---|---|
| GLM — via Claude Code | `~/.claude/settings.json` → `env.ANTHROPIC_AUTH_TOKEN` + `ANTHROPIC_BASE_URL` | `~\.claude\settings.json`, same keys | UNVERIFIED |
| GLM — via ZCode config | `~/.zcode/v2/config.json` | `~\.zcode\v2\config.json` | UNVERIFIED |
| GLM — via ZCode credentials | `~/.zcode/v2/credentials.json` | same | UNVERIFIED |
| GLM — via OpenCode | `~/.local/share/opencode/auth.json` | `~\.local\share\opencode\auth.json` **or** `%APPDATA%\opencode\auth.json` — OpenCode's XDG handling on Windows is the question | UNVERIFIED |
| Grok | `~/.grok/auth.json` | `~\.grok\auth.json` | UNVERIFIED |
| OpenCode | `~/.local/share/opencode/auth.json` | as GLM row above | UNVERIFIED |
| Antigravity — credential | keychain service `gemini`, account `antigravity`, value prefixed `go-keyring-base64:` | Credential Manager. The Go keyring library's Windows backend is `wincred`; target-name format and the 2560-byte value split both need checking | UNVERIFIED |
| Antigravity — language server | `ps` for `--csrf_token`, `lsof` for listening ports | WMI `Win32_Process.CommandLine`; `GetExtendedTcpTable(TCP_TABLE_OWNER_PID_LISTENER)` | UNVERIFIED |
| Antigravity — transcripts | `AntigravityActivity.transcriptRoot` | Windows path unknown | UNVERIFIED |

---

## Endpoints — unchanged by platform, listed for completeness

| Provider | Request |
|---|---|
| Claude | `GET https://api.anthropic.com/api/oauth/usage`, `Authorization: Bearer <token>`, `anthropic-beta: oauth-2025-04-20` |
| Cursor | `GET https://cursor.com/api/usage-summary`, cookie `WorkosCursorSessionToken=<accountId>::<token>` |
| Codex | `https://chatgpt.com/backend-api/wham/usage` |
| GLM | Z.ai / `open.bigmodel.cn` coding-plan monitor, host chosen by the key's console |
| Grok | `GET https://cli-chat-proxy.grok.com/v1/billing?format=credits` |
| OpenCode | `https://opencode.ai/zen/go/v1/usage` |
| Antigravity | local: `POST https://127.0.0.1:<port>/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary`, header `x-codeium-csrf-token`, body `{"forceRefresh":true}`. Remote fallback: `cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary` |

---

## Response fixtures

Capture one real, redacted body per endpoint into
`windows/tests/Codenotch.Core.Tests/Fixtures/<provider>/` during P0. The Swift
tests in `Tests/UsageResponseTests.swift` (946 lines) already encode the shapes
these must satisfy — read them before capturing, so the capture covers the same
edge cases.
