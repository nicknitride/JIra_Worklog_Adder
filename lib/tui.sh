#!/usr/bin/env bash
# gum-based TUI screens with GCash blue theme.

TUI_THEME_FOREGROUND="#0066CC"
TUI_COLOR_GUILD="#FF6600"
TUI_THEME=""
TUI_VIABLE_DATES=()
TUI_SELECTED_EVENTS_JSON="[]"
TUI_MAPPINGS_JSON="[]"
TUI_PICKED_TICKET=""
TUI_PICK_OPTIONS=()
# Gum label/value split — must not appear in ticket titles (guild labels use "|").
TUI_PICK_VALUE_DELIM=$'\x1f'

tui_require_gum() {
    if ! command -v gum >/dev/null 2>&1; then
        worklog_error "gum is required. Install with: brew install gum"
        exit 1
    fi
}

tui_init_theme() {
    tui_require_gum
    export CLICOLOR_FORCE=1
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

tui_guild_board_configured() {
    [[ -n "${JIRA_GUILD_BOARD_KEY:-}" ]]
}

tui_guild_board_label() {
    if [[ -n "${JIRA_GUILD_BOARD_SUMMARY:-}" && "${JIRA_GUILD_BOARD_SUMMARY}" != "unknown" ]]; then
        printf '%s' "$JIRA_GUILD_BOARD_SUMMARY"
    else
        printf '%s' "$JIRA_GUILD_BOARD_KEY"
    fi
}

tui_format_ticket_line() {
    local color="$1"
    local key="$2"
    local summary="$3"
    local status="${4:-}"
    local board_label="${5:-}"
    local subtask_label="${key} — ${summary}"
    local line
    [[ -n "$status" ]] && subtask_label="${subtask_label} [${status}]"
    if [[ -n "$board_label" ]]; then
        line="${board_label} | ${subtask_label}"
    else
        line="$subtask_label"
    fi
    gum style --foreground "$color" "$line"
}

tui_format_ticket_section_header() {
    local color="$1"
    local label="$2"
    gum style --foreground "$color" --bold "── ${label} ──"
}

tui_reset_pick_options() {
    TUI_PICK_OPTIONS=()
}

# Build gum choose options as styledLabel<RS>ticketKey (see TUI_PICK_VALUE_DELIM).
tui_append_pick_options() {
    local color="$1"
    local source_tag="$2"
    local tickets_json="$3"
    local board_label="${4:-}"
    local count key summary status label subtask_label styled i

    count="$(printf '%s' "$tickets_json" | jq 'length')"
    [[ "$count" -eq 0 ]] && return 0

    for (( i=0; i<count; i++ )); do
        key="$(printf '%s' "$tickets_json" | jq -r ".[$i].key")"
        summary="$(printf '%s' "$tickets_json" | jq -r ".[$i].summary")"
        status="$(printf '%s' "$tickets_json" | jq -r ".[$i].status // empty")"
        subtask_label="${key} — ${summary}"
        [[ -n "$status" ]] && subtask_label="${subtask_label} [${status}]"
        if [[ -n "$board_label" ]]; then
            label="${board_label} | ${subtask_label}"
        else
            label="${source_tag} │ ${subtask_label}"
        fi
        styled="$(gum style --foreground "$color" "$label")"
        TUI_PICK_OPTIONS+=("${styled}${TUI_PICK_VALUE_DELIM}${key}")
    done
}

tui_parse_pick_choice() {
    local choice="$1"
    case "$choice" in
        __manual__) printf '__manual__' ;;
        *)
            if [[ "$choice" == *"$TUI_PICK_VALUE_DELIM"* ]]; then
                printf '%s' "${choice#*"$TUI_PICK_VALUE_DELIM"}"
            elif [[ "$choice" =~ ^([A-Z][A-Z0-9]+-[0-9]+)$ ]]; then
                printf '%s' "${BASH_REMATCH[1]}"
            else
                local stripped
                stripped="$(printf '%s' "$choice" | sed $'s/\x1b\\[[0-9;]*m//g')"
                if [[ "$stripped" =~ ([A-Z][A-Z0-9]+-[0-9]+) ]]; then
                    printf '%s' "${BASH_REMATCH[1]}"
                fi
            fi
            ;;
    esac
}

