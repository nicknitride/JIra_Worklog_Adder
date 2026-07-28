#!/usr/bin/env bash
# Jira REST API integration via curl + jq.

JIRA_BUCKET_TICKETS_JSON="[]"
JIRA_BUCKET_TICKET_KEYS=()
JIRA_BUCKET_PARENT_SUMMARY=""
JIRA_GUILD_TICKETS_JSON="[]"
JIRA_GUILD_TICKET_KEYS=()
JIRA_GUILD_BOARD_SUMMARY=""
JIRA_LAST_CURL_ERROR=""
JIRA_LAST_HTTP_CODE=""

jira_curl() {
    local method="$1"
    local path="$2"
    local data="${3:-}"
    local url="${ATLASSIAN_BASE_URL}${path}"
    local auth
    auth="$(printf '%s:%s' "$ATLASSIAN_EMAIL" "$ATLASSIAN_API_TOKEN" | base64 | tr -d '\n')"
    local args=(-sS -w '\n%{http_code}' -X "$method" -H "Authorization: Basic ${auth}" \
        -H "Accept: application/json" -H "Content-Type: application/json")
    if [[ -n "$data" ]]; then
        args+=(-d "$data")
    fi
    local response http_code body curl_exit curl_stderr_file
    JIRA_LAST_CURL_ERROR=""
    JIRA_LAST_HTTP_CODE=""
    curl_stderr_file="$(mktemp "${TMPDIR:-/tmp}/worklog-jira-curl.XXXXXX")"
    curl_exit=0
    response="$(curl "${args[@]}" "$url" 2>"$curl_stderr_file")" || curl_exit=$?
    if [[ -s "$curl_stderr_file" ]]; then
        JIRA_LAST_CURL_ERROR="$(tr '\n' ' ' < "$curl_stderr_file" | sed 's/[[:space:]]*$//')"
    fi
    rm -f "$curl_stderr_file"
    http_code="$(printf '%s' "$response" | tail -n1)"
    body="$(printf '%s' "$response" | sed '$d')"
    JIRA_LAST_HTTP_CODE="$http_code"
    if [[ "$curl_exit" -ne 0 || "$http_code" == "000" ]]; then
        worklog_audit "WARN" "jira.curl" "$path" "transport_error" \
            "curl_exit=${curl_exit} http=${http_code} err=${JIRA_LAST_CURL_ERROR:-none}"
    fi
    printf '%s\n' "$http_code"
    printf '%s' "$body"
}

jira_validate_auth() {
    worklog_audit "INFO" "jira.auth.validate" "myself" "pending" ""
    local result http_code body
    result="$(jira_curl GET "/rest/api/3/myself")"
    http_code="$(printf '%s' "$result" | head -n1)"
    body="$(printf '%s' "$result" | tail -n +2)"

    if [[ "$http_code" == "200" ]]; then
        local email
        email="$(printf '%s' "$body" | jq -r '.emailAddress // .displayName // "ok"')"
        worklog_audit "INFO" "jira.auth.validate" "myself" "success" "connected as ${email}"
        return 0
    fi
    if [[ "$http_code" == "401" ]]; then
        worklog_audit "ERROR" "jira.auth.validate" "myself" "failure" "HTTP 401 unauthorized"
        worklog_error "Jira authentication failed (401). Check ATLASSIAN_EMAIL and ATLASSIAN_API_TOKEN."
        return 3
    fi
    worklog_audit "ERROR" "jira.auth.validate" "myself" "failure" "HTTP ${http_code}"
    worklog_error "Jira authentication failed with HTTP ${http_code}"
    return 3
}

jira_fetch_with_retry() {
    local method="$1"
    local path="$2"
    local data="${3:-}"
    local result http_code body
    result="$(jira_curl "$method" "$path" "$data")"
    http_code="$(printf '%s' "$result" | head -n1)"
    body="$(printf '%s' "$result" | tail -n +2)"
    if [[ "$http_code" == "429" ]]; then
        worklog_audit "WARN" "jira.rate_limit" "$path" "retry" "waiting 2s"
        sleep 2
        result="$(jira_curl "$method" "$path" "$data")"
        http_code="$(printf '%s' "$result" | head -n1)"
        body="$(printf '%s' "$result" | tail -n +2)"
    fi
    printf '%s\n' "$http_code"
    printf '%s' "$body"
}

