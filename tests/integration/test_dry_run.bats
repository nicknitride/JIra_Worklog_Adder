#!/usr/bin/env bats
# Integration test: dry-run mode and CLI flags

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    WORKLOG_TUI="${PROJECT_ROOT}/worklog-tui.sh"
}

@test "worklog-tui --help exits 0" {
    run "$WORKLOG_TUI" --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"--dry-run"* ]]
    [[ "$output" == *"--verbose"* ]]
}

@test "worklog-tui --version exits 0" {
    run "$WORKLOG_TUI" --version
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"worklog-tui"* ]]
}

@test "worklog-tui exits 2 when .env is missing" {
    cd "${BATS_TEST_TMPDIR}" || exit 1
    cp "$WORKLOG_TUI" ./worklog-tui.sh
    cp -r "${PROJECT_ROOT}/lib" .
    cp -r "${PROJECT_ROOT}/scripts" .
    run bash ./worklog-tui.sh
    [[ "$status" -eq 2 ]]
}

@test "worklog-tui --dry-run exits 2 with placeholder .env" {
    local tmp="${BATS_TEST_TMPDIR}/dryrun"
    mkdir -p "$tmp"
    cp "$WORKLOG_TUI" "${tmp}/worklog-tui.sh"
    cp -r "${PROJECT_ROOT}/lib" "${tmp}/lib"
    cp -r "${PROJECT_ROOT}/scripts" "${tmp}/scripts"
    cp "${PROJECT_ROOT}/.env.example" "${tmp}/.env"
    run bash "${tmp}/worklog-tui.sh" --dry-run
    [[ "$status" -eq 2 ]]
}