tui_worklog_tickets_overview() {
    local bucket_tickets_json="$1"
    local guild_tickets_json="${2:-[]}"
    local bucket_count guild_count

    tui_display $TUI_THEME --bold "Available Worklog Tickets"
    bucket_count="$(printf '%s' "$bucket_tickets_json" | jq 'length')"
    guild_count="$(printf '%s' "$guild_tickets_json" | jq 'length')"

    if [[ "$bucket_count" -eq 0 && "$guild_count" -eq 0 ]]; then
        tui_display $TUI_THEME --foreground "#FF6600" \
            "No subtasks found. You can enter ticket keys manually during assignment."
        worklog_audit "WARN" "tui.tickets.empty" "subtasks" "empty" "no sprint or guild subtasks"
        tui_println
        return 0
    fi

    if [[ "$bucket_count" -gt 0 ]]; then
        tui_display "$(tui_format_ticket_section_header "$TUI_THEME_FOREGROUND" \
            "Sprint Bucket · ${JIRA_BUCKET_PARENT_KEY} — ${JIRA_BUCKET_PARENT_SUMMARY}")"
        printf '%s' "$bucket_tickets_json" | jq -r '.[] | "\(.key)|\(.summary)|\(.status // "")"' | while IFS='|' read -r key summary status; do
            printf '  %s\n' "$(tui_format_ticket_line "$TUI_THEME_FOREGROUND" "$key" "$summary" "$status")" >&2
        done
        worklog_audit "INFO" "tui.bucket.display" "subtasks" "success" "count=${bucket_count}"
    else
        tui_display $TUI_THEME --foreground "#FF6600" \
            "No subtasks found under ${JIRA_BUCKET_PARENT_KEY}."
        worklog_audit "WARN" "tui.bucket.empty" "subtasks" "empty" "parent=${JIRA_BUCKET_PARENT_KEY}"
    fi

    if tui_guild_board_configured; then
        tui_println
        if [[ "$guild_count" -gt 0 ]]; then
            tui_display "$(tui_format_ticket_section_header "$TUI_COLOR_GUILD" \
                "Guild Board · ${JIRA_GUILD_BOARD_KEY} — ${JIRA_GUILD_BOARD_SUMMARY}")"
            printf '%s' "$guild_tickets_json" | jq -r '.[] | "\(.key)|\(.summary)|\(.status // "")"' | while IFS='|' read -r key summary status; do
                printf '  %s\n' "$(tui_format_ticket_line "$TUI_COLOR_GUILD" "$key" "$summary" "$status" "$(tui_guild_board_label)")" >&2
            done
            worklog_audit "INFO" "tui.guild.display" "subtasks" "success" "count=${guild_count}"
        else
            tui_display --foreground "$TUI_COLOR_GUILD" --bold \
                "── Guild Board · ${JIRA_GUILD_BOARD_KEY} ──"
            tui_display --foreground "$TUI_COLOR_GUILD" \
                "No subtasks found under ${JIRA_GUILD_BOARD_KEY}."
            worklog_audit "WARN" "tui.guild.empty" "subtasks" "empty" "parent=${JIRA_GUILD_BOARD_KEY}"
        fi
    fi

    tui_println
}

