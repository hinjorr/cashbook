#!/usr/bin/env bash
# Installs the release APK on the running emulator, opens it and waits for the
# app to log CASHBOOK_READY (home screen shown) or CASHBOOK_STARTUP_ERROR.
# Prints the app's log either way.
set -u
APK=build/app/outputs/flutter-apk/app-release.apk
PKG=com.hinjorr.cashbook

adb install -r "$APK"
adb logcat -c
adb shell am start -n "$PKG/.MainActivity"

ok=1
for i in $(seq 1 40); do
  sleep 3
  log=$(adb logcat -d -s flutter:I '*:S')
  if grep -q CASHBOOK_READY <<<"$log"; then
    echo "SMOKE TEST PASSED: home screen ready after about $((i * 3))s"
    ok=0
    break
  fi
  if grep -q CASHBOOK_STARTUP_ERROR <<<"$log"; then
    echo "SMOKE TEST FAILED: the app reported a startup error"
    break
  fi
done
[ $ok -ne 0 ] && ! grep -q CASHBOOK_STARTUP_ERROR <<<"$log" && echo "SMOKE TEST FAILED: app not ready after 120s"

echo "----- flutter log -----"
adb logcat -d -s flutter:V '*:S' | tail -80
echo "----- crashes -----"
adb logcat -d -b crash | tail -60
adb logcat -d | grep -E "AndroidRuntime|FATAL" | grep -v uiautomator | tail -40
exit $ok
