#!/usr/bin/env bash
# Downloads Scryfall's bulk card data (oracle cards and default cards) into a directory, the
# polite way: one request to the bulk-data index, then the two published files. Scryfall asks
# for bulk files instead of per-card API calls and for a descriptive User-Agent.
#
#   tools/fetch_scryfall.sh .scryfall-cache
set -euo pipefail
out="${1:-.scryfall-cache}"
mkdir -p "$out"
ua="OpenMTG/1.0 (+https://github.com/Coral-coder/openmtg)"
index=$(curl -fsSL -H "User-Agent: $ua" -H "Accept: application/json" https://api.scryfall.com/bulk-data)
for kind in oracle_cards default_cards; do
  url=$(printf '%s' "$index" | python3 -c "import json,sys; d=json.load(sys.stdin)['data']; b=[x for x in d if x['type']=='$kind'][0]; print(b.get('jsonl_download_uri') or b['download_uri'])")
  file="$out/${kind//_/-}.jsonl.gz"
  case "$url" in *.gz) ;; *) file="$out/${kind//_/-}.json" ;; esac
  echo "Fetching $kind from $url"
  curl -fsSL -H "User-Agent: $ua" -o "$file" "$url"
  ls -la "$file"
done
