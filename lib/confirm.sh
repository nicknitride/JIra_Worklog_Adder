#!/usr/bin/env bash
# User verification prompts per constitution CR-001.

confirm_action() {
    local summary="$1"
    local response

    if [[ "$WORKLOG_DRY_RUN" == "1" && "${2:-}" != "force" ]]; then
        worklog_audit "INFO" "confirm.prompt" "user" "dry_run" "$summary"
    fi

    if [[ -t 0 ]] && command -v gum >/dev/null 2>&1; then
        if gum confirm "$summary"; then
            worklog_audit "INFO" "confirm.accept" "user" "success" "$summary"
            return 0
        fi
        worklog_audit "INFO" "confirm.decline" "user" "skipped" "$summary"
        return 1
    fi

    printf '%s [y/N]: ' "$summary" >&2
    read -r response
    response="$(printf '%s' "$response" | tr '[:upper:]' '[:lower:]')"
    case "$response" in
        y|yes)
            worklog_audit "INFO" "confirm.accept" "user" "success" "$summary"
            return 0
            ;;
        *)
            worklog_audit "INFO" "confirm.decline" "user" "skipped" "$summary"
            return 1
            ;;
    esac
}

confirm_or_exit() {
    if ! confirm_action "$1"; then
        worklog_error "User cancelled: $1"
        exit 4
    fi
}
