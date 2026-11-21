#!/usr/bin/env bash
# media.sh status          -> JSON {players:[...]} (one entry per MPRIS player)
# media.sh ctl  <bus> <PlayPause|Next|Previous>
# media.sh seek <bus> <trackid> <microseconds>   (absolute position)
# media.sh volume <bus> <0..1>
# media.sh shuffle <bus> <true|false>   |   media.sh loop <bus> <None|Track|Playlist>
set -u
B=(busctl --user --json=short)
P=/org/mpris/MediaPlayer2 I=org.mpris.MediaPlayer2.Player
valid() { [[ $1 =~ ^org\.mpris\.MediaPlayer2\.[A-Za-z0-9_.-]+$ ]]; }
case "${1:-status}" in
  ctl)  valid "$2" && [[ $3 =~ ^(PlayPause|Next|Previous)$ ]] && busctl --user call "$2" $P $I "$3" >/dev/null 2>&1; exit 0 ;;
  seek) valid "$2" && [[ $3 =~ ^/[A-Za-z0-9_/]*$ ]] && [[ $4 =~ ^[0-9]+$ ]] && busctl --user call "$2" $P $I SetPosition ox "$3" "$4" >/dev/null 2>&1; exit 0 ;;
  volume)  valid "$2" && [[ $3 =~ ^(0(\.[0-9]+)?|1(\.0+)?)$ ]] && busctl --user set-property "$2" $P $I Volume d "$3" >/dev/null 2>&1; exit 0 ;;
  shuffle) valid "$2" && [[ $3 =~ ^(true|false)$ ]] && busctl --user set-property "$2" $P $I Shuffle b "$3" >/dev/null 2>&1; exit 0 ;;
  loop)    valid "$2" && [[ $3 =~ ^(None|Track|Playlist)$ ]] && busctl --user set-property "$2" $P $I LoopStatus s "$3" >/dev/null 2>&1; exit 0 ;;
esac
out='[]'
for bus in $("${B[@]}" list 2>/dev/null | jq -r '.[].name | select(startswith("org.mpris.MediaPlayer2."))'); do
  # $1 = property, $2 = JSON default when the player lacks it or busctl fails
  g() { "${B[@]}" get-property "$bus" $P $I "$1" 2>/dev/null | jq -ce '.data' 2>/dev/null || echo "$2"; }
  # artist is "as" for most players but a plain string for some
  entry=$(jq -c --arg bus "$bus" --argjson st "$(g PlaybackStatus null)" --argjson pos "$(g Position 0)" \
    --argjson seek "$(g CanSeek false)" --argjson vol "$(g Volume 1)" --argjson shuf "$(g Shuffle false)" --argjson loop "$(g LoopStatus '"None"')" \
    --argjson m "$(g Metadata '{}')" '{
      bus: $bus, status: $st, position: ($pos // 0), canSeek: $seek, shuffle: $shuf, volume: $vol, loop: $loop,
      title: ($m["xesam:title"].data // ""),
      artist: (($m["xesam:artist"].data // "") | if type == "array" then join(", ") else tostring end),
      album: ($m["xesam:album"].data // ""), art: ($m["mpris:artUrl"].data // ""),
      length: ($m["mpris:length"].data // 0), trackid: ($m["mpris:trackid"].data // "/")}' <<<null 2>/dev/null) \
    && out=$(jq -c --argjson e "$entry" '. + [$e]' <<<"$out") # a bad player is skipped, not fatal
done
jq -nc --argjson p "$out" '{players:$p}'
