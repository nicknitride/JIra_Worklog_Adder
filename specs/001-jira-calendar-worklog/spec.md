# Feature Specification: Jira Calendar Worklog TUI

**Feature Branch**: `001-jira-calendar-worklog`

**Created**: 2026-07-09

**Status**: Draft

**Input**: User description: "A bash script that takes an atlassian API key and a google api key that allows me to log work in tickets I can specify based on calendar days I pick from (I click yes on the ones that are viable for logging), allow the user to select calendar events and then provide viable buckets in the current sprint. Example: TRIBE06-67802. Make it have a beautiful TUI with blue as a color scheme (GCash ASCII art if logos appear) and for transparency purposes log all actions performed in date-timestamped .txt files (create a logs folder)."

## Clarifications

### Session 2026-07-09

- Q: Where should API credentials be stored and how should they be labeled? → A: Use a `.env` file at project root with clearly labeled placeholder variables; user fills in their own keys.
- Q: How should Google Calendar authenticate? → A: First-run OAuth browser flow (Option C); refresh token cached locally after initial login for subsequent runs.
- Q: Are existing Google OAuth credentials sufficient? → A: Client ID and Client Secret are sufficient to start; refresh token is obtained on first run; Calendar API must be enabled on the Google Cloud project.
- Q: What is the default date range for viable-day selection? → A: Current calendar week (Monday through Sunday).
- Q: Which sprint tickets appear as worklog buckets? → A: All tickets in the current sprint, filtered to those labeled with the team's monthly logging label pattern `DLV-133 {YYYY}-{Month}` (e.g., `DLV-133 2026-July`).
- Q: What text is used for the Jira worklog description? → A: Calendar event title only.
- Q: Which calendar events appear in the selectable list? → A: Exclude declined/cancelled events; include all-day and tentative events with visual warnings in the TUI.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Connect and View Sprint Context (Priority: P1)

As a developer, I want to launch the tool with my Atlassian and Google API credentials
so that I can see the tickets available in my current sprint before logging any work.

**Why this priority**: Without valid API connections and sprint context, no worklogging
is possible. This is the foundation for all downstream flows.

**Independent Test**: Launch the tool with valid credentials and verify the current
sprint ticket list (e.g., issues from project TRIBE06) appears in the TUI without
requiring calendar or worklog actions.

**Acceptance Scenarios**:

1. **Given** a populated `.env` file with valid credentials, **When** the user launches
   the tool, **Then** the TUI displays a blue-themed welcome screen with GCash ASCII
   art and confirms both API connections succeeded.
2. **Given** a valid Atlassian connection, **When** the sprint context loads,
   **Then** the user sees ticket keys and summaries for all issues in the active
   sprint that carry the current month's team logging label (e.g., `DLV-133 2026-July`).
3. **Given** a missing or incomplete `.env` file, **When** the user launches the tool,
   **Then** the tool displays a clear error naming the missing variables and does not
   proceed to worklogging steps.
4. **Given** valid Atlassian credentials but no Google refresh token, **When** the
   user launches the tool for the first time, **Then** the tool opens a browser OAuth
   flow and caches the refresh token locally after successful login.
5. **Given** invalid credentials in `.env`, **When** the user launches the tool,
   **Then** the tool displays a clear error message and does not proceed to
   worklogging steps.

---

### User Story 2 - Select Viable Calendar Days (Priority: P2)

As a developer, I want to browse calendar days and mark which days are viable for
worklogging so that I only process days where I actually worked.

**Why this priority**: Day selection gates which calendar data is fetched and prevents
accidental worklogs on non-working days.

**Independent Test**: Present a date range in the TUI; user toggles days yes/no;
verify only "yes" days proceed to event selection.

**Acceptance Scenarios**:

1. **Given** connected Google Calendar access, **When** the day-selection screen
   loads, **Then** the TUI defaults to the current calendar week (Monday through
   Sunday) with a yes/no toggle for each day.
