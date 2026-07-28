# Jira REST API Contract

**Version**: 1.0.0 | **Base URL**: `{ATLASSIAN_BASE_URL}` | **Auth**: Basic (email + API token)

## Authentication

```http
Authorization: Basic base64({ATLASSIAN_EMAIL}:{ATLASSIAN_API_TOKEN})
Accept: application/json
Content-Type: application/json
```

## Endpoints Used

### 1. Validate credentials

```http
GET /rest/api/3/myself
```

**Success**: `200` with `accountId`, `emailAddress`

**Failure**: `401` → exit code 3

---

### 2. Get active sprint

```http
GET /rest/agile/1.0/board/{JIRA_BOARD_ID}/sprint?state=active
```

**Success**: `200` — use first sprint in `values[]`

**Response fields used**:
- `values[0].id` → sprintId
- `values[0].name`
- `values[0].startDate`, `values[0].endDate`

**Failure**: empty `values` → WARN, continue with empty ticket list

---

### 3. List sprint issues

```http
GET /rest/agile/1.0/sprint/{sprintId}/issue?maxResults=100
```

**Response fields used** (per issue):
- `key`
- `fields.summary`
- `fields.labels`
- `fields.status.name`

**Client filter**: keep issues where `fields.labels` contains `JIRA_LOGGING_LABEL`

---

### 4. Create worklog

```http
POST /rest/api/3/issue/{issueKey}/worklog
```

**Request body**:
```json
{
  "comment": {
    "type": "doc",
    "version": 1,
    "content": [
      {
        "type": "paragraph",
        "content": [
          { "type": "text", "text": "{eventTitle}" }
        ]
      }
    ]
  },
  "started": "{ISO8601 with timezone offset}",
  "timeSpentSeconds": {durationMinutes * 60}
}
```

**Success**: `201` with worklog `id`

**Failure**: `4xx/5xx` → log ERROR, skip entry, continue or abort based on user choice

**Dry-run**: Do not call — log `[DRY-RUN] would POST worklog ...`

---

## Rate Limiting

- On `429`: wait 2s, retry once
- On second failure: ERROR log, surface message in TUI

## Audit Log Actions

| Action key | When |
|------------|------|
| `jira.auth.validate` | After `/myself` |
| `jira.sprint.load` | After active sprint fetch |
| `jira.issues.filter` | After label filter with count |
| `jira.worklog.submit` | Before/after each POST |
| `jira.worklog.dry_run` | Dry-run preview |
