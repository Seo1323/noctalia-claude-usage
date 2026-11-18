#!/usr/bin/env bash
# Prints the European Central Bank's daily reference rates as JSON (EUR = 1), or {"error": "..."}.
# Network: one HTTPS request to www.ecb.europa.eu; used only to show costs in a currency other than USD.
set -u
xml=$(curl -sS --max-time 10 --proto =https https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml 2>/dev/null) \
  || { printf '{"error":"network"}\n'; exit 0; }
printf '%s' "$xml" | grep -o "currency='[A-Z]\{3\}' rate='[0-9.]*'" \
  | sed "s/currency='\([A-Z]*\)' rate='\([0-9.]*\)'/\1 \2/" \
  | jq -Rnc '[inputs | split(" ") | { key: .[0], value: (.[1] | tonumber) }] | from_entries | . + { EUR: 1 }
      | if has("USD") then . else { error: "bad_response" } end' 2>/dev/null \
  || printf '{"error":"bad_response"}\n'
