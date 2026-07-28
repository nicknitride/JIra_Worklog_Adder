# CLI Contract: worklog-tui

**Version**: 1.0.0 | **Feature**: 001-jira-calendar-worklog

## Entry Point

```bash
./worklog-tui.sh [OPTIONS]
```

## Options

| Flag | Env equivalent | Description |
|------|----------------|-------------|
| `--dry-run` | — | Preview all steps; no Jira worklogs or `.env` writes |
| `--verbose` | `SPECIFY_VERBOSE=1` | Enable `set -x` trace on stderr |
| `--help` | — | Show usage and exit 0 |
| `--version` | — | Show version and exit 0 |

## Environment Variables

### Required (in `.env`)

| Variable | Example | Description |
|----------|---------|-------------|
| `ATLASSIAN_EMAIL` | `user@mynt.xyz` | Jira Cloud account email |
| `ATLASSIAN_API_TOKEN` | `(secret)` | Jira API token from Atlassian account settings |
| `ATLASSIAN_BASE_URL` | `https://myntfintech.atlassian.net` | Jira Cloud instance URL |
| `GOOGLE_CLIENT_ID` | `(from Google Cloud Console)` | OAuth client ID |
| `GOOGLE_CLIENT_SECRET` | `(secret)` | OAuth client secret |

### Optional

| Variable | Default | Description |
|----------|---------|-------------|
| `JIRA_PROJECT_KEY` | `TRIBE06` | Jira project key |
| `JIRA_BOARD_ID` | `4912` | Agile board ID for sprint lookup |
| `GOOGLE_CALENDAR_ID` | `primary` | Calendar to read events from |
| `JIRA_LOGGING_LABEL` | `DLV-133 YYYY-Month` | Auto-computed monthly label |
| `GOOGLE_REFRESH_TOKEN` | — | Set automatically after first OAuth |
| `GOOGLE_OAUTH_PORT` | `8080` | Local redirect listener port |
| `TZ` | system | Timezone for week/day boundaries |

### Runtime (not in `.env`)

| Variable | Description |
|----------|-------------|
| `SPECIFY_VERBOSE` | `1` enables verbose trace |
| `WORKLOG_LOG_DIR` | Override log directory (default: `./logs`) |

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success (including dry-run completion) |
| 1 | General error |
| 2 | Configuration error (missing/invalid `.env`) |
| 3 | Authentication error (Jira or Google) |
| 4 | User cancelled at confirmation gate |
| 5 | API error after retry |

## User Interaction Contract

| Step | Input | Confirmation required |
|------|-------|----------------------|
| OAuth token save | Browser login | yes — before writing `GOOGLE_REFRESH_TOKEN` |
| Day viability toggles | y/n per day | no (selection only) |
| Event selection | multi-select | no |
| Ticket mapping | pick per event | no |
| Worklog submit | summary preview | **yes** — FR-008 |
| Dry-run | summary preview | yes to proceed preview |

## Output Channels

| Channel | Content |
|---------|---------|
| TUI (stdout) | gum-rendered screens, blue theme |
| stderr | Progress INFO, ERROR messages |
| `logs/*.txt` | Full audit trail with timestamps |
| stdout (JSON mode) | Not in v1 — reserved |

## `.env.example` Template

```dotenv
# Jira Cloud
ATLASSIAN_EMAIL=your-email@example.com
ATLASSIAN_API_TOKEN=your-atlassian-api-token
ATLASSIAN_BASE_URL=https://myntfintech.atlassian.net

# Google OAuth (Calendar read-only)
GOOGLE_CLIENT_ID=your-google-client-id
GOOGLE_CLIENT_SECRET=your-google-client-secret
# GOOGLE_REFRESH_TOKEN=  # Auto-populated after first login

# Optional — defaults shown
JIRA_PROJECT_KEY=TRIBE06
JIRA_BOARD_ID=4912
GOOGLE_CALENDAR_ID=primary
# JIRA_LOGGING_LABEL=DLV-133 2026-July
```
