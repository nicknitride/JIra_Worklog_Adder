#!/usr/bin/env bash
# gum-based TUI screens with GCash blue theme.

TUI_THEME_FOREGROUND="#0066CC"
TUI_THEME=""
TUI_VIABLE_DATES=()
TUI_SELECTED_EVENTS_JSON="[]"
TUI_MAPPINGS_JSON="[]"
TUI_PICKED_TICKET=""

tui_require_gum() {
    if ! command -v gum >/dev/null 2>&1; then
        worklog_error "gum is required. Install with: brew install gum"
        exit 1
    fi
}

tui_init_theme() {
    tui_require_gum
    export GUM_CONFIRM_DEFAULT=false
    TUI_THEME="--foreground ${TUI_THEME_FOREGROUND}"
}

# Never write UI to stdout — worklog-tui captures stdout for data in some paths.
# Use stderr only; avoid /dev/tty (breaks Cursor's integrated terminal).
tui_display() {
    gum style "$@" >&2
}

tui_println() {
    printf '\n' >&2
}

tui_print_list() {
    local line
    while IFS= read -r line; do
        [[ -n "$line" ]] && printf '  %s\n' "$line" >&2
    done
}

tui_show_banner() {
    local banner_file="${WORKLOG_PROJECT_ROOT}/lib/assets/gcash-banner.txt"
    if [[ -f "$banner_file" ]]; then
        tui_display $TUI_THEME "$(cat "$banner_file")"
    fi
    tui_display $TUI_THEME --bold "Jira Calendar Worklog TUI"
    tui_println
}

tui_welcome() {
    tui_show_banner
    tui_display $TUI_THEME "Welcome! Connect to Jira and Google Calendar to log work from your calendar."
    tui_println
}

tui_connection_status() {
    local jira_status="$1"
    local google_status="$2"
    tui_display $TUI_THEME --bold "Connection Status"
    tui_display $TUI_THEME "Jira:    ${jira_status}"
    tui_display $TUI_THEME "Google:  ${google_status}"
    tui_println
}

tui_bucket_tickets() {
    local tickets_json="$1"
    local count
    count="$(printf '%s' "$tickets_json" | jq 'length')"
    tui_display $TUI_THEME --bold "Worklog Buckets (subtasks of ${JIRA_BUCKET_PARENT_KEY})"
    tui_display $TUI_THEME "${JIRA_BUCKET_PARENT_KEY} — ${JIRA_BUCKET_PARENT_SUMMARY}"
    if [[ "$count" -eq 0 ]]; then
        tui_display $TUI_THEME --foreground "#FF6600" \
            "No subtasks found under ${JIRA_BUCKET_PARENT_KEY}. You can enter ticket keys manually later."
        worklog_audit "WARN" "tui.bucket.empty" "subtasks" "empty" "parent=${JIRA_BUCKET_PARENT_KEY}"
        return 0
    fi
    printf '%s' "$tickets_json" | jq -r '.[] | "\(.key) — \(.summary) [\(.status)]"' | tui_print_list
    worklog_audit "INFO" "tui.bucket.display" "subtasks" "success" "count=${count}"
    tui_println
}

