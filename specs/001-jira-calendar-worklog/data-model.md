# Data Model: Jira Calendar Worklog TUI

**Feature**: 001-jira-calendar-worklog | **Date**: 2026-07-09

## Entity Relationship Overview

```text
Session
 ├── Config (.env)
 ├── AuditLog (logs/*.txt)
 ├── SprintContext
 │    └── SprintTicket[]
 ├── DaySelection
 │    └── ViableDay[]
 ├── CalendarEvent[] (filtered)
 └── WorklogMapping[] → Jira Worklog (on confirm)
```

---

## Config

Runtime configuration loaded from `.env` at session start.

| Field | Source | Required | Default | Validation |
|-------|--------|----------|---------|------------|
| `ATLASSIAN_EMAIL` | .env | yes | — | Valid email format |
| `ATLASSIAN_API_TOKEN` | .env | yes | — | Non-empty, not placeholder |
| `ATLASSIAN_BASE_URL` | .env | yes | — | HTTPS URL, no trailing slash |
| `GOOGLE_CLIENT_ID` | .env | yes | — | Non-empty |
| `GOOGLE_CLIENT_SECRET` | .env | yes | — | Non-empty |
| `GOOGLE_REFRESH_TOKEN` | .env | no* | — | Auto-set after OAuth |
| `JIRA_PROJECT_KEY` | .env | no | `TRIBE06` | Uppercase key |
| `JIRA_BOARD_ID` | .env | no | `4912` | Numeric |
| `GOOGLE_CALENDAR_ID` | .env | no | `primary` | Calendar ID string |
| `JIRA_LOGGING_LABEL` | .env | no | auto `DLV-133 YYYY-Month` | Exact label match |

\*Required after first successful OAuth; absent triggers browser flow.

**State transitions**:
- `missing .env` → ERROR, exit
- `placeholder values` → ERROR, list invalid keys
- `no refresh token` → OAuth flow → user confirm → write token to `.env`

---

## SprintTicket

Jira issue eligible as worklog bucket.

| Field | Type | Source | Notes |
|-------|------|--------|-------|
| `key` | string | Jira `issue.key` | e.g. `TRIBE06-67802` |
| `summary` | string | Jira `fields.summary` | Display in TUI |
| `labels` | string[] | Jira `fields.labels` | Must include logging label |
| `status` | string | Jira `fields.status.name` | Informational |
| `inActiveSprint` | boolean | Agile API | Must be true |

**Validation**: At least zero matches allowed; empty → manual key entry (FR-014).

---

## ViableDay

User-selected calendar date for event fetching.

| Field | Type | Notes |
|-------|------|-------|
| `date` | ISO date `YYYY-MM-DD` | Local timezone |
| `viable` | boolean | User yes/no toggle |
| `dayOfWeek` | string | Mon–Sun, display only |

**Defaults**: Current week Mon–Sun, all toggles start `false` (user explicitly marks viable).

---

## CalendarEvent

Google Calendar event after filtering.

| Field | Type | Source | Notes |
|-------|------|--------|-------|
| `id` | string | Google `id` | Unique per calendar |
| `title` | string | Google `summary` | Becomes worklog description |
| `startTime` | ISO datetime | Google `start.dateTime` or `start.date` | |
| `endTime` | ISO datetime | Google `end.dateTime` or `end.date` | |
| `durationMinutes` | integer | computed | All-day → default 480, adjustable |
| `responseStatus` | enum | Google `attendees[].self.responseStatus` or event status | |
| `allDay` | boolean | `start.date` present without time | Triggers warning badge |
| `warning` | enum? | derived | `ALL_DAY`, `TENTATIVE`, null |
| `selected` | boolean | TUI state | User checkbox |

**Filter rules** (FR-005a/b):
- EXCLUDE: `responseStatus` ∈ {`declined`, `cancelled`}
- INCLUDE with warning: `allDay=true` → `ALL_DAY`; `tentative` → `TENTATIVE`

---

## WorklogMapping

Pending or submitted link between event and ticket.

| Field | Type | Notes |
|-------|------|-------|
| `eventId` | string | FK → CalendarEvent.id |
| `eventTitle` | string | Denormalized for preview/log |
| `ticketKey` | string | FK → SprintTicket.key |
| `durationMinutes` | integer | User-adjustable |
| `workDate` | ISO date | From event start, local TZ |
| `description` | string | = eventTitle (FR-009a) |
| `status` | enum | `pending`, `confirmed`, `submitted`, `skipped`, `dry_run` |

**Lifecycle**:
```text
pending → (user confirm) → submitted | dry_run
pending → (user decline) → skipped
```

---

## AuditLogEntry

Append-only session log record.

| Field | Type | Notes |
|-------|------|-------|
| `timestamp` | ISO-8601 | With timezone offset |
| `level` | enum | INFO, WARN, ERROR, DEBUG |
| `action` | string | e.g. `jira.worklog.submit` |
| `target` | string | Ticket key, event id, var name |
| `outcome` | string | success, failure, dry_run, skipped |
| `detail` | string | No secret values |

**File naming**: `logs/YYYY-MM-DDTHH-MM-SS-session.txt`

---

## Session State Machine

```text
INIT → LOAD_CONFIG → VALIDATE_CREDS
  → [oauth if needed] → CONNECT_JIRA → CONNECT_GOOGLE
  → LOAD_SPRINT_TICKETS → DAY_SELECT → FETCH_EVENTS
  → EVENT_SELECT → MAP_TICKETS → PREVIEW
  → CONFIRM → [SUBMIT_WORKLOGS | DRY_RUN] → DONE
```

Each transition produces an AuditLogEntry.

---

## Validation Rules Summary

| Rule | Entity | Constraint |
|------|--------|------------|
| VR-001 | WorklogMapping | durationMinutes > 0 |
| VR-002 | WorklogMapping | ticketKey matches `[A-Z]+-[0-9]+` |
| VR-003 | ViableDay | At least one viable=true to proceed |
| VR-004 | CalendarEvent | declined/cancelled never selectable |
| VR-005 | Session | Total mapped minutes/day > 480 → WARN |
| VR-006 | Config | Secret values never in AuditLogEntry.detail |