jira_normalize_bucket_tickets() {
    local body="$1"
    printf '%s' "$body" | jq '[.issues[]? | {
        key: .key,
        summary: (.fields.summary // "(no summary)"),
        status: (.fields.status.name // "unknown"),
        inBucket: true
    }]'
}

jira_fetch_subtasks_for_parent() {
    local parent_key="$1"
    local audit_label="${2:-subtasks/${parent_key}}"
    local result http_code body count payload tickets_json parent_summary

    worklog_audit "INFO" "jira.subtasks.load" "$audit_label" "pending" "parent=${parent_key}"
    result="$(jira_fetch_with_retry GET "/rest/api/3/issue/${parent_key}?fields=summary,subtasks")"
    http_code="$(printf '%s' "$result" | head -n1)"
    body="$(printf '%s' "$result" | tail -n +2)"

    if [[ "$http_code" != "200" ]]; then
        worklog_audit "ERROR" "jira.subtasks.load" "$audit_label" "failure" "HTTP ${http_code}"
        worklog_error "Failed to fetch parent issue ${parent_key} (HTTP ${http_code})"
        return 5
    fi

    parent_summary="$(printf '%s' "$body" | jq -r '.fields.summary // "unknown"')"
    worklog_audit "INFO" "jira.subtasks.load" "$audit_label" "success" "summary=${parent_summary}"

    tickets_json="$(printf '%s' "$body" | jq '[.fields.subtasks[]? | {
        key: .key,
        summary: (.fields.summary // "(no summary)"),
        status: (.fields.status.name // "unknown"),
        inBucket: true
    }]')"

    count="$(printf '%s' "$tickets_json" | jq 'length')"
    if [[ "$count" -eq 0 ]]; then
        payload="$(jq -n --arg parent "$parent_key" \
            '{jql: ("parent = " + $parent + " ORDER BY key ASC"), maxResults: 100, fields: ["summary", "status"]}')"
        result="$(jira_fetch_with_retry POST "/rest/api/3/search" "$payload")"
        http_code="$(printf '%s' "$result" | head -n1)"
        body="$(printf '%s' "$result" | tail -n +2)"
        if [[ "$http_code" != "200" ]]; then
            worklog_audit "ERROR" "jira.subtasks.filter" "$audit_label" "failure" "HTTP ${http_code}"
            worklog_error "Failed to search subtasks for ${parent_key} (HTTP ${http_code})"
            return 5
        fi
        tickets_json="$(jira_normalize_bucket_tickets "$body")"
        count="$(printf '%s' "$tickets_json" | jq 'length')"
    fi

    worklog_audit "INFO" "jira.subtasks.filter" "$audit_label" "success" "count=${count}"
    printf '%s\n%s' "$parent_summary" "$tickets_json"
    return 0
}

jira_fetch_bucket_tickets() {
    local fetched parent_summary
    fetched="$(jira_fetch_subtasks_for_parent "$JIRA_BUCKET_PARENT_KEY" "bucket/${JIRA_BUCKET_PARENT_KEY}")" || return 5
    parent_summary="$(printf '%s' "$fetched" | head -n1)"
    JIRA_BUCKET_PARENT_SUMMARY="$parent_summary"
    JIRA_BUCKET_TICKETS_JSON="$(printf '%s' "$fetched" | tail -n +2)"

    JIRA_BUCKET_TICKET_KEYS=()
    while IFS= read -r key; do
        [[ -n "$key" ]] && JIRA_BUCKET_TICKET_KEYS+=("$key")
    done < <(printf '%s' "$JIRA_BUCKET_TICKETS_JSON" | jq -r '.[].key')

    return 0
}

jira_fetch_guild_board_tickets() {
    if [[ -z "${JIRA_GUILD_BOARD_KEY:-}" ]]; then
        JIRA_GUILD_TICKETS_JSON="[]"
        JIRA_GUILD_TICKET_KEYS=()
        JIRA_GUILD_BOARD_SUMMARY=""
        return 0
    fi

    local fetched parent_summary
    fetched="$(jira_fetch_subtasks_for_parent "$JIRA_GUILD_BOARD_KEY" "guild/${JIRA_GUILD_BOARD_KEY}")" || return 5
    parent_summary="$(printf '%s' "$fetched" | head -n1)"
    JIRA_GUILD_BOARD_SUMMARY="$parent_summary"
    JIRA_GUILD_TICKETS_JSON="$(printf '%s' "$fetched" | tail -n +2)"

    JIRA_GUILD_TICKET_KEYS=()
    while IFS= read -r key; do
        [[ -n "$key" ]] && JIRA_GUILD_TICKET_KEYS+=("$key")
    done < <(printf '%s' "$JIRA_GUILD_TICKETS_JSON" | jq -r '.[].key')

    return 0
}

