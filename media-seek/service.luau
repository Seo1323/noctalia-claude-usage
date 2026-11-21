--!nonstrict
-- Polls MPRIS once a second, picks the active player and caches its cover art locally.
local DIR = noctalia.pluginDir()
local busy, art = false, {}
local lastTrack = nil

local function pick(players)
  for _, p in players do if p.status == "Playing" then return p end end
  return players[1]
end

local function publish(data)
  local p = pick(data.players or {})
  noctalia.state.set("media", { player = p, count = #(data.players or {}), t = noctalia.nowMs() })
end

local function poll()
  if busy then return end
  busy = true
  noctalia.runAsync({ DIR .. "/media.sh", "status" }, function(result)
    busy = false
    local ok, data = pcall(noctalia.json.decode, result.stdout or "")
    if not ok or type(data) ~= "table" then data = { players = {} } end
    local p = pick(data.players or {})
    if p and p.art ~= "" and not art[p.art] then
      local src = p.art:gsub("^file://", "")
      local dir = noctalia.pluginDataDir()
      if src ~= p.art then art[p.art] = src
      elseif dir and p.art:match("^https://") then
        local file = `{dir}/cover-{#p.art}-{p.art:sub(-16):gsub("[^%w]", "")}.jpg`
        if noctalia.fileExists(file) then art[p.art] = file
        else
          art[p.art] = "pending"
          -- download to .part and rename only on success, so a cut-off transfer is never cached
          noctalia.runAsync({ "sh", "-c", 'curl -sfL --proto =https --max-time 10 -o "$1.part" "$2" && mv "$1.part" "$1" || rm -f "$1.part"', "sh", file, p.art }, function()
            art[p.art] = if noctalia.fileExists(file) then file else nil -- nil = retry on a later poll
          end)
        end
      end
    end
    if p then local a = art[p.art]; p.cover = if a ~= "pending" then a else nil end
    publish(data)
    -- Track changed: ask Spotify whether it is already on one of the user's playlists (errors = "no")
    local id = p and tostring(p.trackid):match("^/com/spotify/track/(%w+)$")
    if id and id ~= lastTrack then
      lastTrack = id
      noctalia.runAsync({ "python3", DIR .. "/spotify.py", "playlists", id }, function(r)
        local ok2, d = pcall(noctalia.json.decode, r.stdout or "")
        local any = false
        if ok2 and type(d) == "table" and d.playlists then for _, pl in d.playlists do if pl.contains then any = true end end end
        noctalia.state.set("in_any", { track = id, value = any })
      end)
    end
  end)
end

noctalia.state.watch("cmd", function(c)
  if type(c) ~= "table" then return end
  noctalia.runAsync({ DIR .. "/media.sh", c.kind, c.bus, c.arg or "", c.arg2 or "" }, function() poll() end)
end)

function update() noctalia.setUpdateInterval(1000); poll() end
poll()
