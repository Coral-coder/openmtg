#!/usr/bin/env bash
# Plays the same seeded games on the Dart VM and as JavaScript (as in the browser) and fails if
# any fingerprint differs.  tool/xplat_check.sh <cards.json> [games] [--random-decks]
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
dart compile js -O2 -o "$out/xplat.js" tool/xplat.dart >/dev/null
dart run tool/xplat.dart "$@" > "$out/vm.txt"
# dart2js output looks for require on globalThis; Node keeps it module-local.
node -e "globalThis.require = require; require(process.argv[1])" "$out/xplat.js" "$@" > "$out/js.txt"
if diff "$out/vm.txt" "$out/js.txt"; then
  echo "VM and JavaScript agree on $(wc -l < "$out/vm.txt") games"
else
  echo "VM and JavaScript disagree" >&2
  exit 1
fi
