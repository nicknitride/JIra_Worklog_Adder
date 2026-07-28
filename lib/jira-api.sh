#!/usr/bin/env bash
# Jira REST API integration via curl + jq.

JIRA_BUCKET_TICKETS_JSON="[]"
JIRA_BUCKET_TICKET_KEYS=()
JIRA_BUCKET_PARENT_SUMMARY=""

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
    local response http_code body
    response="$(curl "${args[@]}" "$url")"
    http_code="$(printf '%s' "$response" | tail -n1)"
    body="$(printf '%s' "$response" | sed '$d')"
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

jira_fetch_bucket_tickets() {
    worklog_audit "INFO" "jira.bucket.load" "parent/${JIRA_BUCKET_PARENT_KEY}" "pending" ""
    local result http_code body count payload

    result="$(jira_fetch_with_retry GET "/rest/api/3/issue/${JIRA_BUCKET_PARENT_KEY}?fields=summary,subtasks")"
    http_code="$(printf '%s' "$result" | head -n1)"
    body="$(printf '%s' "$result" | tail -n +2)"

    if [[ "$http_code" != "200" ]]; then
        worklog_audit "ERROR" "jira.bucket.load" "parent/${JIRA_BUCKET_PARENT_KEY}" "failure" "HTTP ${http_code}"
        worklog_error "Failed to fetch parent issue ${JIRA_BUCKET_PARENT_KEY} (HTTP ${http_code})"
        return 5
    fi

    JIRA_BUCKET_PARENT_SUMMARY="$(printf '%s' "$body" | jq -r '.fields.summary // "unknown"')"
    worklog_audit "INFO" "jira.bucket.load" "parent/${JIRA_BUCKET_PARENT_KEY}" "success" \
        "summary=${JIRA_BUCKET_PARENT_SUMMARY}"

    JIRA_BUCKET_TICKETS_JSON="$(printf '%s' "$body" | jq '[.fields.subtasks[]? | {
        key: .key,
        summary: (.fields.summary // "(no summary)"),
        status: (.fields.status.name // "unknown"),
        inBucket: true
    }]')"

    count="$(printf '%s' "$JIRA_BUCKET_TICKETS_JSON" | jq 'length')"
    if [[ "$count" -eq 0 ]]; then
        payload="$(jq -n --arg parent "$JIRA_BUCKET_PARENT_KEY" \
            '{jql: ("parent = " + $parent + " ORDER BY key ASC"), maxResults: 100, fields: ["summary", "status"]}')"
        result="$(jira_fetch_with_retry POST "/rest/api/3/search" "$payload")"
        http_code="$(printf '%s' "$result" | head -n1)"
        body="$(printf '%s' "$result" | tail -n +2)"
        if [[ "$http_code" != "200" ]]; then
            worklog_audit "ERROR" "jira.bucket.filter" "subtasks/${JIRA_BUCKET_PARENT_KEY}" "failure" "HTTP ${http_code}"
            worklog_error "Failed to search subtasks for ${JIRA_BUCKET_PARENT_KEY} (HTTP ${http_code})"
            return 5
        fi
        JIRA_BUCKET_TICKETS_JSON="$(jira_normalize_bucket_tickets "$body")"
        count="$(printf '%s' "$JIRA_BUCKET_TICKETS_JSON" | jq 'length')"
    fi

    worklog_audit "INFO" "jira.bucket.filter" "subtasks/${JIRA_BUCKET_PARENT_KEY}" "success" "count=${count}"

    JIRA_BUCKET_TICKET_KEYS=()
    while IFS= read -r key; do
        [[ -n "$key" ]] && JIRA_BUCKET_TICKET_KEYS+=("$key")
    done < <(printf '%s' "$JIRA_BUCKET_TICKETS_JSON" | jq -r '.[].key')

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

jira_format_worklog_started() {
    local iso_datetime="$1"
    python3 - "$iso_datetime" <<'PY'
import sys
from datetime import datetime

dt = datetime.fromisoformat(sys.argv[1])
offset = dt.strftime("%z") or "+0000"
print(dt.strftime(f"%Y-%m-%dT%H:%M:%S.000{offset}"))
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
    worklog_error "Worklog submission failed for ${issue_key} (HTTP ${http_code})"
    return 5
}