2. **Given** the default week view, **When** the user adjusts the date range,
   **Then** the TUI updates the listed days accordingly.
3. **Given** a day marked as not viable, **When** the user confirms day selection,
   **Then** that day is excluded from event fetching and worklog mapping.
4. **Given** a day marked as viable, **When** the user confirms day selection,
   **Then** calendar events for that day are loaded for review.

---

### User Story 3 - Select Events and Map to Sprint Tickets (Priority: P3)

As a developer, I want to select calendar events and assign each to a sprint ticket
bucket so that my Jira worklogs reflect how I actually spent my time.

**Why this priority**: This is the core value — translating calendar activity into
accurate Jira work entries tied to the current sprint.

**Independent Test**: Select one calendar event, assign it to a sprint ticket, confirm
the mapping preview, and verify the worklog is submitted only after explicit approval.

**Acceptance Scenarios**:

1. **Given** viable days with calendar events, **When** the user reviews events,
   **Then** each eligible event shows title, time range, and duration for selection;
   declined and cancelled events are hidden; all-day and tentative events display
   a visual warning badge.
2. **Given** selected events and loaded sprint tickets, **When** the user assigns
   an event to a ticket bucket, **Then** the TUI shows the event-to-ticket mapping
   including event title (worklog description), duration, and ticket key before
   any submission.
3. **Given** a completed mapping, **When** the user confirms submission, **Then**
   work is logged to the chosen Jira ticket with time derived from the calendar
   event duration and description set to the calendar event title.
4. **Given** a mapping ready for submission, **When** the user declines confirmation,
   **Then** no worklog is created and the user can revise selections.

---

### User Story 4 - Transparent Audit Trail (Priority: P4)

As a developer, I want every action recorded in timestamped log files so that I can
review exactly what the tool did for compliance and debugging.

**Why this priority**: Transparency and auditability are explicit user requirements
and align with project constitution principles on verification and logging.

**Independent Test**: Run a session that includes API calls, day toggles, event
selection, and a confirmed worklog; verify a date-stamped log file in `logs/` captures
each action with timestamps.

**Acceptance Scenarios**:

1. **Given** a new session, **When** the tool starts, **Then** a `logs/` folder is
   created if absent and a new date-timestamped `.txt` log file is opened for the
   session.
2. **Given** any user or system action (API call, selection, confirmation, error),
   **When** the action occurs, **Then** an entry is appended to the log file with
   an ISO-8601 timestamp and a description of the action and outcome.
3. **Given** a worklog submission, **When** the user confirms, **Then** the log
   records the ticket key, event title, duration, and submission result.

---

### Edge Cases

- What happens when a viable day has no calendar events? The tool shows an empty
  state and skips that day without error.
- What happens when the current sprint has no tickets matching the logging label?
  The tool displays a warning showing the expected label (e.g., `DLV-133 2026-July`)
  and allows manual ticket key entry as fallback.
- What happens when an API rate limit or network error occurs? The tool retries once,
  then shows a user-friendly error and logs the failure without partial submissions.
- What happens when a calendar event overlaps another? Both events remain selectable;
  the user is warned if total mapped time exceeds a reasonable daily threshold (8h).
- What happens when a ticket is no longer in the active sprint? The tool flags it and
  requires explicit user override to proceed.
- What happens when the user runs in dry-run mode? All steps execute except Jira
  worklog creation; the audit log marks entries as `[DRY-RUN]`.
- What happens when `.env` is missing? The tool exits with an error pointing the
  user to copy `.env.example` to `.env` and fill in required values.
- What happens when `.env` contains placeholder values? The tool detects unfilled
  placeholders and refuses to connect until real credentials are supplied.
- What happens on first Google OAuth run with only Client ID/Secret configured? The
  tool launches a browser consent flow and persists the refresh token to `.env` after
  user approval.
- What happens when the Google refresh token expires or is revoked? The tool prompts
  the user to re-authenticate via browser OAuth.
