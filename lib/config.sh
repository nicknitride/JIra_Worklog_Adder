#!/usr/bin/env bash
# Load and validate .env configuration.

WORKLOG_PROJECT_ROOT="${WORKLOG_PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
WORKLOG_ENV_FILE="${WORKLOG_ENV_FILE:-${WORKLOG_PROJECT_ROOT}/.env}"

# Exported config (populated by config_load)
export ATLASSIAN_EMAIL=""
export ATLASSIAN_API_TOKEN=""
export ATLASSIAN_BASE_URL=""
export GOOGLE_CLIENT_ID=""
export GOOGLE_CLIENT_SECRET=""
export GOOGLE_REFRESH_TOKEN=""
export JIRA_PROJECT_KEY="TRIBE06"
export JIRA_BOARD_ID="4912"
export GOOGLE_CALENDAR_ID="primary"
export JIRA_LOGGING_LABEL=""
export GOOGLE_OAUTH_PORT="${GOOGLE_OAUTH_PORT:-8080}"

config_is_placeholder() {
    local value="$1"
    [[ -z "$value" ]] && return 0
    case "$value" in
        your-*) return 0 ;;
        YOUR_*) return 0 ;;
        your-email@example.com) return 0 ;;
    esac
    return 1
}

config_compute_logging_label() {
    local month_name
    month_name="$(date '+%B')"
    printf 'DLV-133 %s-%s' "$(date '+%Y')" "$month_name"
}

config_load_dotenv() {
    local env_file="$1"
    if [[ ! -f "$env_file" ]]; then
        return 2
    fi
    # shellcheck disable=SC1090
    set -a
    source "$env_file"
    set +a
    return 0
}

config_validate() {
    local missing=()
    local placeholders=()
    local var val

    for var in ATLASSIAN_EMAIL ATLASSIAN_API_TOKEN ATLASSIAN_BASE_URL \
               GOOGLE_CLIENT_ID GOOGLE_CLIENT_SECRET; do
        eval "val=\${${var}:-}"
        if [[ -z "$val" ]]; then
            missing+=("$var")
        elif config_is_placeholder "$val"; then
            placeholders+=("$var")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        worklog_error "Missing required .env variables: ${missing[*]}"
        printf 'Copy .env.example to .env and fill in: %s\n' "${missing[*]}" >&2
        return 2
    fi

    if [[ ${#placeholders[@]} -gt 0 ]]; then
        worklog_error "Placeholder values detected in .env: ${placeholders[*]}"
        return 2
    fi

    # Strip trailing slash from base URL
    ATLASSIAN_BASE_URL="${ATLASSIAN_BASE_URL%/}"

    # Defaults for optional vars
    JIRA_PROJECT_KEY="${JIRA_PROJECT_KEY:-TRIBE06}"
    JIRA_BOARD_ID="${JIRA_BOARD_ID:-4912}"
    GOOGLE_CALENDAR_ID="${GOOGLE_CALENDAR_ID:-primary}"
    GOOGLE_OAUTH_PORT="${GOOGLE_OAUTH_PORT:-8080}"

    if [[ -z "${JIRA_LOGGING_LABEL:-}" ]]; then
        JIRA_LOGGING_LABEL="$(config_compute_logging_label)"
    fi

    export ATLASSIAN_EMAIL ATLASSIAN_API_TOKEN ATLASSIAN_BASE_URL
    export GOOGLE_CLIENT_ID GOOGLE_CLIENT_SECRET GOOGLE_REFRESH_TOKEN
    export JIRA_PROJECT_KEY JIRA_BOARD_ID GOOGLE_CALENDAR_ID JIRA_LOGGING_LABEL GOOGLE_OAUTH_PORT
    return 0
}

config_load() {
    if ! config_load_dotenv "$WORKLOG_ENV_FILE"; then
        worklog_error ".env file not found at ${WORKLOG_ENV_FILE}"
        printf 'Copy .env.example to .env and fill in your credentials.\n' >&2
        return 2
    fi
    config_validate
}

config_append_refresh_token() {
    local token="$1"
    local env_file="$WORKLOG_ENV_FILE"
    if grep -q '^GOOGLE_REFRESH_TOKEN=' "$env_file" 2>/dev/null; then
        if [[ "$(uname)" == "Darwin" ]]; then
            sed -i '' "s|^GOOGLE_REFRESH_TOKEN=.*|GOOGLE_REFRESH_TOKEN=${token}|" "$env_file"
        else
            sed -i "s|^GOOGLE_REFRESH_TOKEN=.*|GOOGLE_REFRESH_TOKEN=${token}|" "$env_file"
        fi
    else
        printf '\nGOOGLE_REFRESH_TOKEN=%s\n' "$token" >> "$env_file"
    fi
    export GOOGLE_REFRESH_TOKEN="$token"
}

config_current_week_range() {
    local tz="${TZ:-}"
    local monday sunday
    if [[ -n "$tz" ]]; then
        monday="$(TZ="$tz" date -v-monday '+%Y-%m-%d' 2>/dev/null || TZ="$tz" date -d 'monday this week' '+%Y-%m-%d')"
        sunday="$(TZ="$tz" date -v-sunday '+%Y-%m-%d' 2>/dev/null || TZ="$tz" date -d 'sunday this week' '+%Y-%m-%d')"
    else
        monday="$(date -v-monday '+%Y-%m-%d' 2>/dev/null || date -d 'monday this week' '+%Y-%m-%d')"
        sunday="$(date -v-sunday '+%Y-%m-%d' 2>/dev/null || date -d 'sunday this week' '+%Y-%m-%d')"
    fi
    printf '%s %s' "$monday" "$sunday"
}

config_dates_between() {
    local start="$1"
    local end="$2"
    local current="$start"
    local dates=()

    while [[ "$current" < "$end" || "$current" == "$end" ]]; do
        dates+=("$current")
        current="$(date -j -f '%Y-%m-%d' -v+1d "$current" '+%Y-%m-%d' 2>/dev/null \
            || date -d "$current + 1 day" '+%Y-%m-%d')"
        [[ ${#dates[@]} -gt 400 ]] && break
    done
    printf '%s\n' "${dates[@]}"
}

config_day_of_week() {
    local d="$1"
    date -j -f '%Y-%m-%d' "$d" '+%a' 2>/dev/null || date -d "$d" '+%a'
}
