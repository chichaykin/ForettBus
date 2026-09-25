PRAGMA foreign_keys = ON;

CREATE TABLE installations (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  session_hash TEXT NOT NULL UNIQUE,
  created_at TEXT NOT NULL,
  last_seen_at TEXT NOT NULL,
  expires_at TEXT NOT NULL
);

CREATE TABLE push_subscriptions (
  installation_id INTEGER PRIMARY KEY REFERENCES installations(id) ON DELETE CASCADE,
  endpoint TEXT NOT NULL,
  p256dh TEXT NOT NULL,
  auth TEXT NOT NULL,
  version INTEGER NOT NULL DEFAULT 1,
  updated_at TEXT NOT NULL
);

CREATE TABLE reminders (
  id TEXT PRIMARY KEY,
  installation_id INTEGER NOT NULL REFERENCES installations(id) ON DELETE CASCADE,
  departure_at TEXT NOT NULL,
  send_at TEXT NOT NULL,
  direction TEXT NOT NULL CHECK(direction IN ('forettToBeautyWorld', 'beautyWorldToForett')),
  schedule_revision TEXT NOT NULL,
  status TEXT NOT NULL CHECK(status IN ('active', 'queued', 'sending', 'sent', 'cancelled', 'replaced', 'failed')),
  attempts INTEGER NOT NULL DEFAULT 0,
  subscription_version INTEGER,
  locked_until TEXT,
  last_error TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE UNIQUE INDEX one_current_reminder_per_installation
ON reminders(installation_id)
WHERE status IN ('active', 'queued', 'sending');

CREATE INDEX due_reminders ON reminders(status, send_at, locked_until);
CREATE INDEX reminders_by_installation ON reminders(installation_id, updated_at DESC);
CREATE INDEX expired_installations ON installations(expires_at);
