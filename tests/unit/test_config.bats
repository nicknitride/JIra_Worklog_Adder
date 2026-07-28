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
EOF
    config_load_dotenv "$WORKLOG_ENV_FILE"
    run config_validate
    [[ "$status" -eq 0 ]]
    [[ "$JIRA_LOGGING_LABEL" == DLV-133* ]]
}

@test "config_compute_logging_label follows DLV-133 pattern" {
    label="$(config_compute_logging_label)"
    [[ "$label" =~ ^DLV-133\ [0-9]{4}-[A-Za-z]+$ ]]
}