- What happens when a calendar event is declined or cancelled? The event is excluded
  from the selectable list and noted in the session audit log.
- What happens when a calendar event is all-day or tentative? The event appears in
  the list with a visual warning badge so the user can decide whether to log it.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The tool MUST load credentials from a `.env` file at project root at
  launch; a committed `.env.example` MUST provide labeled placeholders the user copies
  to `.env` and fills in.
- **FR-001a**: Required `.env` variables MUST be labeled as:
  `ATLASSIAN_EMAIL`, `ATLASSIAN_API_TOKEN`, `ATLASSIAN_BASE_URL`,
  `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`.
- **FR-001a2**: Google OAuth variable `GOOGLE_REFRESH_TOKEN` is populated
  automatically after first successful browser login; it MUST NOT be required in
  `.env.example` on initial setup.
- **FR-001b**: Optional `.env` variables MUST be labeled as:
  `JIRA_PROJECT_KEY` (default TRIBE06), `JIRA_BOARD_ID` (default 4912),
  `GOOGLE_CALENDAR_ID` (default `primary`),
  `JIRA_LOGGING_LABEL` (default auto-computed as `DLV-133 {YYYY}-{Month}` for the
  current date, e.g., `DLV-133 2026-July`).
- **FR-001c**: The tool MUST NOT commit or write secrets to audit logs; only variable
  names (not values) may appear in logs when reporting missing or invalid config.
- **FR-002**: The tool MUST authenticate against Atlassian and Google Calendar and
  report connection status in the TUI before proceeding.
- **FR-002a**: On first launch without a cached `GOOGLE_REFRESH_TOKEN`, the tool MUST
  initiate a browser-based Google OAuth consent flow and persist the refresh token
  to `.env` after successful authorization.
- **FR-003**: The tool MUST retrieve all issues in the user's current active sprint
  in project TRIBE06 (board context per example), filter them to those carrying the
  team logging label, and display the matches as selectable ticket buckets.
- **FR-003a**: The default logging label MUST follow the pattern `DLV-133 {YYYY}-{Month}`
  (full English month name), auto-computed from the current date unless overridden
  by `JIRA_LOGGING_LABEL` in `.env`.
- **FR-003b**: These labeled sprint tickets are the team's designated meeting/work
  logging buckets; the TUI MUST show label, key, and summary for each match.
