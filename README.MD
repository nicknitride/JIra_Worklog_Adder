# Jira Calendar Worklog Automater

Author Note (nicknitride): Made mostly for convenience, UI/UX needs improvement 

An interactive terminal tool for turning Google Calendar events into Jira worklogs.
It connects to Jira Cloud and Google Calendar, lets you choose viable worklogging
days, select calendar events, map each event to a Jira ticket bucket, preview the
result, and submit the worklogs only after confirmation.

The TUI uses a blue GCash-inspired theme, shows the configured Jira bucket subtasks,
and writes a timestamped audit trail for every session under `logs/`.

## What This Tool Does

- Loads credentials and Jira context from a local `.env` file.
- Validates your Jira Cloud account with an Atlassian API token.
- Uses Google OAuth to read calendar events from one calendar.
- Defaults the day picker to the current Monday-Sunday week.
- Excludes declined and cancelled calendar events.
- Includes tentative and all-day events with warnings.
- Lists subtasks under a Jira parent issue as selectable worklog buckets.
- Optionally lists subtasks under a second "guild board" parent issue.
- Lets you manually enter a Jira issue key when the ticket is not listed.
- Uses the calendar event title as the Jira worklog comment.
- Uses the calendar event duration as the Jira worklog duration.
- Requires confirmation before saving a Google refresh token or submitting worklogs.
- Supports `--dry-run` so you can preview the flow without creating Jira worklogs.

## Requirements

Install these tools before running the script:

| Tool | Why it is needed | macOS install |
| --- | --- | --- |
| Bash | Runs the TUI scripts | Included with macOS; Bash 5 can be installed with `brew install bash` |
| `curl` | Calls Jira REST APIs | Included with macOS |
| `jq` | Reads and builds JSON | `brew install jq` |
| `gum` | Provides the terminal UI controls | `brew install gum` |
| Python 3.11+ | Runs the Google Calendar helper | `brew install python` |
| Google Python libraries | OAuth and Calendar API access | `pip3 install -r scripts/requirements.txt` |
| Bats | Optional, only for tests | `brew install bats-core` |

For Linux, install the same command-line tools with your package manager, then run
`pip3 install -r scripts/requirements.txt`.

## Quick Start

```bash
cp .env.example .env
pip3 install -r scripts/requirements.txt
./worklog-tui.sh --dry-run
```

Fill in `.env` before the dry run can connect to Jira or Google.

## Environment Setup

The tool reads configuration from `.env` in the project root. Start by copying the
template:

```bash
cp .env.example .env
```

Do not commit `.env`. It contains personal credentials and is already ignored by
`.gitignore`.

### Required `.env` Variables

| Variable | Example | Where to get it |
| --- | --- | --- |
| `ATLASSIAN_EMAIL` | `you@example.com` | The email address for your Jira Cloud account |
| `ATLASSIAN_API_TOKEN` | `ATATT...` | Atlassian account API token |
| `ATLASSIAN_BASE_URL` | `https://myntfintech.atlassian.net` | Your Jira Cloud site URL |
| `GOOGLE_CLIENT_ID` | `123456.apps.googleusercontent.com` | Google Cloud OAuth client |
| `GOOGLE_CLIENT_SECRET` | `GOCSPX-...` | Google Cloud OAuth client |
| `JIRA_BUCKET_PARENT` | `https://myntfintech.atlassian.net/browse/TRIBE06-67802` | Jira parent issue whose subtasks should be used as worklog buckets |

### Optional `.env` Variables

| Variable | Default | What it does |
| --- | --- | --- |
| `JIRA_GUILD_BOARD` | Empty | Optional second Jira parent issue. Its subtasks appear in orange in the picker. |
| `JIRA_PROJECT_KEY` | `TRIBE06` | Project key used for defaults and examples. |
| `GOOGLE_CALENDAR_ID` | `primary` | Calendar ID to read. Use `primary` for your main calendar. |
| `GOOGLE_REFRESH_TOKEN` | Empty | Auto-populated after first successful Google OAuth login. |
| `GOOGLE_OAUTH_PORT` | `8080` | Local callback port for Google OAuth. |
| `TZ` | System timezone | Timezone for week/day boundaries and Jira worklog start times. |

Runtime-only options:

| Variable | What it does |
| --- | --- |
| `SPECIFY_VERBOSE=1` | Same as running `./worklog-tui.sh --verbose`. |
| `WORKLOG_LOG_DIR=/path/to/logs` | Overrides the default `./logs` audit folder. |

## Jira Setup

