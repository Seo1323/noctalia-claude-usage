#!/usr/bin/env bash
# Prints one JSON line with Claude Code usage, or {"error": "..."}.
# Network: one HTTPS request to api.anthropic.com, authenticated with the OAuth token
# Claude Code already stores (read only - never written or refreshed).
# Token counts come from local transcripts, because the API has none.
set -u
DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CREDS="$DIR/.credentials.json"
fail() { printf '{"error":"%s"}\n' "$1"; exit 0; }

[ -r "$CREDS" ] || fail no_credentials
exp=$(jq -r '.claudeAiOauth.expiresAt // 0' "$CREDS" 2>/dev/null) || fail no_credentials
[ "${exp%.*}" -gt "$(( $(date +%s) * 1000 ))" ] 2>/dev/null || fail token_expired

# The token reaches curl as a config file on stdin, so it never appears in argv / ps.
resp=$(jq -r '"header = " + ("Authorization: Bearer " + .claudeAiOauth.accessToken | @json)' "$CREDS" \
  | curl -sS --max-time 10 --proto =https -K - \
      -H "anthropic-beta: oauth-2025-04-20" \
      -w $'\n%{http_code}' \
      https://api.anthropic.com/api/oauth/usage 2>/dev/null) || fail network
[ "${resp##*$'\n'}" = 200 ] || fail "http_${resp##*$'\n'}"

# Tokens per message (deduplicated by id) inside each window (start = reset - length):
# input + output + cache creation, with cache reads summed separately.
find "$DIR/projects" -name '*.jsonl' -mtime -8 -print0 2>/dev/null \
| xargs -0 -r grep -hF '"usage"' 2>/dev/null \
| jq -Rnc --argjson now "$(date +%s)" --argjson api "${resp%$'\n'*}" '
    def ts: sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdateiso8601;
    def start($r; $len): if $r != null and $r > $now then $r - $len else $now + 1 end;
    ($api.five_hour.resets_at | values | ts) as $r5
    | ($api.seven_day.resets_at | values | ts) as $rw
    | [inputs | fromjson? | select(.type == "assistant" and .message.usage != null)
        | .message.usage as $u
        | { k: (.message.id // .uuid), t: ((.timestamp | ts)? // 0),
            n: (($u.input_tokens // 0) + ($u.output_tokens // 0) + ($u.cache_creation_input_tokens // 0)),
            c: ($u.cache_read_input_tokens // 0) }]
    | (group_by(.k) | map(last)) as $m
    | def total(f; $from): [$m[] | select(.t >= $from) | f] | add // 0;
      { five_hour: $api.five_hour.utilization, five_reset: $r5,
        weekly: $api.seven_day.utilization, weekly_reset: $rw,
        five_tokens: total(.n; start($r5; 18000)), weekly_tokens: total(.n; start($rw; 604800)),
        five_cache_read: total(.c; start($r5; 18000)), weekly_cache_read: total(.c; start($rw; 604800)) }' 2>/dev/null \
|| fail bad_response
