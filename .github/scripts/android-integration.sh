#!/usr/bin/env bash
set -euo pipefail

device=emulator-5554
package=com.forett.shuttle_bus

# Keep an existing debug installation's preferences before the mock-backed tests.
if adb -s "$device" shell run-as "$package" test -d shared_prefs 2>/dev/null; then
  backup_dir=$(mktemp -d)
  adb -s "$device" exec-out run-as "$package" tar -cf - shared_prefs > "$backup_dir/preferences.tar"
fi

restore_app() {
  test_status=$?
  trap - EXIT
  # Always replace the integration-test entrypoint, including after a failure.
  if flutter build apk --debug &&
    adb -s "$device" install -r build/app/outputs/flutter-apk/app-debug.apk; then
    exit "$test_status"
  fi
  exit 1
}
trap restore_app EXIT

flutter test integration_test/app_test.dart -d "$device" --no-uninstall
