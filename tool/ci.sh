#!/usr/bin/env bash
# M0 CI：全包 pub get +（如有 l10n.yaml 则 gen-l10n）+ analyze + test；desktop_app 构建 Windows release。
set -euo pipefail
cd "$(dirname "$0")/.."
FAIL=0
for p in packages/* apps/desktop_app; do
  echo "== $p =="
  (cd "$p" \
    && flutter pub get \
    && if [ -f l10n.yaml ]; then flutter gen-l10n; fi \
    && flutter analyze && flutter test) || FAIL=1
done
echo "== apps/desktop_app: build windows (release) =="
(cd apps/desktop_app && flutter build windows --release) || FAIL=1
exit $FAIL
