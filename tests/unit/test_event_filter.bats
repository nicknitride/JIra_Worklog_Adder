#!/usr/bin/env bats
# Unit tests for calendar event filtering in lib/calendar-api.sh

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    # shellcheck source=lib/logging.sh
    source "${PROJECT_ROOT}/lib/logging.sh"
    WORKLOG_LOG_DIR="${BATS_TEST_TMPDIR}/logs"
    worklog_init_session_log
    # shellcheck source=lib/config.sh
    source "${PROJECT_ROOT}/lib/config.sh"
    # shellcheck source=lib/calendar-api.sh
    source "${PROJECT_ROOT}/lib/calendar-api.sh"
    FIXTURE="${BATS_TEST_TMPDIR}/events.json"
    cat > "$FIXTURE" <<'EOF'
{
  "events": [
    {"id": "1", "title": "Standup", "startTime": "2026-07-09T09:00:00+08:00", "endTime": "2026-07-09T09:30:00+08:00", "durationMinutes": 30, "responseStatus": "accepted", "allDay": false},
    {"id": "2", "title": "Declined mtg", "startTime": "2026-07-09T10:00:00+08:00", "endTime": "2026-07-09T11:00:00+08:00", "durationMinutes": 60, "responseStatus": "declined", "allDay": false},
    {"id": "3", "title": "All day offsite", "startTime": "2026-07-09", "endTime": "2026-07-09", "durationMinutes": 480, "responseStatus": "accepted", "allDay": true},
    {"id": "4", "title": "Maybe sync", "startTime": "2026-07-09T14:00:00+08:00", "endTime": "2026-07-09T15:00:00+08:00", "durationMinutes": 60, "responseStatus": "tentative", "allDay": false}
  ]
}
EOF
}

@test "calendar_filter_events excludes declined events" {
    filtered="$(calendar_filter_events "$(cat "$FIXTURE")")"
    count="$(printf '%s' "$filtered" | jq 'length')"
    [[ "$count" -eq 3 ]]
    ! printf '%s' "$filtered" | jq -e '.[] | select(.title == "Declined mtg")' >/dev/null
}

@test "calendar_filter_events flags all-day events with ALL_DAY warning" {
    filtered="$(calendar_filter_events "$(cat "$FIXTURE")")"
    warning="$(printf '%s' "$filtered" | jq -r '.[] | select(.title == "All day offsite") | .warning')"
    [[ "$warning" == "ALL_DAY" ]]
}

@test "calendar_filter_events flags tentative events with TENTATIVE warning" {
    filtered="$(calendar_filter_events "$(cat "$FIXTURE")")"
    warning="$(printf '%s' "$filtered" | jq -r '.[] | select(.title == "Maybe sync") | .warning')"
    [[ "$warning" == "TENTATIVE" ]]
}

@test "calendar_filter_events sets selected false by default" {
    filtered="$(calendar_filter_events "$(cat "$FIXTURE")")"
    selected="$(printf '%s' "$filtered" | jq -r '.[0].selected')"
    [[ "$selected" == "false" ]]
}
