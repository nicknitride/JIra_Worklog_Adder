# Implementation Plan: Jira Calendar Worklog TUI

**Branch**: `001-jira-calendar-worklog` | **Date**: 2026-07-09 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/001-jira-calendar-worklog/spec.md`

## Summary

Build a bash-driven CLI tool with a blue-themed TUI (`gum`) that loads credentials from
`.env`, connects to Jira Cloud (TRIBE06) and Google Calendar (OAuth), lets the user
toggle viable days (default: current Mon–Sun week), select filtered calendar events,
map them to sprint tickets labeled `DLV-133 {YYYY}-{Month}`, and submit worklogs after
explicit confirmation. All actions are audit-logged to timestamped files in `logs/`.

Hybrid architecture: bash orchestrates flow, `curl`+`jq` calls Jira REST API, Python 3
helper handles Google OAuth refresh and Calendar API reads.

## Technical Context

**Language/Version**: Bash 5.x (orchestration), Python 3.11+ (Google OAuth/Calendar)

**Primary Dependencies**: `curl`, `jq`, `gum` (Charm TUI), `python3`,
`google-auth-oauthlib`, `google-api-python-client`, `python-dotenv` (optional in helper)

**Storage**: File-based only — `.env` (secrets, gitignored), `logs/*.txt` (session audit),
no database

**Testing**: `bats` for bash unit/integration tests; manual quickstart scenarios for OAuth/TUI

**Target Platform**: macOS and Linux terminal (local single-user CLI)

**Project Type**: CLI tool with interactive TUI

**Performance Goals**: Credential validation < 10s (SC-005); full single-day flow < 5 min (SC-001)

**Constraints**: Secrets never in logs; user confirmation before Jira writes and `.env`
updates; `--dry-run` supported; blue GCash-branded TUI

**Scale/Scope**: Single user, ~7 days/week, ~20 events/day, ~10 sprint tickets/session

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Verify compliance with `.specify/memory/constitution.md` (v1.0.0):

- [x] **User Verification**: Jira worklog submit, `.env` refresh-token write, and log
      file creation gated by explicit `y/yes` confirmation; `--dry-run` skips mutations.
- [x] **Verbose Scripts**: `lib/logging.sh` provides step-level INFO logs; `--verbose`
      enables `set -x` trace; errors prefixed `ERROR:` on stderr.
- [x] **Timestamped Logging**: ISO-8601 session log in `logs/`; every API call, toggle,
      and confirmation recorded (FR-012, CR-003).
- [x] **Spec-Driven**: spec.md with 4 prioritized user stories completed before plan.
- [x] **Auditability**: Session log + spec traceability via FR/CR IDs in plan and tasks.

**Post-design re-check (Phase 1)**: All gates pass. No constitution violations requiring
Complexity Tracking entries.

## Project Structure

### Documentation (this feature)

```text
specs/001-jira-calendar-worklog/
├── plan.md              # This file
├── research.md          # Phase 0 — technology decisions
├── data-model.md        # Phase 1 — entities and state
├── quickstart.md        # Phase 1 — validation guide
├── contracts/           # Phase 1 — CLI and API contracts
│   ├── cli-contract.md
│   ├── jira-api-contract.md
│   └── google-calendar-contract.md
└── tasks.md             # Phase 2 (/speckit-tasks — not yet created)
```

### Source Code (repository root)

```text
worklog-tui.sh                 # Main entry point
.env.example                   # Labeled credential placeholders
.gitignore                     # .env, logs/, token cache

lib/
├── logging.sh                 # ISO-8601 audit log + stderr helpers
├── config.sh                  # .env load/validate, label auto-compute
├── confirm.sh                 # User verification prompts
├── jira-api.sh                # Jira REST: sprint issues, worklog POST
├── calendar-api.sh              # Bash wrapper → Python helper
├── tui.sh                     # gum screens, blue theme, GCash banner
└── assets/
    └── gcash-banner.txt       # ASCII art

scripts/
└── google_calendar.py         # OAuth flow, token persist, event fetch

logs/                          # Session audit files (gitignored)

tests/
├── unit/
│   ├── test_logging.bats
│   ├── test_config.bats
│   └── test_event_filter.bats
└── integration/
    └── test_dry_run.bats
```

**Structure Decision**: Single CLI project at repo root. Bash owns UX orchestration and
Jira integration; Python isolated to Google OAuth/Calendar complexity. Shared `lib/`
modules satisfy constitution logging/confirmation requirements.

## Complexity Tracking

> No violations — table intentionally empty.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
