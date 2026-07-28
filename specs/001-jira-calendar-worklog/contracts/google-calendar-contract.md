# Google Calendar API Contract

**Version**: 1.0.0 | **Helper**: `scripts/google_calendar.py`

## Authentication Flow

### First run (no `GOOGLE_REFRESH_TOKEN`)

1. Python starts local server on `GOOGLE_OAUTH_PORT` (default 8080)
2. Opens browser to Google consent URL
3. User approves `calendar.readonly` scope
4. Script receives auth code → exchanges for refresh + access token
5. Bash prompts user to confirm before appending `GOOGLE_REFRESH_TOKEN` to `.env`

### Subsequent runs

1. Python reads refresh token from env
2. Refreshes access token silently
3. Calls Calendar API

## CLI Interface (Python helper)

Bash invokes the helper via subprocess; stdout is JSON, stderr is diagnostics.

### OAuth init

```bash
python3 scripts/google_calendar.py oauth \
  --client-id "$GOOGLE_CLIENT_ID" \
  --client-secret "$GOOGLE_CLIENT_SECRET" \
  --port "${GOOGLE_OAUTH_PORT:-8080}"
```

**stdout on success**:
```json
{ "refresh_token": "...", "status": "ok" }
```

### List events

```bash
python3 scripts/google_calendar.py events \
  --calendar-id "${GOOGLE_CALENDAR_ID:-primary}" \
  --from "2026-07-07" \
  --to "2026-07-13" \
  --refresh-token "$GOOGLE_REFRESH_TOKEN" \
  --client-id "$GOOGLE_CLIENT_ID" \
  --client-secret "$GOOGLE_CLIENT_SECRET"
```

**stdout**:
```json
{
  "events": [
    {
      "id": "abc123",
      "title": "Sprint Planning",
      "startTime": "2026-07-09T09:00:00+08:00",
      "endTime": "2026-07-09T10:30:00+08:00",
      "durationMinutes": 90,
      "responseStatus": "accepted",
      "allDay": false
    }
  ]
}
```

**Exit codes**: 0 success, 2 auth error, 3 API error

## Google Calendar API (underlying)

```http
GET https://www.googleapis.com/calendar/v3/calendars/{calendarId}/events
  ?timeMin={RFC3339}
  &timeMax={RFC3339}
  &singleEvents=true
  &orderBy=startTime
Authorization: Bearer {access_token}
```

## Event Normalization (bash layer)

After receiving JSON from Python, `lib/calendar-api.sh` applies:

| Condition | Action |
|-----------|--------|
| `responseStatus` = `declined` or `cancelled` | DROP |
| `allDay` = true | KEEP, set `warning: ALL_DAY`, default duration 480 min |
| `responseStatus` = `tentative` | KEEP, set `warning: TENTATIVE` |
| otherwise | KEEP, no warning |

## Audit Log Actions

| Action key | When |
|------------|------|
| `google.oauth.start` | Browser flow initiated |
| `google.oauth.complete` | Refresh token obtained |
| `google.oauth.token_saved` | After user confirms `.env` write |
| `google.calendar.fetch` | Events fetched for date range |
| `google.calendar.filter` | Count before/after declined filter |

## Security

- Refresh token and client secret passed via env to Python, never argv
- Tokens never written to `logs/*.txt`
- `google_api_oauth_details.txt` not used at runtime — `.env` only
