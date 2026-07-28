<!--
Sync Impact Report
==================
Version change: (none) → 1.0.0
Modified principles: Initial ratification (template placeholders replaced)
Added sections:
  - I. User Verification Before Actions
  - II. Verbose Bash Script Output
  - III. Comprehensive Timestamped Logging
  - IV. Spec-Driven Development
  - V. Auditability & Traceability
  - Script Standards & Logging Requirements
  - Development Workflow & Verification Gates
Removed sections: None
Templates requiring updates:
  - .specify/templates/plan-template.md ✅ updated
  - .specify/templates/spec-template.md ✅ updated
  - .specify/templates/tasks-template.md ✅ updated
  - .specify/templates/checklist-template.md ✅ updated
  - .specify/templates/commands/*.md ⚠ N/A (directory does not exist)
  - README.md ⚠ N/A (file does not exist)
Follow-up TODOs: None
-->

# Test Speckit Project Constitution

## Core Principles

### I. User Verification Before Actions (NON-NEGOTIABLE)

Every action that mutates state MUST obtain explicit user confirmation before execution.
This includes file creation/deletion, git operations, database changes, deployments,
and any script step that writes to disk or alters external systems.

- Agents and scripts MUST present a clear summary of the intended action and await
  user approval before proceeding.
- Non-interactive or CI contexts MUST use an explicit opt-in flag (e.g., `--yes`,
  `--force`) rather than silently performing mutating operations.
- Read-only operations (inspection, listing, dry-run) do NOT require confirmation
  but MUST still be logged per Principle III.

**Rationale**: Prevents unintended changes, preserves user control, and creates an
auditable decision point for every state mutation.

### II. Verbose Bash Script Output

All bash scripts in `.specify/scripts/bash/` MUST produce verbose, human-readable
output during execution.

- Scripts MUST enable verbose tracing (`set -x` or equivalent) when `SPECIFY_VERBOSE=1`
  or `--verbose` is passed; default behavior SHOULD still emit step-level progress
  messages even without the flag.
- Each major step MUST print a labeled status line to stdout before and after execution.
- Errors MUST be written to stderr with a descriptive prefix (e.g., `ERROR:`).
- Scripts MUST support `--dry-run` where applicable to preview actions without mutation.

**Rationale**: Verbose output enables operators and agents to diagnose failures
quickly and verify that the correct steps ran in the correct order.

### III. Comprehensive Timestamped Logging

Logging MUST reflect every action performed, and every log entry MUST include a
timestamp.

- All scripts MUST use a shared logging helper (defined in `common.sh`) that emits
  ISO-8601 timestamps: `[YYYY-MM-DDTHH:MM:SS±HHMM]`.
- Log levels MUST be used consistently: `INFO`, `WARN`, `ERROR`, `DEBUG`.
- Every state-changing action MUST produce an `INFO`-level log entry describing
  what was done, to which target, and the outcome (success/failure).
- Log output MUST go to stderr; structured data output (JSON mode) MUST go to stdout.
- Scripts SHOULD support `SPECIFY_LOG_FILE` to append logs to a persistent file in
  addition to stderr.

**Rationale**: Timestamped, action-level logs provide a complete audit trail for
debugging, compliance review, and post-incident analysis.

### IV. Spec-Driven Development

Features MUST be defined in specification documents before implementation begins.

- Every feature MUST have a `spec.md` with prioritized user stories and acceptance
  criteria before planning or coding starts.
- Implementation plans (`plan.md`) and task lists (`tasks.md`) MUST trace back to
  spec requirements.
- Scope changes MUST update the spec first, then propagate to plan and tasks.

**Rationale**: Spec-driven workflow ensures shared understanding, prevents scope
drift, and enables independent verification of each user story.

### V. Auditability & Traceability

Every workflow MUST be reconstructable from its artifacts and logs.

- Constitution compliance MUST be verifiable via the Constitution Check gate in
  `plan.md`.
- Git commits for feature work MUST reference the feature identifier.
- Script logs, user confirmations, and generated artifacts MUST together tell a
  complete story of what happened, when, and who approved it.

**Rationale**: Traceability connects user intent (spec) to execution (logs/commits)
and supports review, rollback, and accountability.

## Script Standards & Logging Requirements

| Requirement | Standard |
|-------------|----------|
| Timestamp format | ISO-8601 with timezone offset |
| Log destination | stderr (console); optional file via `SPECIFY_LOG_FILE` |
| Verbose mode | `SPECIFY_VERBOSE=1` or `--verbose` enables `set -x` tracing |
| User confirmation | Prompt with action summary; require `y`/`yes` (case-insensitive) |
| Dry-run | `--dry-run` prints intended actions without executing mutations |
| Exit codes | `0` success; non-zero on failure with `ERROR`-level log entry |

All new or modified scripts MUST source `common.sh` and use its logging helpers.
Existing scripts MUST be updated to comply when next modified.

## Development Workflow & Verification Gates

1. **Specify** → Create/update `spec.md` with user stories and acceptance criteria.
2. **Constitution Check** → Verify plan complies with all five principles before
   Phase 0 research (re-check after Phase 1 design).
3. **Plan** → Generate `plan.md`; include Constitution Check gate results.
4. **Tasks** → Generate `tasks.md` organized by user story priority.
5. **Implement** → Execute tasks; obtain user verification before each mutating
   action; log every step with timestamps.
6. **Validate** → Confirm acceptance scenarios pass; review logs for completeness.

Agents executing `/speckit-implement` MUST pause for user confirmation before any
file write, deletion, git commit, or external system call unless the user has
explicitly pre-authorized the action in the current session.

## Governance

This constitution supersedes conflicting practices in templates, scripts, and agent
workflows for this project.

**Amendment procedure**:

1. Propose change with rationale and version bump type (MAJOR/MINOR/PATCH).
2. Update `.specify/memory/constitution.md` with Sync Impact Report.
3. Propagate changes to dependent templates and scripts.
4. Record amendment date and new version.

**Versioning policy**:

- **MAJOR**: Backward-incompatible principle removal or redefinition.
- **MINOR**: New principle or materially expanded guidance.
- **PATCH**: Clarifications, wording, typo fixes.

**Compliance review**: All feature plans MUST pass the Constitution Check gate.
PRs and agent sessions SHOULD verify script logging and user-verification compliance
before marking work complete.

**Version**: 1.0.0 | **Ratified**: 2026-07-09 | **Last Amended**: 2026-07-09
