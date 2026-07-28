# Research: Jira Calendar Worklog TUI

**Feature**: 001-jira-calendar-worklog | **Date**: 2026-07-09

## 1. TUI Framework

**Decision**: [gum](https://github.com/charmbracelet/gum) (Charmbracelet) invoked from bash

**Rationale**:
- Native support for styled prompts, tables, spinners, filters, and confirm dialogs
- `--foreground "#0066CC"` (GCash blue) theming via env vars
- Better UX than `dialog`/`whiptail` for multi-step flows with branding
- Callable from bash without embedding another language in UI layer

**Alternatives considered**:
| Alternative | Rejected because |
|-------------|------------------|
| `dialog` / `whiptail` | Limited styling; hard to achieve "beautiful" blue branded UX |
| Pure `tput`/`printf` | High maintenance for interactive lists and toggles |
| Python `textual`/`rich` | Violates bash-first spec intent; heavier dependency tree |

---

## 2. Google Calendar Authentication

**Decision**: Python 3 helper (`scripts/google_calendar.py`) with `google-auth-oauthlib`
Installed App flow; refresh token persisted to `.env`

**Rationale**:
- Google Calendar private data requires OAuth 2.0 — API key alone insufficient (confirmed in clarify)
- Official Google client libraries handle token refresh reliably
- First-run opens browser; subsequent runs use cached `GOOGLE_REFRESH_TOKEN`
- Redirect URI: `http://localhost:8080/` (configurable via `GOOGLE_OAUTH_PORT`)

**Alternatives considered**:
| Alternative | Rejected because |
|-------------|------------------|
| curl-only OAuth | Fragile PKCE/state handling; high bug surface |
| `oauth2l` CLI | Extra install; less control over token persist to `.env` |
| Service account | Requires Workspace admin delegation; overkill for personal tool |

**OAuth scopes**: `https://www.googleapis.com/auth/calendar.readonly`

---

## 3. Jira Cloud Integration

**Decision**: REST API v3 via `curl` + `jq`; Basic auth with `ATLASSIAN_EMAIL:ATLASSIAN_API_TOKEN`

**Rationale**:
- Jira Cloud standard auth pattern; no extra SDK needed
- Sprint issues via Agile API: `GET /rest/agile/1.0/board/{boardId}/sprint?state=active`
  then `GET /rest/agile/1.0/sprint/{sprintId}/issue`
- Label filter applied client-side: issues where `fields.labels` contains `JIRA_LOGGING_LABEL`
- Worklog: `POST /rest/api/3/issue/{issueKey}/worklog`

**Alternatives considered**:
| Alternative | Rejected because |
|-------------|------------------|
| Jira CLI (`go-jira`) | Extra tool dependency; less control over label filter UX |
| JQL-only search | Sprint boundary + label combo clearer via Agile API |

---

## 4. Configuration & Secrets

**Decision**: `.env` at project root; committed `.env.example` with labeled placeholders

**Rationale**:
- User-requested pattern (clarify session)
- `lib/config.sh` validates required vars on startup; rejects placeholder values like `your-*`
- `GOOGLE_REFRESH_TOKEN` appended after first OAuth (with user confirmation per constitution)
- `.gitignore` covers `.env`, `logs/`, `google_api_oauth_details.txt`

**Variable set**: See [contracts/cli-contract.md](./contracts/cli-contract.md)

---

## 5. Logging & Audit Trail

**Decision**: Dedicated `lib/logging.sh` writing to `logs/{ISO-date}T{time}-session.txt`

**Rationale**:
- Constitution CR-003 requires ISO-8601 timestamped action logs
- Separate from stderr progress output (CR-002)
- Format: `[2026-07-09T12:30:00+0800] INFO action=... outcome=...`
- Secrets redacted: log variable names only, never values

**Alternatives considered**:
| Alternative | Rejected because |
|-------------|------------------|
| syslog | Overkill; user wants local `.txt` audit files |
| Single shared `common.sh` from `.specify/` | Feature tool is standalone at repo root |

---

## 6. Calendar Event Filtering

**Decision**: Filter in `calendar-api.sh` after Python returns JSON event list

**Rationale**:
- Exclude `responseStatus` in (`declined`, `cancelled`)
- Flag `allDay: true` and `responseStatus: tentative` with `warning` field for TUI badge
- Accepted/default events shown without warning

**All-day duration default**: 8h cap with user adjustment prompt (edge case: daily 8h threshold)

---

## 7. Date Range Default

**Decision**: Current calendar week Mon–Sun in local timezone (`TZ` env or system default)

**Rationale**:
- User chose Option C in clarify session
- Computed via `date` command: find Monday of current week, Sunday end
- User can expand/narrow range in TUI before toggling viability

---

## 8. Sprint Ticket Label Pattern

**Decision**: Auto-compute `DLV-133 {YYYY}-{MonthName}` using `date +"%Y-%B"` → e.g. `DLV-133 2026-July`

**Rationale**:
- User-specified team logging label pattern
- Overridable via `JIRA_LOGGING_LABEL` in `.env` for edge months or typos
- Filter sprint issues where labels array contains exact match

---

## 9. Testing Strategy

**Decision**: `bats` for bash units; `--dry-run` integration test; manual OAuth quickstart

**Rationale**:
- Constitution-aligned: test logging, config validation, event filter logic without live APIs
- Live Jira/Google tests documented in quickstart.md (manual, user credentials)

**Alternatives considered**:
| Alternative | Rejected because |
|-------------|------------------|
| pytest for all | Bash is orchestration layer; bats matches shell code |
| No tests | Violates quality engineering rules for new scripts |

---

## Resolved Unknowns

All Technical Context items resolved — no remaining `NEEDS CLARIFICATION` markers.