### 1. Create an Atlassian API Token

1. Open your Atlassian account API token page: `https://id.atlassian.com/manage-profile/security/api-tokens`
2. Create a new API token.
3. Copy the token into `.env` as `ATLASSIAN_API_TOKEN`.
4. Set `ATLASSIAN_EMAIL` to the same email address you use to sign in to Jira.
5. Set `ATLASSIAN_BASE_URL` to your Jira Cloud site, without a trailing slash.

Example:

```dotenv
ATLASSIAN_EMAIL=you@example.com
ATLASSIAN_API_TOKEN=ATATT...
ATLASSIAN_BASE_URL=https://myntfintech.atlassian.net
```

### 2. Choose the Sprint Bucket Parent Link

The current implementation does not require a numeric Jira board ID. Instead, it
uses a parent Jira issue and loads that issue's subtasks as worklog buckets.

Open the Jira parent issue that contains the sprint/worklog bucket subtasks, then
copy either the browser URL or the issue key into `JIRA_BUCKET_PARENT`.

Accepted formats:

```dotenv
JIRA_BUCKET_PARENT=https://myntfintech.atlassian.net/browse/TRIBE06-67802
```

or:

```dotenv
JIRA_BUCKET_PARENT=TRIBE06-67802
```

When the tool starts, it fetches `TRIBE06-67802`, reads its subtasks, and shows
those subtasks as blue selectable bucket tickets.

### 3. Optionally Choose a Guild Board Parent Link

If you also need a second group of subtask tickets, set `JIRA_GUILD_BOARD`.
Those subtasks appear separately in orange.

Accepted formats:

```dotenv
JIRA_GUILD_BOARD=https://myntfintech.atlassian.net/browse/DEVELOPMNT-15646
```

or:

```dotenv
JIRA_GUILD_BOARD=DEVELOPMNT-15646
```

Leave `JIRA_GUILD_BOARD` commented out or empty if you only want the main sprint
bucket list.

### 4. Jira Permissions Needed

Your Jira account must be able to:

- Read the configured parent issue.
- Read subtasks under that parent issue.
- Browse the tickets you want to log work against.
- Add worklogs to the target Jira issues.

If the tool can connect but shows no subtasks, confirm that the configured parent
issue has visible subtasks and that your account has permission to browse them.

## Google Calendar Setup

### 1. Create Google OAuth Credentials

1. Open Google Cloud Console.
2. Create or select a project.
3. Enable the Google Calendar API for that project.
4. Configure the OAuth consent screen.
5. Create an OAuth client ID for a desktop app or installed app.
6. Copy the client ID and client secret into `.env`.

Example:

```dotenv
GOOGLE_CLIENT_ID=1234567890-example.apps.googleusercontent.com
GOOGLE_CLIENT_SECRET=GOCSPX-example
GOOGLE_CALENDAR_ID=primary
```

The tool requests read-only Calendar access with this OAuth scope:

```text
https://www.googleapis.com/auth/calendar.readonly
```

### 2. First-Run OAuth

On the first run, leave `GOOGLE_REFRESH_TOKEN` unset. The tool will:

1. Open a browser login flow.
2. Start a local callback server on `http://localhost:8080/` by default.
3. Ask whether to save the returned refresh token to `.env`.
4. Use that refresh token for future runs.

If port `8080` is already in use, choose another port:

```dotenv
GOOGLE_OAUTH_PORT=8090
```

If your Google OAuth client requires explicit redirect URIs, add:

```text
http://localhost:8080/
```

Use your chosen `GOOGLE_OAUTH_PORT` if you changed it.

### 3. Calendar ID

Use this for your primary calendar:

```dotenv
GOOGLE_CALENDAR_ID=primary
```

For another calendar, use that calendar's ID from Google Calendar settings. Shared
calendar IDs often look like an email address or a long `group.calendar.google.com`
identifier.

## Example `.env`

```dotenv
# Jira Cloud
ATLASSIAN_EMAIL=you@example.com
ATLASSIAN_API_TOKEN=ATATT...
ATLASSIAN_BASE_URL=https://myntfintech.atlassian.net

# Google OAuth (Calendar read-only)
GOOGLE_CLIENT_ID=1234567890-example.apps.googleusercontent.com
GOOGLE_CLIENT_SECRET=GOCSPX-example
# GOOGLE_REFRESH_TOKEN is added by the tool after first OAuth login

# Worklog bucket parent - issue key or browse URL; subtasks become buckets
JIRA_BUCKET_PARENT=https://myntfintech.atlassian.net/browse/TRIBE06-67802

# Optional second parent; subtasks are shown as guild board tickets
# JIRA_GUILD_BOARD=https://myntfintech.atlassian.net/browse/DEVELOPMNT-15646

# Optional defaults
JIRA_PROJECT_KEY=TRIBE06
GOOGLE_CALENDAR_ID=primary
GOOGLE_OAUTH_PORT=8080
TZ=Asia/Manila
```