tui_day_selection() {
    local week_start="$1"
    local week_end="$2"
    tui_display $TUI_THEME --bold "Select Viable Days (${week_start} to ${week_end})"

    local adjust
    if gum confirm "Adjust date range before selecting days?"; then
        week_start="$(gum input --placeholder "Start date YYYY-MM-DD" --value "$week_start")"
        week_end="$(gum input --placeholder "End date YYYY-MM-DD" --value "$week_end")"
        worklog_audit "INFO" "tui.day.range_adjust" "dates" "success" "${week_start}..${week_end}"
    fi

    local -a viable_dates=() all_dates=()
    local d dow label
    while IFS= read -r d; do
        [[ -n "$d" ]] && all_dates+=("$d")
    done < <(config_dates_between "$week_start" "$week_end")

    for d in "${all_dates[@]}"; do
        dow="$(config_day_of_week "$d")"
        label="${d} (${dow})"
        if gum confirm "Mark ${label} as viable for worklogging?"; then
            viable_dates+=("$d")
            worklog_audit "INFO" "tui.day.toggle" "$d" "viable" "day=${dow}"
        else
            worklog_audit "INFO" "tui.day.toggle" "$d" "skipped" "day=${dow}"
        fi
    done

    if [[ ${#viable_dates[@]} -eq 0 ]]; then
        tui_display $TUI_THEME --foreground "#FF6600" "No viable days selected. Please select at least one day."
        worklog_audit "WARN" "tui.day.selection" "days" "empty" "no viable days"
        return 1
    fi

    TUI_VIABLE_DATES=("${viable_dates[@]}")
    return 0
}

tui_format_event_line() {
    local event_json="$1"
    local title start end dur warning badge
    title="$(printf '%s' "$event_json" | jq -r '.title')"
    start="$(printf '%s' "$event_json" | jq -r '.startTime')"
    end="$(printf '%s' "$event_json" | jq -r '.endTime')"
    dur="$(printf '%s' "$event_json" | jq -r '.durationMinutes')"
    warning="$(printf '%s' "$event_json" | jq -r '.warning // empty')"
    badge=""
    [[ "$warning" == "ALL_DAY" ]] && badge=" [ALL-DAY ⚠]"
    [[ "$warning" == "TENTATIVE" ]] && badge=" [TENTATIVE ⚠]"
    printf '%s | %s - %s (%sm)%s' "$title" "${start:11:5}" "${end:11:5}" "$dur" "$badge"
}

tui_event_selection() {
    local events_json="$1"
    local count
    count="$(printf '%s' "$events_json" | jq 'length')"

    tui_display $TUI_THEME --bold "Select Calendar Events"
    if [[ "$count" -eq 0 ]]; then
        tui_display $TUI_THEME "No eligible events found for viable days."
        worklog_audit "INFO" "tui.event.empty" "events" "empty" "no events"
        TUI_SELECTED_EVENTS_JSON="[]"
        return 0
    fi

    local -a choices=()
    local -a ids=()
    local i event line id
    for (( i=0; i<count; i++ )); do
        event="$(printf '%s' "$events_json" | jq -c ".[$i]")"
        id="$(printf '%s' "$event" | jq -r '.id')"
        line="$(tui_format_event_line "$event")"
        choices+=("$line")
        ids+=("$id")
    done

    local selected
    selected="$(gum choose --no-limit "${choices[@]}")" || true
    if [[ -z "$selected" ]]; then
        worklog_audit "INFO" "tui.event.select" "events" "skipped" "none selected"
        TUI_SELECTED_EVENTS_JSON="[]"
        return 0
    fi

    local -a selected_ids=()
    local line choice idx
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        for idx in "${!choices[@]}"; do
            if [[ "${choices[$idx]}" == "$line" ]]; then
                selected_ids+=("${ids[$idx]}")
                worklog_audit "INFO" "tui.event.select" "${ids[$idx]}" "selected" "$line"
            fi
        done
    done <<< "$selected"

    TUI_SELECTED_EVENTS_JSON="$(printf '%s' "$events_json" | jq --argjson sel "$(printf '%s\n' "${selected_ids[@]}" | jq -R . | jq -s .)" \
        '[.[] | select(.id as $id | $sel | index($id)) | . + {selected: true}]')"
}

tui_pick_ticket() {
    local event_title="$1"
    local tickets_json="$2"
    local count ticket_keys choice manual

    count="$(printf '%s' "$tickets_json" | jq 'length')"
    tui_display $TUI_THEME --bold "Assign ticket for: ${event_title}"

    if [[ "$count" -gt 0 ]]; then
        ticket_keys=()
        while IFS= read -r key; do
            [[ -n "$key" ]] && ticket_keys+=("$key")
        done < <(printf '%s' "$tickets_json" | jq -r '.[] | "\(.key) — \(.summary)"')
        choice="$(gum choose "${ticket_keys[@]}" "Enter ticket key manually...")" || true
        if [[ "$choice" == "Enter ticket key manually..." || -z "$choice" ]]; then
            manual="$(gum input --placeholder "TRIBE06-12345")"
            TUI_PICKED_TICKET="$manual"
            worklog_audit "INFO" "tui.ticket.manual" "$manual" "selected" "event=${event_title}"
            return 0
        fi
        TUI_PICKED_TICKET="$(printf '%s' "$choice" | awk '{print $1}')"
        worklog_audit "INFO" "tui.ticket.assign" "$TUI_PICKED_TICKET" "selected" "event=${event_title}"
        return 0
    fi

    manual="$(gum input --placeholder "Enter Jira ticket key (e.g. TRIBE06-67802)")"
    worklog_audit "INFO" "tui.ticket.manual" "$manual" "selected" "event=${event_title}"
    TUI_PICKED_TICKET="$manual"
}

tui_validate_ticket_key() {
    local key="$1"
    case "$key" in
        [A-Z]*-[0-9]*) return 0 ;;
        *) return 1 ;;
    esac
}

tui_check_out_of_buckets() {
    local ticket_key="$1"
    if jira_ticket_in_buckets "$ticket_key"; then
        return 0
    fi
    tui_display $TUI_THEME --foreground "#FF6600" \
        "Warning: ${ticket_key} is not a subtask of ${JIRA_BUCKET_PARENT_KEY}."
    worklog_audit "WARN" "tui.ticket.out_of_bucket" "$ticket_key" "warning" "requires confirm"
    confirm_action "Submit worklog to ticket outside bucket list (${ticket_key})?"
}

tui_build_mappings() {
    local selected_events="$1"
    local tickets_json="$2"
    local count i event title ticket mappings="[]"

    count="$(printf '%s' "$selected_events" | jq 'length')"
    if [[ "$count" -eq 0 ]]; then
        TUI_MAPPINGS_JSON="[]"
        return 0
    fi

    for (( i=0; i<count; i++ )); do
        event="$(printf '%s' "$selected_events" | jq -c ".[$i]")"
        title="$(printf '%s' "$event" | jq -r '.title')"
        tui_pick_ticket "$title" "$tickets_json"
        ticket="$TUI_PICKED_TICKET"
        if [[ -z "$ticket" ]]; then
            worklog_audit "WARN" "tui.ticket.assign" "event" "skipped" "no ticket for ${title}"
            continue
        fi
        ticket="$(printf '%s' "$ticket" | awk '{print $1}')"
        if ! tui_validate_ticket_key "$ticket"; then
            tui_display $TUI_THEME --foreground "#FF6600" "Invalid ticket key: ${ticket}"
            continue
        fi
        tui_check_out_of_buckets "$ticket" || continue
        mappings="$(printf '%s' "$mappings" | jq \
            --argjson ev "$event" \
            --arg tk "$ticket" \
            '. + [{
                eventId: $ev.id,
                eventTitle: $ev.title,
                ticketKey: $tk,
                startTime: $ev.startTime,
                endTime: $ev.endTime,
                durationMinutes: ($ev.durationMinutes | tonumber),
                workDate: ($ev.startTime[0:10]),
                description: $ev.title,
                status: "pending"
            }]')"
    done
    TUI_MAPPINGS_JSON="$mappings"
}

