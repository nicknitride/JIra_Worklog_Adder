#!/usr/bin/env bash
# Jira REST API integration via curl + jq.

JIRA_SPRINT_TICKETS_JSON="[]"
JIRA_SPRINT_TICKET_KEYS=()

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

jira_fetch_sprint_tickets() {
    worklog_audit "INFO" "jira.sprint.load" "board/${JIRA_BOARD_ID}" "pending" ""
    local result http_code body sprint_id
    result="$(jira_fetch_with_retry GET "/rest/agile/1.0/board/${JIRA_BOARD_ID}/sprint?state=active")"
    http_code="$(printf '%s' "$result" | head -n1)"
    body="$(printf '%s' "$result" | tail -n +2)"

    if [[ "$http_code" != "200" ]]; then
        worklog_audit "ERROR" "jira.sprint.load" "board/${JIRA_BOARD_ID}" "failure" "HTTP ${http_code}"
        worklog_error "Failed to fetch active sprint (HTTP ${http_code})"
        return 5
    fi

    sprint_id="$(printf '%s' "$body" | jq -r '.values[0].id // empty')"
    if [[ -z "$sprint_id" ]]; then
        worklog_audit "WARN" "jira.sprint.load" "board/${JIRA_BOARD_ID}" "empty" "no active sprint"
        JIRA_SPRINT_TICKETS_JSON="[]"
        JIRA_SPRINT_TICKET_KEYS=()
        return 0
    fi

    local sprint_name
    sprint_name="$(printf '%s' "$body" | jq -r '.values[0].name // "unknown"')"
    worklog_audit "INFO" "jira.sprint.load" "sprint/${sprint_id}" "success" "sprint=${sprint_name}"

    result="$(jira_fetch_with_retry GET "/rest/agile/1.0/sprint/${sprint_id}/issue?maxResults=100")"
    http_code="$(printf '%s' "$result" | head -n1)"
    body="$(printf '%s' "$result" | tail -n +2)"

    if [[ "$http_code" != "200" ]]; then
        worklog_audit "ERROR" "jira.issues.filter" "sprint/${sprint_id}" "failure" "HTTP ${http_code}"
        return 5
    fi

    JIRA_SPRINT_TICKETS_JSON="$(printf '%s' "$body" | jq --arg label "$JIRA_LOGGING_LABEL" \
        '[.issues[] | select(.fields.labels | index($label)) | {
            key: .key,
            summary: .fields.summary,
            labels: .fields.labels,
            status: .fields.status.name,
            inActiveSprint: true
        }]')"

    local count
    count="$(printf '%s' "$JIRA_SPRINT_TICKETS_JSON" | jq 'length')"
    worklog_audit "INFO" "jira.issues.filter" "label/${JIRA_LOGGING_LABEL}" "success" "count=${count}"

    JIRA_SPRINT_TICKET_KEYS=()
    while IFS= read -r key; do
        [[ -n "$key" ]] && JIRA_SPRINT_TICKET_KEYS+=("$key")
    done < <(printf '%s' "$JIRA_SPRINT_TICKETS_JSON" | jq -r '.[].key')

    return 0
}

jira_ticket_in_sprint() {
    local ticket_key="$1"
    local key
    for key in "${JIRA_SPRINT_TICKET_KEYS[@]}"; do
        [[ "$key" == "$ticket_key" ]] && return 0
    done
    return 1
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
            "title=${title} duration=${duration_minutes}m"
        return 0
    fi

    worklog_audit "INFO" "jira.worklog.submit" "$issue_key" "pending" \
        "title=${title} duration=${duration_minutes}m"

    local payload result http_code body
    payload="$(jira_build_worklog_payload "$title" "$started" "$duration_minutes")"
    result="$(jira_fetch_with_retry POST "/rest/api/3/issue/${issue_key}/worklog" "$payload")"
    http_code="$(printf '%s' "$result" | head -n1)"
    body="$(printf '%s' "$result" | tail -n +2)"

    if [[ "$http_code" == "201" ]]; then
        local wl_id
        wl_id="$(printf '%s' "$body" | jq -r '.id // "unknown"')"
        worklog_audit "INFO" "jira.worklog.submit" "$issue_key" "success" \
            "worklog_id=${wl_id} title=${title} duration=${duration_minutes}m"
        return 0
    fi

    worklog_audit "ERROR" "jira.worklog.submit" "$issue_key" "failure" "HTTP ${http_code}"
    worklog_error "Worklog submission failed for ${issue_key} (HTTP ${http_code})"
    return 5
}