jira_ticket_in_buckets() {
    local ticket_key="$1"
    local key
    for key in "${JIRA_BUCKET_TICKET_KEYS[@]}"; do
        [[ "$key" == "$ticket_key" ]] && return 0
    done
    return 1
}

jira_ticket_in_guild_board() {
    local ticket_key="$1"
    local key
    for key in "${JIRA_GUILD_TICKET_KEYS[@]}"; do
        [[ "$key" == "$ticket_key" ]] && return 0
    done
    return 1
}

jira_ticket_in_known_lists() {
    local ticket_key="$1"
    jira_ticket_in_buckets "$ticket_key" && return 0
    jira_ticket_in_guild_board "$ticket_key" && return 0
    return 1
}

jira_format_worklog_started() {
    local iso_datetime="$1"
    python3 - "$iso_datetime" <<'PY'
import os
import sys
from datetime import datetime, timezone
from zoneinfo import ZoneInfo

local_tz = ZoneInfo(os.environ.get("TZ", "Asia/Manila"))
dt = datetime.fromisoformat(sys.argv[1])
if dt.tzinfo is None:
    dt = dt.replace(tzinfo=timezone.utc)
local_dt = dt.astimezone(local_tz)
offset = local_dt.strftime("%z") or "+0000"
print(local_dt.strftime(f"%Y-%m-%dT%H:%M:%S.000{offset}"))
PY
}

jira_build_worklog_payload() {
    local title="$1"
    local started="$2"
    local duration_minutes="$3"
    local seconds=$((duration_minutes * 60))
    jq -n \
        --arg title "$title" \
        --arg started "$started" \
        --argjson seconds "$seconds" \
        '{
            comment: {
                type: "doc",
                version: 1,
                content: [{
                    type: "paragraph",
                    content: [{ type: "text", text: $title }]
                }]
            },
            started: $started,
            timeSpentSeconds: $seconds
        }'
}

jira_submit_worklog() {
    local issue_key="$1"
    local title="$2"
    local started="$3"
    local duration_minutes="$4"

    if [[ "$WORKLOG_DRY_RUN" == "1" ]]; then
        worklog_audit "INFO" "jira.worklog.dry_run" "$issue_key" "dry_run" \
            "title=${title} started=${started} duration=${duration_minutes}m"
        return 0
    fi

    worklog_audit "INFO" "jira.worklog.submit" "$issue_key" "pending" \
        "title=${title} started=${started} duration=${duration_minutes}m"

    local payload result http_code body
    payload="$(jira_build_worklog_payload "$title" "$started" "$duration_minutes")"
    result="$(jira_fetch_with_retry POST "/rest/api/3/issue/${issue_key}/worklog" "$payload")"
    http_code="$(printf '%s' "$result" | head -n1)"
    body="$(printf '%s' "$result" | tail -n +2)"

    if [[ "$http_code" == "201" ]]; then
        local wl_id
        wl_id="$(printf '%s' "$body" | jq -r '.id // "unknown"')"
        worklog_audit "INFO" "jira.worklog.submit" "$issue_key" "success" \
            "worklog_id=${wl_id} title=${title} started=${started} duration=${duration_minutes}m"
        return 0
    fi

    worklog_audit "ERROR" "jira.worklog.submit" "$issue_key" "failure" "HTTP ${http_code}"
    if [[ "$http_code" == "000" ]]; then
        worklog_error "Worklog submission failed for ${issue_key} (network error — no response from Jira).${JIRA_LAST_CURL_ERROR:+ ${JIRA_LAST_CURL_ERROR}}"
    else
        local err_msg
        err_msg="$(printf '%s' "$body" | jq -r '.errorMessages[0] // .errors | to_entries[0].value // empty' 2>/dev/null || true)"
        if [[ -n "$err_msg" ]]; then
            worklog_error "Worklog submission failed for ${issue_key} (HTTP ${http_code}): ${err_msg}"
        else
            worklog_error "Worklog submission failed for ${issue_key} (HTTP ${http_code})"
        fi
    fi
    return 5
}
