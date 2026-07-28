#!/usr/bin/env bats
# Unit tests for jira_format_worklog_started

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    # shellcheck source=lib/logging.sh
    source "${PROJECT_ROOT}/lib/logging.sh"
    WORKLOG_LOG_DIR="${BATS_TEST_TMPDIR}/logs"
    worklog_init_session_log
    # shellcheck source=lib/jira-api.sh
    source "${PROJECT_ROOT}/lib/jira-api.sh"
}

@test "jira_format_worklog_started preserves local offset from calendar event" {
    local started
    started="$(jira_format_worklog_started "2026-07-06T11:00:00+08:00")"
    [[ "$started" == "2026-07-06T11:00:00.000+0800" ]]
}

@test "jira_format_worklog_started shifts UTC instant to local calendar date" {
    local started
    TZ=Asia/Manila started="$(jira_format_worklog_started "2026-07-06T18:30:00+00:00")"
    [[ "$started" == "2026-07-07T02:30:00.000+0800" ]]
}
