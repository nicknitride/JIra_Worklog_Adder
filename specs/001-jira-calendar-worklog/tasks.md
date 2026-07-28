# Tasks: Jira Calendar Worklog TUI

**Input**: Design documents from `/specs/001-jira-calendar-worklog/`

**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, contracts/

**Tests**: Not explicitly requested in spec — bats tests included in Polish phase per plan.md testing strategy.

**Organization**: Tasks grouped by user story to enable independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1–US4)
- Include exact file paths in descriptions

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and basic structure

- [x] T001 Create directory structure: `lib/assets/`, `scripts/`, `logs/`, `tests/unit/`, `tests/integration/` per plan.md
- [x] T002 [P] Create `.env.example` with labeled placeholders per `specs/001-jira-calendar-worklog/contracts/cli-contract.md`
- [x] T003 [P] Update `.gitignore` to exclude `.env`, `logs/`, and `google_api_oauth_details.txt`
- [x] T004 [P] Create GCash ASCII art banner in `lib/assets/gcash-banner.txt`
- [x] T005 [P] Create `scripts/requirements.txt` with `google-auth-oauthlib` and `google-api-python-client`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story work begins

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [x] T006 Implement ISO-8601 audit logging helpers in `lib/logging.sh` (INFO/WARN/ERROR/DEBUG, session file in `logs/`, stderr progress per FR-012a)
- [x] T007 Implement `.env` load, placeholder rejection, and `JIRA_LOGGING_LABEL` auto-compute in `lib/config.sh` per data-model.md Config entity
- [x] T008 Implement user confirmation prompts (`y/yes`) in `lib/confirm.sh` per constitution CR-001
- [x] T009 Create `worklog-tui.sh` entry point with `--help`, `--version`, `--verbose`, `--dry-run` flags and exit codes per cli-contract.md
- [x] T010 Wire session log auto-creation, config load, and missing-`.env` error handling in `worklog-tui.sh` using `lib/logging.sh` and `lib/config.sh`

**Checkpoint**: Foundation ready — user story implementation can now begin

---

## Phase 3: User Story 1 - Connect and View Sprint Context (Priority: P1) 🎯 MVP

**Goal**: Launch with `.env` credentials, connect to Jira and Google, display labeled sprint ticket buckets in blue TUI

**Independent Test**: Run `./worklog-tui.sh --dry-run` with valid `.env`; see GCash welcome, connection status, and sprint tickets filtered by `DLV-133 {YYYY}-{Month}` label without calendar or worklog steps

### Implementation for User Story 1

- [x] T011 [P] [US1] Implement Jira auth validation (`GET /rest/api/3/myself`) with exit code 3 on 401 in `lib/jira-api.sh`
- [x] T012 [US1] Implement active sprint fetch, label-filtered issue list, and empty-sprint WARN in `lib/jira-api.sh` per jira-api-contract.md
- [x] T013 [P] [US1] Implement `oauth` subcommand with browser flow and `GOOGLE_OAUTH_PORT` support in `scripts/google_calendar.py` per google-calendar-contract.md
- [x] T014 [US1] Implement OAuth wrapper in `lib/calendar-api.sh` with user confirm before writing `GOOGLE_REFRESH_TOKEN` to `.env`
- [x] T015 [P] [US1] Implement welcome screen, blue gum theme (`#0066CC`), and GCash banner loader in `lib/tui.sh`
- [x] T016 [US1] Implement connection status and sprint ticket list screens (label, key, summary) in `lib/tui.sh`
- [x] T017 [US1] Wire US1 flow in `worklog-tui.sh`: config validate → Jira validate → Google OAuth if needed → sprint ticket display

**Checkpoint**: US1 complete — tool connects and shows sprint logging tickets without calendar/worklog steps

---

## Phase 4: User Story 2 - Select Viable Calendar Days (Priority: P2)

**Goal**: Default to current Mon–Sun week, toggle day viability, fetch events only for viable days

**Independent Test**: Toggle days yes/no; confirm only viable days trigger calendar fetch; empty days show empty state without error

### Implementation for User Story 2

- [x] T018 [P] [US2] Implement current-week Mon–Sun date range computation with `TZ` support in `lib/config.sh`
- [x] T019 [US2] Implement day-selection screen with yes/no toggles, range adjustment, and at-least-one-viable validation in `lib/tui.sh`
- [x] T020 [P] [US2] Implement `events` subcommand with RFC3339 fetch and normalized JSON output in `scripts/google_calendar.py` per google-calendar-contract.md
- [x] T021 [US2] Implement viable-day event fetch wrapper in `lib/calendar-api.sh`
- [x] T022 [US2] Wire US2 day-selection flow in `worklog-tui.sh` after sprint ticket load

**Checkpoint**: US2 complete — viable days gate calendar event loading

---

## Phase 5: User Story 3 - Select Events and Map to Sprint Tickets (Priority: P3)

**Goal**: Select filtered calendar events, map to sprint tickets, confirm, submit worklogs (or dry-run)

**Independent Test**: Map one event to a ticket, confirm preview, verify Jira worklog with event title as description and calendar-derived duration (no manual override)

### Implementation for User Story 3

