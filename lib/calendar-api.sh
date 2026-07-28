#!/usr/bin/env bash
# Bash wrapper around scripts/google_calendar.py.

CALENDAR_EVENTS_JSON="[]"
WORKLOG_PROJECT_ROOT="${WORKLOG_PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
CALENDAR_PYTHON="${WORKLOG_PROJECT_ROOT}/scripts/google_calendar.py"

calendar_run_oauth() {
    worklog_audit "INFO" "google.oauth.start" "browser" "pending" "port=${GOOGLE_OAUTH_PORT}"
    local result exit_code refresh_token
    result="$(GOOGLE_CLIENT_ID="$GOOGLE_CLIENT_ID" \
        GOOGLE_CLIENT_SECRET="$GOOGLE_CLIENT_SECRET" \
        python3 "$CALENDAR_PYTHON" oauth \
        --client-id "$GOOGLE_CLIENT_ID" \
        --client-secret "$GOOGLE_CLIENT_SECRET" \
        --port "$GOOGLE_OAUTH_PORT" 2>&1)"
    exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        worklog_audit "ERROR" "google.oauth.complete" "browser" "failure" "exit=${exit_code}"
        worklog_error "Google OAuth failed"
        return 3
    fi
    refresh_token="$(printf '%s' "$result" | tail -n1 | jq -r '.refresh_token // empty')"
    if [[ -z "$refresh_token" ]]; then
        worklog_audit "ERROR" "google.oauth.complete" "browser" "failure" "no refresh token"
        return 3
    fi
    worklog_audit "INFO" "google.oauth.complete" "browser" "success" "refresh token obtained"
    printf '%s' "$refresh_token"
    return 0
}

calendar_save_refresh_token() {
    local token="$1"
    if [[ "$WORKLOG_DRY_RUN" == "1" ]]; then
        worklog_audit "INFO" "google.oauth.token_saved" ".env" "dry_run" "skipped write"
        export GOOGLE_REFRESH_TOKEN="$token"
        return 0
    fi
    if ! confirm_action "Save Google refresh token to .env?"; then
        worklog_audit "INFO" "google.oauth.token_saved" ".env" "skipped" "user declined"
        return 1
    fi
    config_append_refresh_token "$token"
    worklog_audit "INFO" "google.oauth.token_saved" ".env" "success" "GOOGLE_REFRESH_TOKEN updated"
    return 0
}

calendar_ensure_google_auth() {
    if [[ -n "${GOOGLE_REFRESH_TOKEN:-}" ]] && ! config_is_placeholder "${GOOGLE_REFRESH_TOKEN:-}"; then
        worklog_audit "INFO" "google.auth.validate" "refresh_token" "success" "cached token present"
        return 0
    fi
    local token
    token="$(calendar_run_oauth)" || return 3
    calendar_save_refresh_token "$token" || return 4
    return 0
}

calendar_fetch_events_raw() {
    local date_from="$1"
    local date_to="$2"
    worklog_audit "INFO" "google.calendar.fetch" "${date_from}..${date_to}" "pending" ""
    local result exit_code
    result="$(GOOGLE_CLIENT_ID="$GOOGLE_CLIENT_ID" \
        GOOGLE_CLIENT_SECRET="$GOOGLE_CLIENT_SECRET" \
        GOOGLE_REFRESH_TOKEN="$GOOGLE_REFRESH_TOKEN" \
        python3 "$CALENDAR_PYTHON" events \
        --calendar-id "$GOOGLE_CALENDAR_ID" \
        --from "$date_from" \
        --to "$date_to" \
        --refresh-token "$GOOGLE_REFRESH_TOKEN" \
        --client-id "$GOOGLE_CLIENT_ID" \
        --client-secret "$GOOGLE_CLIENT_SECRET" 2>&1)"
    exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        local err_detail
        err_detail="$(printf '%s' "$result" | sed '/^exit=/d' | tail -n1 | tr -d '\n')"
        worklog_audit "ERROR" "google.calendar.fetch" "${date_from}..${date_to}" "failure" \
            "exit=${exit_code} detail=${err_detail:-unknown}"
        worklog_error "Failed to fetch calendar events: ${err_detail:-exit ${exit_code}}"
        return 3
    fi
    local json_line
    json_line="$(printf '%s' "$result" | tail -n1)"
    worklog_audit "INFO" "google.calendar.fetch" "${date_from}..${date_to}" "success" \
        "raw_count=$(printf '%s' "$json_line" | jq '.events | length')"
    printf '%s' "$json_line"
}

calendar_filter_events() {
    local raw_json="$1"
    local before after filtered
    before="$(printf '%s' "$raw_json" | jq '.events | length')"
    filtered="$(printf '%s' "$raw_json" | jq '
        [.events[] |
            if (.responseStatus == "declined" or .responseStatus == "cancelled") then empty
            else .
                + (if .allDay == true then {warning: "ALL_DAY"} elif .responseStatus == "tentative" then {warning: "TENTATIVE"} else {warning: null} end)
                + {selected: false}
            end
        ]')"
    after="$(printf '%s' "$filtered" | jq 'length')"
    worklog_audit "INFO" "google.calendar.filter" "events" "success" "before=${before} after=${after}"
    printf '%s' "$filtered"
}

calendar_fetch_events_for_range() {
    local date_from="$1"
    local date_to="$2"
    local raw filtered
    raw="$(calendar_fetch_events_raw "$date_from" "$date_to")" || return 3
    filtered="$(calendar_filter_events "$raw")"
    CALENDAR_EVENTS_JSON="$filtered"
    printf '%s' "$filtered"
}

calendar_fetch_events_for_days() {
    local -a viable_dates=("$@")
    if [[ ${#viable_dates[@]} -eq 0 ]]; then
        CALENDAR_EVENTS_JSON="[]"
        return 0
    fi
    local sorted_from sorted_to
    sorted_from="$(printf '%s\n' "${viable_dates[@]}" | sort | head -n1)"
    sorted_to="$(printf '%s\n' "${viable_dates[@]}" | sort | tail -n1)"
    local all_events
    all_events="$(calendar_fetch_events_for_range "$sorted_from" "$sorted_to")" || return 3
    # Filter to only events on viable dates (by local date prefix)
    local filtered
    filtered="$(printf '%s' "$all_events" | jq --argjson dates "$(printf '%s\n' "${viable_dates[@]}" | jq -R . | jq -s .)" '
        [.[] | select(.startTime[0:10] as $d | $dates | index($d))]
    ')"
    CALENDAR_EVENTS_JSON="$filtered"
    printf '%s' "$filtered"
}

# Export filter function for unit tests (source with args)
calendar_filter_events_from_file() {
    calendar_filter_events "$(cat "$1")"
}
