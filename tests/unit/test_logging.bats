#!/usr/bin/env bats
# Unit tests for lib/logging.sh

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    # shellcheck source=lib/logging.sh
    source "${PROJECT_ROOT}/lib/logging.sh"
    WORKLOG_LOG_DIR="${BATS_TEST_TMPDIR}/logs"
    WORKLOG_DRY_RUN=0
    worklog_init_session_log
}

@test "worklog_init_session_log creates session file" {
    [[ -f "$WORKLOG_SESSION_LOG" ]]
    [[ -s "$WORKLOG_SESSION_LOG" ]]
}

@test "worklog_audit writes ISO-8601 timestamped entry" {
    worklog_audit "INFO" "test.action" "target" "success" "detail=test"
    grep -q 'action=test.action' "$WORKLOG_SESSION_LOG"
    grep -qE '\[[0-9]{4}-[0-9]{2}-[0-9]{2}T' "$WORKLOG_SESSION_LOG"
}

@test "worklog_redact removes secret values from messages" {
    ATLASSIAN_API_TOKEN="secret-token-xyz"
    local redacted
    redacted="$(worklog_redact "token=secret-token-xyz in log")"
    [[ "$redacted" != *"secret-token-xyz"* ]]
    [[ "$redacted" == *"REDACTED"* ]]
}

@test "dry-run tag appears in audit log when WORKLOG_DRY_RUN=1" {
    WORKLOG_DRY_RUN=1
    worklog_audit "INFO" "jira.worklog.dry_run" "TRIBE06-1" "dry_run" "test"
    grep -q '\[DRY-RUN\]' "$WORKLOG_SESSION_LOG"
}
