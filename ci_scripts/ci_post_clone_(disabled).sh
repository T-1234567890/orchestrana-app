#!/bin/sh

echo "=== Firebase Restore Script ==="

TARGET="${SRCROOT}/macos/Pomodoro/Pomodoro/GoogleService-Info.plist"

if [ -z "$FIREBASE_PLIST_BASE64" ]; then
  echo "⚠ No FIREBASE_PLIST_BASE64 — using dummy plist"
  exit 0
fi

mkdir -p "$(dirname "$TARGET")"

echo "Decoding Firebase config..."

printf "%s" "$FIREBASE_PLIST_BASE64" | base64 --decode > "$TARGET" 2>/dev/null || \
printf "%s" "$FIREBASE_PLIST_BASE64" | base64 -D > "$TARGET"

if [ -s "$TARGET" ]; then
  echo "✅ Firebase restored"
else
  echo "⚠ Firebase decode failed — continuing anyway"
fi

exit 0