- [x] T023 [P] [US3] Implement declined/cancelled exclusion, all-day 480-min default, and tentative warning flags in `lib/calendar-api.sh`
- [x] T024 [US3] Implement event multi-select list with warning badges and empty-state message in `lib/tui.sh`
- [x] T025 [US3] Implement per-event ticket bucket assignment UI in `lib/tui.sh`
- [x] T026 [P] [US3] Implement worklog POST with ADF comment body and 429 retry-once in `lib/jira-api.sh` per jira-api-contract.md
- [x] T027 [US3] Implement submission preview, 8-hour daily warning (FR-008a), and confirmation gate in `lib/tui.sh`
- [x] T028 [US3] Implement manual ticket key entry fallback in `lib/tui.sh` when sprint list is empty (FR-014)
- [x] T029 [US3] Implement out-of-sprint ticket warning with explicit confirm in `lib/tui.sh` (FR-014a)
- [x] T030 [US3] Wire US3 mapping and submit flow with `--dry-run` support in `worklog-tui.sh`

**Checkpoint**: US3 complete — end-to-end worklog submission with user confirmation

---

## Phase 6: User Story 4 - Transparent Audit Trail (Priority: P4)

**Goal**: Every action in all flows recorded in timestamped session log files; no secrets logged

**Independent Test**: Run full dry-run session; verify `logs/*.txt` contains ISO-8601 entries for every API call, selection, confirmation, and error

### Implementation for User Story 4

- [x] T031 [P] [US4] Add audit log entries to all `lib/jira-api.sh` operations per jira-api-contract.md action keys
- [x] T032 [P] [US4] Add audit log entries to all `lib/calendar-api.sh` and `scripts/google_calendar.py` operations per google-calendar-contract.md
- [x] T033 [US4] Add audit log entries for TUI selections (day toggles, event picks, confirm/decline) in `lib/tui.sh`
- [x] T034 [US4] Implement secret redaction guard in `lib/logging.sh` ensuring no credential values appear in `logs/*.txt` (FR-001c, VR-006)

**Checkpoint**: US4 complete — full session reconstructable from audit log

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Quality, tests, and validation

- [x] T035 [P] Create unit tests for logging helpers in `tests/unit/test_logging.bats`
- [x] T036 [P] Create unit tests for config validation and placeholder rejection in `tests/unit/test_config.bats`
- [x] T037 [P] Create unit tests for event filter logic in `tests/unit/test_event_filter.bats`
- [x] T038 Create integration test for dry-run flow in `tests/integration/test_dry_run.bats`
- [x] T039 Set executable permission on `worklog-tui.sh` and verify `--help` and `--version` output matches cli-contract.md
- [x] T040 Run quickstart validation scenarios from `specs/001-jira-calendar-worklog/quickstart.md` and fix gaps

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 — **BLOCKS all user stories**
- **US1 (Phase 3)**: Depends on Phase 2 — MVP
- **US2 (Phase 4)**: Depends on Phase 2 + US1 (needs Google OAuth connected)
- **US3 (Phase 5)**: Depends on US1 + US2 (needs tickets and viable-day events)
- **US4 (Phase 6)**: Depends on US1–US3 modules existing; audit pass after handlers exist
- **Polish (Phase 7)**: Depends on all desired user stories

### User Story Dependencies

```text
US1 (P1) ──► US2 (P2) ──► US3 (P3)
                │              │
                └──────────────┴──► US4 (P4) audit completeness pass
```

- **US1**: Independent after Foundational
- **US2**: Requires US1 Google connection path
- **US3**: Requires US1 sprint tickets + US2 viable days/events
- **US4**: Cross-cutting; best executed after US1–US3 handlers exist

### Within Each User Story

- API modules before TUI screens that consume them
- TUI screens before `worklog-tui.sh` wiring
- Core implementation before audit log pass (US4)

### Parallel Opportunities

- Phase 1: T002, T003, T004, T005 in parallel
- Phase 3: T011 + T013 + T015 in parallel; then T012, T014, T016 sequential
- Phase 4: T018 + T020 in parallel
- Phase 5: T023 + T026 in parallel
- Phase 6: T031 + T032 in parallel
- Phase 7: T035, T036, T037 in parallel

---

## Parallel Example: User Story 1

```bash
# Launch API/TUI modules together:
Task T011: "Implement Jira auth validation in lib/jira-api.sh"
Task T013: "Implement oauth subcommand in scripts/google_calendar.py"
Task T015: "Implement welcome screen in lib/tui.sh"

# Then integrate:
Task T012: "Implement sprint issue fetch in lib/jira-api.sh"
Task T014: "Implement OAuth wrapper in lib/calendar-api.sh"
Task T017: "Wire US1 flow in worklog-tui.sh"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational
3. Complete Phase 3: User Story 1
4. **STOP and VALIDATE**: `./worklog-tui.sh --dry-run` shows sprint logging tickets
5. Demo connection flow if ready

### Incremental Delivery

1. Setup + Foundational → Foundation ready
2. US1 → Connect + sprint tickets (MVP)
3. US2 → Day selection + calendar fetch
4. US3 → Event mapping + worklog submit
5. US4 → Audit trail completeness pass
6. Polish → bats tests + quickstart validation

### Parallel Team Strategy

With multiple developers after Foundational:

- Developer A: US1 (`lib/jira-api.sh`, sprint TUI)
- Developer B: US1 Google path (`scripts/google_calendar.py`, `lib/calendar-api.sh`)
- Then sequential US2 → US3 on shared `worklog-tui.sh` wiring

---

## Notes

- All mutating actions require user confirmation per constitution CR-001
- Never log secret values — only variable names and action outcomes
- `--dry-run` must skip Jira POST and `.env` writes but still produce audit log entries marked `[DRY-RUN]`
- Worklog duration is calendar-derived only — no manual override (FR-009)
- Commit after each task or logical group; reference feature ID `001-jira-calendar-worklog`
