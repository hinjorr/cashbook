#!/usr/bin/env bash
# Installs the release APK on the running emulator, opens it and checks that
# the home screen appears. Prints the app's log either way.
set -u
APK=build/app/outputs/flutter-apk/app-release.apk
PKG=com.hinjorr.cashbook

adb install -r "$APK"
adb logcat -c
adb shell am start -W -n "$PKG/.MainActivity"

ok=1
for i in $(seq 1 30); do
  sleep 3
  adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1
  ui=$(adb shell cat /sdcard/ui.xml 2>/dev/null)
  if grep -q 'text="Transactions"' <<<"$ui"; then
    echo "SMOKE TEST PASSED: home screen visible after $((i * 3))s"
    ok=0
    break
  fi
  if grep -q 'could not start' <<<"$ui"; then
    echo "SMOKE TEST FAILED: app showed its startup error screen"
    break
  fi
done

echo "----- visible text -----"
grep -o 'text="[^"]*"' <<<"$ui" | grep -v 'text=""' | head -60
echo "----- app log -----"
adb logcat -d -v brief | grep -E "flutter|AndroidRuntime|$PKG|FATAL|Exception" | tail -150
exit $ok
