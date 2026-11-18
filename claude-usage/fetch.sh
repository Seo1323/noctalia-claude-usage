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

# The 3 most recent sessions (top-level transcripts; subagent runs live in subfolders), for the
# panel's "Resume a session" buttons: id, project folder, last activity and the first prompt.
sessions=$(find "$DIR/projects" -mindepth 2 -maxdepth 2 -name '*.jsonl' -printf '%T@ %p\n' 2>/dev/null \
  | sort -rn | head -3 | while read -r mtime file; do
      jq -c --arg id "$(basename "$file" .jsonl)" --argjson t "${mtime%.*}" -n '
        [inputs] as $l
        | { id: $id, t: $t,
            cwd: ([$l[] | .cwd | strings] | first),
            prompt: ([$l[] | select(.type == "user") | .message.content
                      | if type == "string" then . else ([.[]? | select(.type == "text") | .text] | join(" ")) end
                      | select(type == "string" and length > 0 and (startswith("<") | not))] | first // "" | .[0:60]) }
        | select(.cwd != null)' "$file" 2>/dev/null
    done | jq -sc '.' 2>/dev/null)
[ -n "$sessions" ] || sessions='[]'

# Tokens per message (deduplicated by id) inside each window (start = reset - length):
# input + output + cache creation, with cache reads summed separately. Also per model
# for both windows (with the input / output / cache split used for cost estimates), and
# series for the panel graphs (24 hourly / 7 daily buckets).
find "$DIR/projects" -name '*.jsonl' -mtime -8 -print0 2>/dev/null \
| xargs -0 -r grep -hF '"usage"' 2>/dev/null \
| jq -Rnc --argjson now "$(date +%s)" --argjson api "${resp%$'\n'*}" --argjson sessions "$sessions" '
    def ts: sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdateiso8601;
    def start($r; $len): if $r != null and $r > $now then $r - $len else $now + 1 end;
    ($api.five_hour.resets_at | values | ts) as $r5
    | ($api.seven_day.resets_at | values | ts) as $rw
    | [inputs | fromjson? | select(.type == "assistant" and .message.usage != null)
        | .message.usage as $u
        | ($u.cache_creation_input_tokens // 0) as $w
        | ($u.cache_creation.ephemeral_1h_input_tokens // 0) as $w1
        | { k: (.message.id // .uuid), t: ((.timestamp | ts)? // 0), model: (.message.model // ""),
            i: ($u.input_tokens // 0), o: ($u.output_tokens // 0), w5: ($w - $w1), w1: $w1,
            n: (($u.input_tokens // 0) + ($u.output_tokens // 0) + $w),
            c: ($u.cache_read_input_tokens // 0) }]
    | (group_by(.k) | map(last)) as $m
    | def total(f; $from): [$m[] | select(.t >= $from) | f] | add // 0;
      def models($from): [$m[] | select(.t >= $from and .model != "" and (.model | startswith("<") | not))]
        | group_by(.model) | map({ model: .[0].model, tokens: (map(.n) | add), cache_read: (map(.c) | add), messages: length,
            input: (map(.i) | add), output: (map(.o) | add), cache_write_5m: (map(.w5) | add), cache_write_1h: (map(.w1) | add) })
        | sort_by(-.tokens);
      def series($size; $count): ([$m[] | (($now - .t) / $size | floor) as $b | select($b >= 0 and $b < $count)
          | { b: ($count - 1 - $b), n }] | group_by(.b) | map({ key: (.[0].b | tostring), value: (map(.n) | add) }) | from_entries) as $g
        | [range(0; $count) | $g[tostring] // 0];
      { five_hour: $api.five_hour.utilization, five_reset: $r5,
        weekly: $api.seven_day.utilization, weekly_reset: $rw,
        five_tokens: total(.n; start($r5; 18000)), weekly_tokens: total(.n; start($rw; 604800)),
        five_cache_read: total(.c; start($r5; 18000)), weekly_cache_read: total(.c; start($rw; 604800)),
        five_models: models(start($r5; 18000)), weekly_models: models(start($rw; 604800)),
        hourly: series(3600; 24), daily: series(86400; 7), recent_sessions: $sessions,
        last_model: ([$m[] | select(.model != "" and (.model | startswith("<") | not))] | max_by(.t) | .model?) }' 2>/dev/null \
|| fail bad_response
