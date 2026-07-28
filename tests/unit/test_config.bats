#!/usr/bin/env bats
# Unit tests for lib/config.sh

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    # shellcheck source=lib/logging.sh
    source "${PROJECT_ROOT}/lib/logging.sh"
    WORKLOG_LOG_DIR="${BATS_TEST_TMPDIR}/logs"
    worklog_init_session_log
    # shellcheck source=lib/config.sh
    source "${PROJECT_ROOT}/lib/config.sh"
    WORKLOG_ENV_FILE="${BATS_TEST_TMPDIR}/.env"
}

@test "config_is_placeholder detects your- prefix values" {
    config_is_placeholder "your-api-token"
    config_is_placeholder "your-email@example.com"
}

@test "config_is_placeholder rejects real-looking values" {
    ! config_is_placeholder "real-token-value"
}

@test "config_validate fails on missing required variables" {
    cat > "$WORKLOG_ENV_FILE" <<EOF
ATLASSIAN_EMAIL=
ATLASSIAN_API_TOKEN=
ATLASSIAN_BASE_URL=
GOOGLE_CLIENT_ID=
GOOGLE_CLIENT_SECRET=
JIRA_BUCKET_PARENT=
EOF
    config_load_dotenv "$WORKLOG_ENV_FILE"
    run config_validate
    [[ "$status" -eq 2 ]]
}

@test "config_validate fails on placeholder values" {
    cat > "$WORKLOG_ENV_FILE" <<EOF
ATLASSIAN_EMAIL=your-email@example.com
ATLASSIAN_API_TOKEN=your-atlassian-api-token
ATLASSIAN_BASE_URL=https://myntfintech.atlassian.net
GOOGLE_CLIENT_ID=your-google-client-id
GOOGLE_CLIENT_SECRET=your-google-client-secret
JIRA_BUCKET_PARENT=your-jira-parent
EOF
    config_load_dotenv "$WORKLOG_ENV_FILE"
    run config_validate
    [[ "$status" -eq 2 ]]
}

@test "config_validate passes with valid values" {
    cat > "$WORKLOG_ENV_FILE" <<EOF
ATLASSIAN_EMAIL=user@mynt.xyz
ATLASSIAN_API_TOKEN=ATATTreal-token
ATLASSIAN_BASE_URL=https://myntfintech.atlassian.net
GOOGLE_CLIENT_ID=123456.apps.googleusercontent.com
GOOGLE_CLIENT_SECRET=GOCSPX-real-secret
JIRA_BUCKET_PARENT=https://myntfintech.atlassian.net/browse/TRIBE06-67802
EOF
    config_load_dotenv "$WORKLOG_ENV_FILE"
    run config_validate
    [[ "$status" -eq 0 ]]
    [[ "$JIRA_BUCKET_PARENT_KEY" == "TRIBE06-67802" ]]
}

@test "config_validate passes with optional guild board" {
    cat > "$WORKLOG_ENV_FILE" <<EOF
ATLASSIAN_EMAIL=user@mynt.xyz
ATLASSIAN_API_TOKEN=ATATTreal-token
ATLASSIAN_BASE_URL=https://myntfintech.atlassian.net
GOOGLE_CLIENT_ID=123456.apps.googleusercontent.com
GOOGLE_CLIENT_SECRET=GOCSPX-real-secret
JIRA_BUCKET_PARENT=https://myntfintech.atlassian.net/browse/TRIBE06-67802
JIRA_GUILD_BOARD=https://myntfintech.atlassian.net/browse/DEVELOPMNT-15646
EOF
    config_load_dotenv "$WORKLOG_ENV_FILE"
    run config_validate
    [[ "$status" -eq 0 ]]
    [[ "$JIRA_GUILD_BOARD_KEY" == "DEVELOPMNT-15646" ]]
}

@test "config_parse_jira_issue_ref accepts browse URL" {
    key="$(config_parse_jira_issue_ref "https://myntfintech.atlassian.net/browse/TRIBE06-67802")"
    [[ "$key" == "TRIBE06-67802" ]]
}

@test "config_parse_jira_issue_ref accepts issue key" {
    key="$(config_parse_jira_issue_ref "TRIBE06-67802")"
    [[ "$key" == "TRIBE06-67802" ]]
}

@test "config_current_week_range returns monday through sunday in order" {
    run bash -c 'source "'"${PROJECT_ROOT}"'/lib/config.sh"; config_current_week_range'
    [[ "$status" -eq 0 ]]
    local week_start="${output%% *}"
    local week_end="${output##* }"
    [[ "$week_start" < "$week_end" || "$week_start" == "$week_end" ]]
}