## Running the Tool

Preview the flow without submitting Jira worklogs:

```bash
./worklog-tui.sh --dry-run
```

Run the normal interactive flow:

```bash
./worklog-tui.sh
```

Enable verbose shell tracing:

```bash
./worklog-tui.sh --verbose
```

Show help:

```bash
./worklog-tui.sh --help
```

## Normal Workflow

1. The tool validates `.env`.
2. It creates a timestamped log file under `logs/`.
3. It validates Jira authentication.
4. It ensures Google Calendar authentication.
5. It loads subtasks from `JIRA_BUCKET_PARENT`.
6. It loads subtasks from `JIRA_GUILD_BOARD`, if configured.
7. It shows the available worklog tickets.
8. You select viable worklogging days.
9. It fetches eligible calendar events for those days.
10. You select calendar events to log.
11. You assign each event to a Jira ticket.
12. You review the submission preview.
13. You confirm before Jira worklogs are created.

Calendar event duration becomes the Jira worklog duration. Calendar event title
becomes the Jira worklog description.

## Audit Logs

Every run creates a session log under `logs/`, for example:

```text
logs/2026-07-09T12-30-00-session.txt
```

Logs include:

- Session start and end.
- Config validation outcomes.
- Jira and Google API steps.
- Selected days.
- Selected events.
- Ticket assignments.
- Submission results.
- Dry-run markers when `--dry-run` is used.

Secret values are redacted from audit output.

To write logs somewhere else:

```bash
WORKLOG_LOG_DIR=/tmp/worklog-logs ./worklog-tui.sh --dry-run
```

## Testing

Run unit tests:

```bash
bats tests/unit/
```

Run integration dry-run tests:

```bash
bats tests/integration/
```

Run everything:

```bash
bats tests/unit/ tests/integration/
```

## Troubleshooting

| Symptom | What to check |
| --- | --- |
| `.env file not found` | Run `cp .env.example .env`, then fill in the required values. |
| Placeholder values detected | Replace `your-*` values in `.env` with real credentials and links. |
| Jira authentication failed with 401 | Confirm `ATLASSIAN_EMAIL` matches the token owner and regenerate `ATLASSIAN_API_TOKEN`. |
| Invalid `JIRA_BUCKET_PARENT` | Use a Jira issue key like `TRIBE06-67802` or a `/browse/TRIBE06-67802` URL. |
| No subtasks found | Confirm the parent issue has subtasks and your Jira account can browse them. |
| Google OAuth fails | Confirm Calendar API is enabled and the OAuth client ID/secret are correct. |
| OAuth redirect error | Add `http://localhost:8080/` to the OAuth redirect URIs, or match your custom `GOOGLE_OAUTH_PORT`. |
| `gum is required` | Install it with `brew install gum`. |
| Missing Google libraries | Run `pip3 install -r scripts/requirements.txt`. |
| Empty calendar event list | Confirm `GOOGLE_CALENDAR_ID`, selected viable days, and event attendance status. |
| Worklog submission fails | Confirm the target Jira ticket exists and your account can add worklogs. |

## Exit Codes

| Code | Meaning |
| --- | --- |
| `0` | Success |
| `1` | General error |
| `2` | Configuration error |
| `3` | Authentication error |
| `4` | User cancelled |
| `5` | API error |

## Project Layout

```text
worklog-tui.sh                  Main entry point
lib/config.sh                   .env loading and validation
lib/jira-api.sh                 Jira REST API calls and worklog submission
lib/calendar-api.sh             Bash wrapper around the Google helper
lib/tui.sh                      gum-based terminal UI
scripts/google_calendar.py      Google OAuth and Calendar event fetcher
scripts/requirements.txt        Python dependencies
tests/                          Bats tests
logs/                           Local audit logs, ignored by git
```

## Safety Notes

- Run `--dry-run` first whenever you change `.env` or Jira parent links.
- The tool does not submit worklogs until you confirm the final preview.
- The tool does not manually adjust event duration; edit your calendar event first
  if the duration should differ.
- All-day events are treated as 8 hours.
- Tickets outside the known bucket lists require an extra confirmation.
