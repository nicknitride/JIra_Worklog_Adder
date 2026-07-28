#!/usr/bin/env bash
# ISO-8601 audit logging with dual-channel output (stderr + session file).

WORKLOG_LOG_DIR="${WORKLOG_LOG_DIR:-./logs}"
WORKLOG_SESSION_LOG=""
WORKLOG_DRY_RUN="${WORKLOG_DRY_RUN:-0}"

# Sensitive variable names whose values must never appear in logs.
WORKLOG_SECRET_VARS="ATLASSIAN_API_TOKEN GOOGLE_CLIENT_SECRET GOOGLE_REFRESH_TOKEN GOOGLE_CLIENT_ID"

worklog_timestamp() {
    date '+%Y-%m-%dT%H:%M:%S%z'
}

worklog_redact() {
    local message="$1"
    local var val
    for var in $WORKLOG_SECRET_VARS; do
        eval "val=\${${var}:-}"
        if [[ -n "$val" ]]; then
            message="${message//"$val"/"[REDACTED:$var]"}"
        fi
    done
    # Redact common placeholder patterns
    message="$(printf '%s' "$message" | sed -E \
        's/(your-[a-z-]+|ATATT[a-zA-Z0-9_-]+|ya29\.[a-zA-Z0-9_-]+)/[REDACTED]/g')"
    printf '%s' "$message"
}

worklog_init_session_log() {
    local log_dir="${WORKLOG_LOG_DIR}"
    mkdir -p "$log_dir"
    local ts
    ts="$(date '+%Y-%m-%dT%H-%M-%S')"
    WORKLOG_SESSION_LOG="${log_dir}/${ts}-session.txt"
    touch "$WORKLOG_SESSION_LOG"
    worklog_audit "INFO" "session.start" "logs" "success" "session log initialized"
}

worklog_audit() {
    local level="$1"
    local action="$2"
    local target="$3"
    local outcome="$4"
    local detail="${5:-}"
    local ts
    ts="$(worklog_timestamp)"
    detail="$(worklog_redact "$detail")"
    local dry_tag=""
    [[ "$WORKLOG_DRY_RUN" == "1" ]] && dry_tag=" [DRY-RUN]"
    local line="[${ts}] ${level} action=${action} target=${target} outcome=${outcome}${dry_tag}"
    [[ -n "$detail" ]] && line="${line} detail=${detail}"
    if [[ -n "$WORKLOG_SESSION_LOG" ]]; then
        printf '%s\n' "$line" >> "$WORKLOG_SESSION_LOG"
    fi
    worklog_progress "$level" "$action" "$outcome" "$detail"
}

worklog_progress() {
    local level="$1"
    local action="$2"
    local outcome="$3"
    local detail="${4:-}"
    detail="$(worklog_redact "$detail")"
    if [[ -n "$detail" ]]; then
        printf 'INFO: %s → %s (%s)\n' "$action" "$outcome" "$detail" >&2
    else
        printf 'INFO: %s → %s\n' "$action" "$outcome" >&2
    fi
}

worklog_error() {
    local message="$1"
    message="$(worklog_redact "$message")"
    printf 'ERROR: %s\n' "$message" >&2
    worklog_audit "ERROR" "system.error" "stderr" "failure" "$message"
}

worklog_debug() {
    local action="$1"
    local detail="${2:-}"
    worklog_audit "DEBUG" "$action" "debug" "success" "$detail"
}
