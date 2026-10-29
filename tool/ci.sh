#!/usr/bin/env bash
# M0 CI：全包 pub get + analyze + test；desktop_app 构建 Windows release。
set -euo pipefail
cd "$(dirname "$0")/.."
FAIL=0
for p in packages/* apps/desktop_app; do
  echo "== $p =="
  (cd "$p" && flutter pub get && flutter analyze && flutter test) || FAIL=1
done
echo "== apps/desktop_app: build windows (release) =="
(cd apps/desktop_app && flutter build windows --release) || FAIL=1
exit $FAIL
