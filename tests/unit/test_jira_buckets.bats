#!/usr/bin/env bats
# Unit tests for lib/jira-api.sh bucket helpers

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    # shellcheck source=lib/logging.sh
    source "${PROJECT_ROOT}/lib/logging.sh"
    WORKLOG_LOG_DIR="${BATS_TEST_TMPDIR}/logs"
    worklog_init_session_log
    # shellcheck source=lib/jira-api.sh
    source "${PROJECT_ROOT}/lib/jira-api.sh"
}

@test "jira_normalize_bucket_tickets maps search results" {
    local body='{"issues":[{"key":"TRIBE06-1","fields":{"summary":"Standup","status":{"name":"Done"}}}]}'
    local result
    result="$(jira_normalize_bucket_tickets "$body")"
    [[ "$(printf '%s' "$result" | jq -r '.[0].key')" == "TRIBE06-1" ]]
    [[ "$(printf '%s' "$result" | jq -r '.[0].summary')" == "Standup" ]]
    [[ "$(printf '%s' "$result" | jq -r '.[0].inBucket')" == "true" ]]
}