tui_submission_preview() {
    local mappings="$1"
    local count
    count="$(printf '%s' "$mappings" | jq 'length')"

    tui_display $TUI_THEME --bold "Worklog Submission Preview"
    if [[ "$count" -eq 0 ]]; then
        tui_display $TUI_THEME "No worklog entries to submit."
        return 1
    fi

    printf '%s' "$mappings" | jq -r '.[] |
        "\(.ticketKey): \(.eventTitle) — \(.durationMinutes)m | \(.startTime[11:16])-\(.endTime[11:16]) on \(.workDate)"' | tui_print_list

    # 8-hour daily warning (FR-008a)
    local over_days
    over_days="$(printf '%s' "$mappings" | jq -r '
        group_by(.workDate) |
        map({date: .[0].workDate, total: (map(.durationMinutes) | add)}) |
        map(select(.total > 480)) |
        .[] | "\(.date): \(.total)m (\((.total / 60 * 10 | floor) / 10)h)"
    ')"
    if [[ -n "$over_days" ]]; then
        tui_display $TUI_THEME --foreground "#FF6600" "Warning: Daily mapped time exceeds 8 hours:"
        while IFS= read -r line; do
            [[ -n "$line" ]] && printf '  %s\n' "$line" >&2
        done <<< "$over_days"
        worklog_audit "WARN" "tui.preview.over8h" "mappings" "warning" "$over_days"
    fi

    tui_println
    if [[ "$WORKLOG_DRY_RUN" == "1" ]]; then
        tui_display $TUI_THEME "[DRY-RUN] No worklogs will be submitted."
    fi

    confirm_action "Submit ${count} worklog(s) to Jira?"
}

tui_map_and_submit() {
    local selected_events="$1"
    local tickets_json="$2"
    local mappings result i count mapping

    tui_build_mappings "$selected_events" "$tickets_json"
    mappings="$TUI_MAPPINGS_JSON"
    if ! tui_submission_preview "$mappings"; then
        worklog_audit "INFO" "tui.submit" "worklogs" "declined" "user declined preview"
        return 4
    fi

    count="$(printf '%s' "$mappings" | jq 'length')"
    for (( i=0; i<count; i++ )); do
        mapping="$(printf '%s' "$mappings" | jq -c ".[$i]")"
        local started
        started="$(jira_format_worklog_started "$(printf '%s' "$mapping" | jq -r '.startTime')")"
        jira_submit_worklog \
            "$(printf '%s' "$mapping" | jq -r '.ticketKey')" \
            "$(printf '%s' "$mapping" | jq -r '.eventTitle')" \
            "$started" \
            "$(printf '%s' "$mapping" | jq -r '.durationMinutes')" || true
    done
    tui_display $TUI_THEME "Done!"
    return 0
}
