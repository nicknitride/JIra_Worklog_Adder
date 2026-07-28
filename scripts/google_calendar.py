#!/usr/bin/env python3
"""Google Calendar OAuth and event fetch helper for worklog-tui."""

from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import date, datetime, timedelta, timezone
from typing import Any
from zoneinfo import ZoneInfo

SCOPES = ["https://www.googleapis.com/auth/calendar.readonly"]
LOCAL_TZ = ZoneInfo(os.environ.get("TZ", "Asia/Manila"))


def _parse_dt(value: str, all_day: bool) -> datetime:
    if all_day:
        return datetime.strptime(value[:10], "%Y-%m-%d").replace(tzinfo=LOCAL_TZ)
    if value.endswith("Z"):
        value = value[:-1] + "+00:00"
    parsed = datetime.fromisoformat(value)
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed


def _to_local(dt: datetime) -> datetime:
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(LOCAL_TZ)


def _duration_minutes(start: datetime, end: datetime, all_day: bool) -> int:
    if all_day:
        return 480
    delta = end - start
    return max(int(delta.total_seconds() // 60), 1)


def _response_status(event: dict[str, Any]) -> str:
    attendees = event.get("attendees") or []
    for attendee in attendees:
        if attendee.get("self"):
            return attendee.get("responseStatus", "accepted")
    return event.get("status", "confirmed")


def normalize_event(event: dict[str, Any]) -> dict[str, Any]:
    start_raw = event.get("start", {})
    end_raw = event.get("end", {})
    all_day = "date" in start_raw and "dateTime" not in start_raw
    start_val = start_raw.get("dateTime") or start_raw.get("date", "")
    end_val = end_raw.get("dateTime") or end_raw.get("date", "")
    start_dt = _parse_dt(start_val, all_day)
    end_dt = _parse_dt(end_val, all_day)
    if all_day and end_val:
        end_dt = end_dt - timedelta(seconds=1)
    start_local = _to_local(start_dt)
    end_local = _to_local(end_dt)
    return {
        "id": event.get("id", ""),
        "title": event.get("summary", "(no title)"),
        "eventDate": start_local.date().isoformat(),
        "startTime": start_local.isoformat(),
        "endTime": end_local.isoformat(),
        "durationMinutes": _duration_minutes(start_dt, end_dt, all_day),
        "responseStatus": _response_status(event),
        "allDay": all_day,
    }


def cmd_oauth(args: argparse.Namespace) -> int:
    try:
        from google_auth_oauthlib.flow import InstalledAppFlow
    except ImportError:
        print("Missing google-auth-oauthlib. Run: pip3 install -r scripts/requirements.txt", file=sys.stderr)
        return 2

    client_config = {
        "installed": {
            "client_id": args.client_id,
            "client_secret": args.client_secret,
            "auth_uri": "https://accounts.google.com/o/oauth2/auth",
            "token_uri": "https://oauth2.googleapis.com/token",
            "redirect_uris": [f"http://localhost:{args.port}/"],
        }
    }
    flow = InstalledAppFlow.from_client_config(client_config, SCOPES)
    creds = flow.run_local_server(port=args.port, open_browser=True)
    refresh = creds.refresh_token
    if not refresh:
        print("No refresh token returned. Revoke app access and retry.", file=sys.stderr)
        return 2
    print(json.dumps({"refresh_token": refresh, "status": "ok"}))
    return 0


def cmd_events(args: argparse.Namespace) -> int:
    try:
        from google.oauth2.credentials import Credentials
        from googleapiclient.discovery import build
    except ImportError:
        print("Missing Google libraries. Run: pip3 install -r scripts/requirements.txt", file=sys.stderr)
        return 2

    if not args.refresh_token:
        print("GOOGLE_REFRESH_TOKEN is required for events fetch", file=sys.stderr)
        return 2

    creds = Credentials(
        token=None,
        refresh_token=args.refresh_token,
        token_uri="https://oauth2.googleapis.com/token",
        client_id=args.client_id,
        client_secret=args.client_secret,
        scopes=SCOPES,
    )
    try:
        from google.auth.transport.requests import Request

        if not creds.valid:
            if not creds.refresh_token:
                print("No refresh token available. Re-run OAuth.", file=sys.stderr)
                return 2
            creds.refresh(Request())

        service = build("calendar", "v3", credentials=creds, cache_discovery=False)
        start_date = date.fromisoformat(args.date_from)
        end_date = date.fromisoformat(args.date_to) + timedelta(days=1)
        time_min = datetime.combine(start_date, datetime.min.time(), tzinfo=LOCAL_TZ).isoformat()
        time_max = datetime.combine(end_date, datetime.min.time(), tzinfo=LOCAL_TZ).isoformat()
        result = (
            service.events()
            .list(
                calendarId=args.calendar_id,
                timeMin=time_min,
                timeMax=time_max,
                singleEvents=True,
                orderBy="startTime",
            )
            .execute()
        )
    except Exception as exc:  # noqa: BLE001
        print(f"Calendar API error: {exc}", file=sys.stderr)
        return 3

    events = [normalize_event(e) for e in result.get("items", [])]
    print(json.dumps({"events": events}))
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Google Calendar helper for worklog-tui")
    sub = parser.add_subparsers(dest="command", required=True)

    oauth_p = sub.add_parser("oauth")
    oauth_p.add_argument("--client-id", required=True)
    oauth_p.add_argument("--client-secret", required=True)
    oauth_p.add_argument("--port", type=int, default=8080)

    events_p = sub.add_parser("events")
    events_p.add_argument("--calendar-id", default="primary")
    events_p.add_argument("--from", dest="date_from", required=True)
    events_p.add_argument("--to", dest="date_to", required=True)
    events_p.add_argument("--refresh-token", required=True)
    events_p.add_argument("--client-id", required=True)
    events_p.add_argument("--client-secret", required=True)

    args = parser.parse_args()
    if args.command == "oauth":
        return cmd_oauth(args)
    if args.command == "events":
        return cmd_events(args)
    return 1


if __name__ == "__main__":
    sys.exit(main())
