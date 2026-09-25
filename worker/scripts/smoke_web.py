#!/usr/bin/env python3
"""Non-delivery smoke test for a deployed Forett Shuttle Web Worker."""

import datetime
import http.cookiejar
import json
import secrets
import sys
import urllib.request


base = sys.argv[1].rstrip("/")


def client():
    jar = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(
        urllib.request.HTTPCookieProcessor(jar),
    )
    opener.addheaders = [("User-Agent", "Mozilla/5.0 ForettApiTest")]
    opener.open(
        urllib.request.Request(
            base + "/api/session",
            method="POST",
            headers={"Origin": base},
        ),
    )
    return opener


def call(opener, path, method="GET", body=None):
    data = None if body is None else json.dumps(body).encode()
    headers = {"Origin": base}
    if data:
        headers["Content-Type"] = "application/json"
    return opener.open(
        urllib.request.Request(
            base + path,
            data=data,
            method=method,
            headers=headers,
        ),
    )


first_client = client()
second_client = client()
subscription = {
    "endpoint": "https://fcm.googleapis.com/fcm/send/forett-test",
    "expirationTime": None,
    "keys": {"p256dh": "A" * 87, "auth": "B" * 22},
}
call(first_client, "/api/push/subscription", "PUT", subscription)

departure = (
    datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(minutes=15)
).isoformat()
first_id = secrets.token_urlsafe(32)
second_id = secrets.token_urlsafe(32)


def reminder(reminder_id):
    return {
        "id": reminder_id,
        "departureAt": departure,
        "direction": "forettToBeautyWorld",
        "scheduleRevision": "revision-test",
    }


created = call(first_client, "/api/reminder", "PUT", reminder(first_id)).status
owned = json.load(call(first_client, "/api/reminder"))["reminder"]["id"] == first_id
isolated = json.load(call(second_client, "/api/reminder"))["reminder"] is None
replaced = call(first_client, "/api/reminder", "PUT", reminder(second_id)).status
call(first_client, "/api/reminder?id=" + first_id, "DELETE")
old_delete_safe = (
    json.load(call(first_client, "/api/reminder"))["reminder"]["id"] == second_id
)
call(first_client, "/api/reminder?id=" + second_id, "DELETE")
cancelled = json.load(call(first_client, "/api/reminder"))["reminder"] is None
call(first_client, "/api/push/subscription", "DELETE")

print(
    {
        "create": created,
        "owned": owned,
        "isolated": isolated,
        "replace": replaced,
        "oldDeleteSafe": old_delete_safe,
        "cancelled": cancelled,
    },
)
