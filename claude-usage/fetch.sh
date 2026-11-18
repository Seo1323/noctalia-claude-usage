#!/usr/bin/env bash
# Prints one JSON line with Claude Code rate-limit usage, or {"error": "..."}.
# Reads the OAuth token Claude Code already stores; never writes or refreshes it.
set -u
CREDS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.credentials.json"
fail() { jq -nc --arg e "$1" '{error:$e}'; exit 0; }

[ -r "$CREDS" ] || fail no_credentials
exp=$(jq -r '.claudeAiOauth.expiresAt // 0' "$CREDS" 2>/dev/null) || fail no_credentials
[ "$exp" -gt "$(( $(date +%s) * 1000 ))" ] 2>/dev/null || fail token_expired

resp=$(jq -r '"header = " + ("Authorization: Bearer " + .claudeAiOauth.accessToken | @json)' "$CREDS" \
  | curl -sS --max-time 10 -K - \
      -H "anthropic-beta: oauth-2025-04-20" \
      -H "Content-Type: application/json" \
      -w $'\n%{http_code}' \
      https://api.anthropic.com/api/oauth/usage 2>/dev/null) || fail network
code=${resp##*$'\n'}
body=${resp%$'\n'*}
[ "$code" = 200 ] || fail "http_$code"

usage=$(printf '%s' "$body" | jq -c '
  def ep: if . == null then null else (sub("\\.[0-9]+";"") | sub("\\+00:00$";"Z") | fromdateiso8601) end;
  { five_hour:   (.five_hour.utilization // null),
    five_reset:  (.five_hour.resets_at | ep),
    weekly:      (.seven_day.utilization // null),
    weekly_reset:(.seven_day.resets_at | ep) }' 2>/dev/null) || fail bad_response

# Token counts come from Claude Code's local transcripts (the API has none).
# Counted: input + output + cache-creation tokens, deduplicated per message id,
# inside the current 5h / weekly windows (window start = reset time - length).
# Cache reads are summed separately (*_cache_read) so the widget can add them on demand.
PROJECTS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"
now_s=$(date +%s)
f5=$(jq -n --argjson u "$usage" --argjson n "$now_s" 'if ($u.five_reset // 0) > $n then $u.five_reset - 18000 else $n + 1 end')
fw=$(jq -n --argjson u "$usage" --argjson n "$now_s" 'if ($u.weekly_reset // 0) > $n then $u.weekly_reset - 604800 else $n + 1 end')
tokens=$( { [ -d "$PROJECTS" ] && find "$PROJECTS" -name '*.jsonl' -mtime -8 -print0 2>/dev/null | xargs -0 -r cat; } \
  | jq -Rc 'fromjson? | select(.type == "assistant" and .message.usage != null)
      | { k: (.message.id // .uuid // empty),
          t: (.timestamp | sub("\\.[0-9]+";"") | fromdateiso8601),
          n: ((.message.usage.input_tokens // 0) + (.message.usage.output_tokens // 0)
              + (.message.usage.cache_creation_input_tokens // 0)),
          c: (.message.usage.cache_read_input_tokens // 0) }' 2>/dev/null \
  | jq -sc --argjson f5 "$f5" --argjson fw "$fw" '
      group_by(.k) | map(last)
      | { five_tokens:       (map(select(.t >= $f5) | .n) | add // 0),
          weekly_tokens:     (map(select(.t >= $fw) | .n) | add // 0),
          five_cache_read:   (map(select(.t >= $f5) | .c) | add // 0),
          weekly_cache_read: (map(select(.t >= $fw) | .c) | add // 0) }' 2>/dev/null) || tokens='{"five_tokens":null,"weekly_tokens":null}'
[ -n "$tokens" ] || tokens='{"five_tokens":null,"weekly_tokens":null}'

jq -nc --argjson a "$usage" --argjson b "$tokens" '$a + $b'
