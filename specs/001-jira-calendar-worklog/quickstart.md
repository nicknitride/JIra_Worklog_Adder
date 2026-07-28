# Quickstart: Jira Calendar Worklog TUI

**Feature**: 001-jira-calendar-worklog | **Date**: 2026-07-09

Validation guide for end-to-end feature verification. See [data-model.md](./data-model.md)
and [contracts/](./contracts/) for details.

## Prerequisites

| Tool | Install (macOS) |
|------|-----------------|
| bash 5+ | pre-installed or `brew install bash` |
| curl, jq | `brew install jq` |
| gum | `brew install gum` |
| python3 3.11+ | `brew install python` |
| Google libs | `pip3 install google-auth-oauthlib google-api-python-client` |
| bats (tests) | `brew install bats-core` |

## Setup

1. Copy environment template:
   ```bash
   cp .env.example .env
   ```

2. Fill `.env` with your credentials (see [cli-contract.md](./contracts/cli-contract.md)):
   - Jira: email, API token, base URL `https://myntfintech.atlassian.net`
   - Google: client ID and secret from Google Cloud Console
   - Ensure **Google Calendar API** is enabled

3. Confirm `.gitignore` excludes `.env` and `logs/`

## Scenario 1: Config validation (no APIs)

**Proves**: FR-001, SC-005, edge case missing `.env`

```bash
# Missing .env
mv .env .env.bak 2>/dev/null; ./worklog-tui.sh; echo "exit: $?"
mv .env.bak .env 2>/dev/null

# Expected: exit 2, error lists missing variables
```

## Scenario 2: Jira connection + sprint tickets

**Proves**: US1, FR-003, FR-003a

```bash
./worklog-tui.sh --dry-run
```

**Expected**:
- Blue welcome screen with GCash ASCII art
- Jira connection success message
- Sprint tickets listed with label matching `DLV-133 {current-month}`
- Audit log created in `logs/` with timestamped entries

## Scenario 3: Google OAuth first run

**Proves**: FR-002a, US1 scenario 4

1. Remove `GOOGLE_REFRESH_TOKEN` line from `.env`
2. Run `./worklog-tui.sh`
3. Browser opens for Google consent
4. Confirm saving token when prompted

**Expected**:
- `GOOGLE_REFRESH_TOKEN` appended to `.env` after confirmation
- Log entry `google.oauth.complete` without token value

## Scenario 4: Day selection + event filter

**Proves**: US2, FR-004, FR-005a/b

1. Run tool with valid credentials
2. Default week (Mon–Sun) displayed
3. Mark at least one day viable
4. Review events — declined/cancelled absent; all-day/tentative show warning badge

**Expected**:
- Only viable days fetch events
- Filter counts in audit log

## Scenario 5: Map event → ticket → confirm submit

**Proves**: US3, FR-008, FR-009a, SC-002

1. Select one calendar event
2. Assign to a sprint logging ticket (e.g. labeled `DLV-133 2026-July`)
3. Review preview (title, duration, ticket key)
4. Confirm submission

**Expected**:
- Jira worklog created with event title as description
- Duration matches calendar event
- Audit log records ticket key, title, duration, outcome

## Scenario 6: Dry-run mode

**Proves**: FR-013, CR-001

```bash
./worklog-tui.sh --dry-run
```

Complete flow through confirmation.

**Expected**:
- No Jira POST calls
- Log entries marked `[DRY-RUN]`
- Preview shows intended worklogs

## Scenario 7: Verbose + audit completeness

**Proves**: CR-002, CR-003, SC-003

```bash
./worklog-tui.sh --verbose --dry-run
```

**Expected**:
- `set -x` trace on stderr
- Every step in `logs/*.txt` with ISO-8601 timestamps
- No secret values in log file

## Automated Tests

```bash
# Unit tests (no live APIs)
bats tests/unit/

# Integration dry-run
bats tests/integration/
```

## Troubleshooting

| Symptom | Check |
|---------|-------|
| Jira 401 | Regenerate API token; verify email matches |
| No sprint tickets | Confirm active sprint exists; verify `JIRA_LOGGING_LABEL` |
| OAuth redirect error | Add `http://localhost:8080/` to Google OAuth redirect URIs |
| Empty calendar | Verify `GOOGLE_CALENDAR_ID`; check viable day toggles |
| gum not found | `brew install gum` |

## Next Step

Run `/speckit-tasks` to generate implementation tasks from this plan.