- **FR-004**: The tool MUST default the viable-day date range to the current calendar
  week (Monday through Sunday, based on the user's local timezone) and allow the user
  to adjust the range before toggling days.
- **FR-004a**: The tool MUST present each day in the selected range with a yes/no
  viability toggle for worklogging.
- **FR-005**: The tool MUST fetch Google Calendar events only for days marked viable.
- **FR-005a**: The tool MUST exclude calendar events with declined or cancelled
  response status from the selectable list.
- **FR-005b**: The tool MUST include all-day and tentative events but display a
  distinct visual warning in the TUI for each.
- **FR-006**: The tool MUST allow the user to select one or more calendar events
  for worklog mapping.
- **FR-007**: The tool MUST allow the user to assign each selected event to a sprint
  ticket bucket (by ticket key such as TRIBE06-67802).
- **FR-008**: The tool MUST show a summary of all proposed worklog entries and require
  explicit user confirmation before submitting any work to Jira.
- **FR-009**: The tool MUST derive worklog duration from the calendar event's scheduled
  time range unless the user adjusts it during review.
- **FR-009a**: The tool MUST set the Jira worklog description to the calendar event
  title exactly as returned from Google Calendar (no prefix or suffix).
- **FR-010**: The tool MUST present a terminal user interface with a blue color scheme
  throughout all screens.
- **FR-011**: The tool MUST display GCash ASCII art on welcome and/or header screens
  where branding or logos appear.
- **FR-012**: The tool MUST create a `logs/` folder and write all session actions to
  a date-timestamped `.txt` file (e.g., `logs/2026-07-09T12-30-00-session.txt`).
- **FR-013**: The tool MUST support a dry-run mode that previews all actions without
  creating Jira worklogs.
- **FR-014**: The tool MUST allow manual ticket key entry when sprint ticket list
  is empty or the desired ticket is not listed.

### Constitution-Driven Requirements

Per `.specify/memory/constitution.md`:

- **CR-001**: Mutating actions (Jira worklog creation, log file writes) MUST require
  explicit user verification before execution; dry-run and read-only inspection do not.
- **CR-002**: The bash script MUST produce verbose step-level output; `--verbose` or
  `SPECIFY_VERBOSE=1` enables additional trace detail in the TUI footer or stderr.
- **CR-003**: All actions MUST be logged with ISO-8601 timestamps in the session
  log file, reflecting every API call, user selection, confirmation, and outcome.

### Key Entities

- **Calendar Event**: A scheduled block from Google Calendar with title, start time,
  end time, computed duration, and response status (accepted, tentative, declined,
  cancelled); declined/cancelled events are filtered out before display.
- **Sprint Ticket**: A Jira issue in the active sprint carrying the team logging label
  (e.g., `DLV-133 2026-July`); serves as a worklog destination bucket for meetings
  and calendar-based work.
- **Viable Day**: A calendar date the user marked as eligible for worklogging.
- **Worklog Mapping**: The association between a calendar event, a sprint ticket, the
  time to log, and the worklog description (calendar event title).
- **Audit Log Entry**: A timestamped record of an action performed during the session,
  stored in a session log file under `logs/`.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can complete worklogging for a single viable day (connect, select
  day, map events, confirm) in under 5 minutes.
- **SC-002**: 100% of Jira worklog submissions require explicit user confirmation;
  zero worklogs are created without approval.
- **SC-003**: 100% of session actions (API calls, selections, confirmations, errors)
  appear in the session audit log with timestamps.
- **SC-004**: Users successfully map at least one calendar event to a sprint ticket
  on first attempt in 90% of sessions (measured in user testing).
- **SC-005**: Invalid API credentials are detected at launch within 10 seconds with
  an actionable error message.

## Assumptions

- The user has Atlassian API access with permissions to read sprint issues and create
  worklogs on TRIBE06 project tickets.
- The user has Google Calendar API enabled on their Google Cloud project with OAuth
  credentials (Client ID + Client Secret); a refresh token is obtained on first run.
- Credentials are stored in a local `.env` file (gitignored); `.env.example` is
  committed with labeled placeholders for: `ATLASSIAN_EMAIL`, `ATLASSIAN_API_TOKEN`,
  `ATLASSIAN_BASE_URL`, `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`,
  `GOOGLE_REFRESH_TOKEN`, `JIRA_PROJECT_KEY`, `JIRA_BOARD_ID`, `GOOGLE_CALENDAR_ID`,
  `JIRA_LOGGING_LABEL`.
- `google_api_oauth_details.txt` or similar ad-hoc credential files MUST NOT be
  committed; users copy values into `.env` instead.
- "Current sprint" refers to the active sprint on the TRIBE06 board (board ID 4912
  per example URL); ticket buckets are all sprint issues labeled with the team's
  monthly logging label (`DLV-133 {YYYY}-{Month}`), not filtered by assignee.
- Worklog time defaults to the calendar event duration; worklog description defaults
  to the calendar event title; users may adjust duration during review.
- The tool runs locally on macOS/Linux terminals with sufficient size for TUI rendering.
- Secret values are never written to audit logs; only non-sensitive config names
  may be logged when reporting errors.
- Only one user's calendar and Jira account are supported per session (single-user tool).
- Default viable-day range is the current calendar week (Mon–Sun) in the user's local
  timezone; the user may expand or narrow the range before confirming.
- Weekend and holiday filtering is manual via the viable-day yes/no toggle (no auto-skip).
- Declined and cancelled calendar events are never shown; all-day and tentative events
  are shown with TUI warning badges.