tui_logging_mode(){
    gum choose \
    --header "Select a logging mode" \
    "Log Today" \
    "Select a date range"
    return 0
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

tui_format_event_date_header() {
    local date_str="$1"
    local dow
    dow="$(config_day_of_week "$date_str")"
    tui_println
    tui_display $TUI_THEME --bold "── ${dow}, ${date_str} ──"
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

    local -a selected_ids=()
    local -a dates=()
    local date_str day_events day_count i event line id
    local -a choices ids selected idx

    dates=()
    while IFS= read -r date_str; do
        [[ -n "$date_str" ]] && dates+=("$date_str")
    done < <(printf '%s' "$events_json" | jq -r '[.[].eventDate // .[].startTime[0:10]] | unique | sort | .[]')

    for date_str in "${dates[@]}"; do
        day_events="$(printf '%s' "$events_json" | jq --arg d "$date_str" \
            '[.[] | select((.eventDate // .startTime[0:10]) == $d)]')"
        day_count="$(printf '%s' "$day_events" | jq 'length')"
        [[ "$day_count" -eq 0 ]] && continue

        tui_format_event_date_header "$date_str"
        printf '%s' "$day_events" | jq -r '.[] |
            "  \(.title) | \(.startTime[11:16])-\(.endTime[11:16]) (\(.durationMinutes)m)"' | tui_print_list

        choices=()
        ids=()
        for (( i=0; i<day_count; i++ )); do
            event="$(printf '%s' "$day_events" | jq -c ".[$i]")"
            id="$(printf '%s' "$event" | jq -r '.id')"
            line="$(tui_format_event_line "$event")"
            choices+=("$line")
            ids+=("$id")
        done

        selected="$(gum choose --no-limit "${choices[@]}")" || true
        [[ -z "$selected" ]] && continue

        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            for idx in "${!choices[@]}"; do
                if [[ "${choices[$idx]}" == "$line" ]]; then
                    selected_ids+=("${ids[$idx]}")
                    worklog_audit "INFO" "tui.event.select" "${ids[$idx]}" "selected" "${date_str} ${line}"
                fi
            done
        done <<< "$selected"
    done

    if [[ ${#selected_ids[@]} -eq 0 ]]; then
        worklog_audit "INFO" "tui.event.select" "events" "skipped" "none selected"
        TUI_SELECTED_EVENTS_JSON="[]"
        return 0
    fi

    TUI_SELECTED_EVENTS_JSON="$(printf '%s' "$events_json" | jq --argjson sel "$(printf '%s\n' "${selected_ids[@]}" | jq -R . | jq -s .)" \
        '[.[] | select(.id as $id | $sel | index($id)) | . + {selected: true}]')"
}

tui_pick_ticket() {
    local event_title="$1"
    local bucket_tickets_json="$2"
    local guild_tickets_json="${3:-[]}"
    local choice manual ticket_key ticket_count header

    tui_reset_pick_options
    tui_append_pick_options "$TUI_THEME_FOREGROUND" "Sprint" "$bucket_tickets_json"

    if tui_guild_board_configured; then
        tui_append_pick_options "$TUI_COLOR_GUILD" "Guild" "$guild_tickets_json" "$(tui_guild_board_label)"
    fi

    ticket_count="${#TUI_PICK_OPTIONS[@]}"

    tui_display $TUI_THEME --bold "Assign ticket for: ${event_title}"
    if [[ "$ticket_count" -gt 0 ]]; then
        tui_display $TUI_THEME "Blue = sprint bucket · Orange = guild board"
    fi

    if [[ "$ticket_count" -eq 0 ]]; then
        tui_manual_parent_subtask_pick "$event_title"
        return 0
    fi

    TUI_PICK_OPTIONS+=("Enter parent ticket key...${TUI_PICK_VALUE_DELIM}__manual__")
    header="Assign ticket for: ${event_title}"

    while true; do
        choice="$(gum choose --label-delimiter="$TUI_PICK_VALUE_DELIM" --header "$header" "${TUI_PICK_OPTIONS[@]}")" || true
        [[ -z "$choice" ]] && return 0

        ticket_key="$(tui_parse_pick_choice "$choice")"
        [[ -z "$ticket_key" ]] && continue

        if [[ "$ticket_key" == "__manual__" ]]; then
            tui_manual_parent_subtask_pick "$event_title"
            return 0
        fi

        TUI_PICKED_TICKET="$ticket_key"
        worklog_audit "INFO" "tui.ticket.assign" "$TUI_PICKED_TICKET" "selected" "event=${event_title}"
        return 0
    done
}

tui_validate_ticket_key() {
    local key="$1"
    case "$key" in
        [A-Z]*-[0-9]*) return 0 ;;
        *) return 1 ;;
    esac
}

# Manual parent key → show summary → pick a subtask for worklogging.
tui_manual_parent_subtask_pick() {
    local event_title="$1"
    local parent_key parent_summary subtasks_json count choice ticket_key fetched

    while true; do
        parent_key="$(gum input --placeholder "Enter Jira ticket key (e.g. TRIBE06-67802)")"
        parent_key="$(printf '%s' "$parent_key" | awk '{print $1}')"
        [[ -z "$parent_key" ]] && return 0

        if ! tui_validate_ticket_key "$parent_key"; then
            tui_display $TUI_THEME --foreground "#FF6600" "Invalid ticket key: ${parent_key}"
            continue
        fi

        if ! fetched="$(jira_fetch_subtasks_for_parent "$parent_key" "manual/${parent_key}")"; then
            tui_display $TUI_THEME --foreground "#FF6600" \
                "Could not fetch ${parent_key}. Check the key and try again."
            continue
        fi

        parent_summary="$(printf '%s' "$fetched" | head -n1)"
        subtasks_json="$(printf '%s' "$fetched" | tail -n +2)"
        count="$(printf '%s' "$subtasks_json" | jq 'length')"

        tui_println
        tui_display $TUI_THEME --bold "${parent_key} — ${parent_summary}"

        if [[ "$count" -eq 0 ]]; then
            tui_display $TUI_THEME --foreground "#FF6600" \
                "No subtasks found under ${parent_key}."
            worklog_audit "WARN" "tui.ticket.manual" "$parent_key" "no_subtasks" "event=${event_title}"
            if gum confirm "Try a different ticket key?"; then
                continue
            fi
            return 0
        fi

        jira_register_manual_subtasks "$subtasks_json"

        tui_reset_pick_options
        tui_append_pick_options "$TUI_THEME_FOREGROUND" "Subtask" "$subtasks_json"
        choice="$(gum choose --label-delimiter="$TUI_PICK_VALUE_DELIM" \
            --header "Pick subtask for: ${event_title} (${parent_key})" \
            "${TUI_PICK_OPTIONS[@]}")" || true
        [[ -z "$choice" ]] && return 0

        ticket_key="$(tui_parse_pick_choice "$choice")"
        if [[ -n "$ticket_key" ]]; then
            TUI_PICKED_TICKET="$ticket_key"
            worklog_audit "INFO" "tui.ticket.manual" "$ticket_key" "selected" \
                "parent=${parent_key} event=${event_title}"
            return 0
        fi
    done
}

tui_check_out_of_buckets() {
    local ticket_key="$1"
    if jira_ticket_in_known_lists "$ticket_key"; then
        return 0
    fi
    local known_lists="sprint bucket (${JIRA_BUCKET_PARENT_KEY})"
    if tui_guild_board_configured; then
        known_lists="${known_lists} or guild board (${JIRA_GUILD_BOARD_KEY})"
    fi
    tui_display $TUI_THEME --foreground "#FF6600" \
        "Warning: ${ticket_key} is not a subtask of ${known_lists}."
    worklog_audit "WARN" "tui.ticket.out_of_bucket" "$ticket_key" "warning" "requires confirm"
    confirm_action "Submit worklog to ticket outside known lists (${ticket_key})?"
}

tui_build_mappings() {
    local selected_events="$1"
    local bucket_tickets_json="$2"
    local guild_tickets_json="${3:-[]}"
    local count i event title ticket mappings="[]"

    count="$(printf '%s' "$selected_events" | jq 'length')"
    if [[ "$count" -eq 0 ]]; then
        TUI_MAPPINGS_JSON="[]"
        return 0
    fi

    for (( i=0; i<count; i++ )); do
        event="$(printf '%s' "$selected_events" | jq -c ".[$i]")"
        title="$(printf '%s' "$event" | jq -r '.title')"
        tui_pick_ticket "$title" "$bucket_tickets_json" "$guild_tickets_json"
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
                eventDate: ($ev.eventDate // $ev.startTime[0:10]),
                durationMinutes: ($ev.durationMinutes | tonumber),
                workDate: ($ev.eventDate // $ev.startTime[0:10]),
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

    printf '%s' "$mappings" | jq -r '
        group_by(.workDate) | sort_by(.[0].workDate)[] |
        "── \(.[0].workDate) ──",
        (.[] | "  \(.ticketKey): \(.eventTitle) — \(.durationMinutes)m | \(.startTime[11:16])-\(.endTime[11:16])")
    ' | tui_print_list

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
    local bucket_tickets_json="$2"
    local guild_tickets_json="${3:-[]}"
    local mappings i count mapping
    local submitted=0 failed=0
    local -a failed_lines=()
    local ticket_key event_title started

    tui_build_mappings "$selected_events" "$bucket_tickets_json" "$guild_tickets_json"
    mappings="$TUI_MAPPINGS_JSON"
    if ! tui_submission_preview "$mappings"; then
        worklog_audit "INFO" "tui.submit" "worklogs" "declined" "user declined preview"
        return 4
    fi

    count="$(printf '%s' "$mappings" | jq 'length')"
    for (( i=0; i<count; i++ )); do
        mapping="$(printf '%s' "$mappings" | jq -c ".[$i]")"
        ticket_key="$(printf '%s' "$mapping" | jq -r '.ticketKey')"
        event_title="$(printf '%s' "$mapping" | jq -r '.eventTitle')"
        started="$(jira_format_worklog_started "$(printf '%s' "$mapping" | jq -r '.startTime')")"
        if jira_submit_worklog \
            "$ticket_key" \
            "$event_title" \
            "$started" \
            "$(printf '%s' "$mapping" | jq -r '.durationMinutes')"; then
            submitted=$((submitted + 1))
            continue
        fi
        failed=$((failed + 1))
        if [[ "${JIRA_LAST_HTTP_CODE:-}" == "000" ]]; then
            failed_lines+=("${ticket_key}: ${event_title} (network error)")
        else
            failed_lines+=("${ticket_key}: ${event_title} (HTTP ${JIRA_LAST_HTTP_CODE:-unknown})")
        fi
    done

    tui_println
    if [[ "$failed" -eq 0 ]]; then
        tui_display $TUI_THEME --bold "Done! Submitted ${submitted} worklog(s) to Jira."
        worklog_audit "INFO" "tui.submit" "worklogs" "success" "submitted=${submitted}"
        return 0
    fi

    if [[ "$submitted" -gt 0 ]]; then
        tui_display $TUI_THEME --foreground "#FF6600" --bold \
            "Partial failure: ${submitted} submitted, ${failed} failed."
    else
        tui_display $TUI_THEME --foreground "#FF6600" --bold \
            "Submission failed: no worklogs were created."
    fi

    local line
    for line in "${failed_lines[@]}"; do
        tui_display $TUI_THEME --foreground "#FF6600" "  ✗ ${line}"
    done
    tui_display $TUI_THEME "Details: ${WORKLOG_SESSION_LOG}"
    if [[ "$failed" -gt 0 && "${JIRA_LAST_HTTP_CODE:-}" == "000" ]]; then
        tui_display $TUI_THEME --foreground "#FF6600" \
            "Network error — check VPN/connectivity and retry."
    fi

    worklog_audit "ERROR" "tui.submit" "worklogs" "failure" \
        "submitted=${submitted} failed=${failed}"
    return 5
}
