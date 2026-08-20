#!/usr/bin/env bash
# Jira Calendar Worklog TUI — main entry point
# Feature: 001-jira-calendar-worklog

set -euo pipefail

readonly WORKLOG_VERSION="1.0.0"
readonly WORKLOG_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export WORKLOG_PROJECT_ROOT="$WORKLOG_SCRIPT_DIR"

# Source libraries
# shellcheck source=lib/logging.sh
source "${WORKLOG_PROJECT_ROOT}/lib/logging.sh"
# shellcheck source=lib/config.sh
source "${WORKLOG_PROJECT_ROOT}/lib/config.sh"
# shellcheck source=lib/confirm.sh
source "${WORKLOG_PROJECT_ROOT}/lib/confirm.sh"
# shellcheck source=lib/jira-api.sh
source "${WORKLOG_PROJECT_ROOT}/lib/jira-api.sh"
# shellcheck source=lib/calendar-api.sh
source "${WORKLOG_PROJECT_ROOT}/lib/calendar-api.sh"
# shellcheck source=lib/tui.sh
source "${WORKLOG_PROJECT_ROOT}/lib/tui.sh"

WORKLOG_DRY_RUN=0
WORKLOG_VERBOSE=0

worklog_usage() {
    cat <<EOF
Usage: ./worklog-tui.sh [OPTIONS]

Interactive TUI to log Jira worklogs from Google Calendar events.

Options:
  --dry-run    Preview all steps without Jira worklog or .env writes
  --verbose    Enable bash trace (set -x) on stderr
  --help       Show this help message
  --version    Show version

Environment:
  SPECIFY_VERBOSE=1   Same as --verbose
  WORKLOG_LOG_DIR     Override log directory (default: ./logs)

Exit codes:
  0  Success
  1  General error
  2  Configuration error
  3  Authentication error
  4  User cancelled
  5  API error
EOF
}

worklog_parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                WORKLOG_DRY_RUN=1
                export WORKLOG_DRY_RUN
                shift
                ;;
            --verbose)
                WORKLOG_VERBOSE=1
                shift
                ;;
            --help|-h)
                worklog_usage
                exit 0
                ;;
            --version|-v)
                printf 'worklog-tui %s\n' "$WORKLOG_VERSION"
                exit 0
                ;;
            *)
                worklog_error "Unknown option: $1"
                worklog_usage
                exit 1
                ;;
        esac
    done
    if [[ "${SPECIFY_VERBOSE:-0}" == "1" ]]; then
        WORKLOG_VERBOSE=1
    fi
    if [[ "$WORKLOG_VERBOSE" == "1" ]]; then
        set -x
    fi
}

worklog_check_dependencies() {
    local dep missing=()
    for dep in curl jq python3; do
        command -v "$dep" >/dev/null 2>&1 || missing+=("$dep")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        worklog_error "Missing dependencies: ${missing[*]}"
        exit 1
    fi
}

worklog_main() {
    worklog_parse_args "$@"
    worklog_check_dependencies

    worklog_init_session_log
    worklog_progress "session" "start" "worklog-tui ${WORKLOG_VERSION}"

    if ! config_load; then
        exit 2
    fi

    tui_init_theme
    tui_welcome

    # US1: Connect and bucket context
    if ! jira_validate_auth; then
        exit 3
    fi

    local google_status="connected"
    if ! calendar_ensure_google_auth; then
        google_status="failed"
        exit 3
    fi

    tui_connection_status "connected" "$google_status"

    if ! jira_fetch_bucket_tickets; then
        exit 5
    fi

    if tui_guild_board_configured; then
        if ! jira_fetch_guild_board_tickets; then
            exit 5
        fi
    else
        JIRA_GUILD_TICKETS_JSON="[]"
    fi

    tui_worklog_tickets_overview "$JIRA_BUCKET_TICKETS_JSON" "$JIRA_GUILD_TICKETS_JSON"

    # US2: Day selection
    local week_range week_start week_end
    week_range="$(config_current_week_range)"
    week_start="${week_range%% *}"
    week_end="${week_range##* }"

    local logging_mode
    logging_mode="$(tui_logging_mode)"
    worklog_audit "INFO" "tui.day.select_log_mode" "mode" "select success" "$logging_mode for $(date +%Y-%m-%d)"
    case "$logging_mode" in
        "Log Today")
            TUI_VIABLE_DATES=("$(date +%Y-%m-%d)")
            ;;

        "Select a date range")
            tui_day_selection "$week_start" "$week_end" || exit 4
            ;;

        *)
            exit 4
            ;;
    esac
    local -a viable_dates=("${TUI_VIABLE_DATES[@]}")

    local events_json
    events_json="$(calendar_fetch_events_for_days "${viable_dates[@]}")" || exit 3

    # US3: Event selection and mapping
    tui_event_selection "$events_json"
    local selected_events="$TUI_SELECTED_EVENTS_JSON"

    local submit_exit=0
    if [[ "$(printf '%s' "$selected_events" | jq 'length')" -gt 0 ]]; then
        tui_map_and_submit "$selected_events" "$JIRA_BUCKET_TICKETS_JSON" "$JIRA_GUILD_TICKETS_JSON" || \
            submit_exit=$?
        if [[ "$submit_exit" -eq 4 ]]; then
            exit 4
        fi
        if [[ "$submit_exit" -eq 5 ]]; then
            worklog_audit "ERROR" "session.end" "worklog-tui" "failure" \
                "log=${WORKLOG_SESSION_LOG} submit_failed=true"
            worklog_progress "session" "failed" "log file: ${WORKLOG_SESSION_LOG}"
            exit 5
        fi
    else
        tui_display $TUI_THEME "No events selected. Exiting without submitting worklogs."
        worklog_audit "INFO" "tui.submit" "worklogs" "skipped" "no events selected"
    fi

    worklog_audit "INFO" "session.end" "worklog-tui" "success" "log=${WORKLOG_SESSION_LOG}"
    worklog_progress "session" "complete" "log file: ${WORKLOG_SESSION_LOG}"
}

worklog_main "$@"
