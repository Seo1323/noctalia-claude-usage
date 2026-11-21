--!nonstrict
-- Panel: your editable Spotify playlists, tick = the current track is in it. Click toggles (like the Android app).
local DIR = noctalia.pluginDir()
local SCRIPT = DIR .. "/spotify.py"
local isOpen, status, lists, busy, err = false, "loading", {}, {}, nil
local trackId, title = nil, ""

local function currentTrack()
  local m = noctalia.state.get("media")
  local p = m and m.player
  if not p then return nil, "" end
  return tostring(p.trackid):match("^/com/spotify/track/(%w+)$"), p.title
end

local function muted(text) return ui.label({ text = text, color = "on_surface_variant", fontSize = 13 }) end
local render

local function run(args, cb)
  local cmd = { "python3", SCRIPT }
  for _, a in args do cmd[#cmd + 1] = a end
  noctalia.runAsync(cmd, function(r)
    local ok, data = pcall(noctalia.json.decode, r.stdout or "")
    cb(if ok and type(data) == "table" then data else { error = "bad_response" })
  end)
end

local function load()
  trackId, title = currentTrack()
  if not trackId then status = "no_track"; return render() end
  status = "loading"; render()
  run({ "playlists", trackId }, function(d)
    if d.error then status, err = d.error, d.error else status, lists = "ready", d.playlists or {} end
    render()
  end)
end

local function toggle(p)
  if busy[p.id] then return end
  busy[p.id] = true
  local want = not p.contains
  p.contains = want; render() -- optimistic; undone below if Spotify refuses
  run({ if want then "add" else "remove", p.id, trackId }, function(d)
    busy[p.id] = nil
    if d.error then p.contains = not want; err = d.error else err = nil end
    render()
  end)
end

function render()
  if not isOpen then return end
  local kids = { ui.label({ text = "Dodaj do playlisty", fontWeight = "bold", fontSize = 16 }) }
  local function add(n) kids[#kids + 1] = n end
  if status == "no_client_id" then
    add(muted("Brak Client ID. Utwórz aplikację na developer.spotify.com (Redirect URI: http://127.0.0.1:8888/callback) i zapisz Client ID w pliku ~/.config/media-seek/client_id"))
  elseif status == "not_logged_in" or status == "http_401" or status == "http_400" then
    add(muted("Zaloguj się do Spotify, żeby zarządzać playlistami."))
    add(ui.button({ text = "Zaloguj", glyph = "brand-spotify", variant = "primary", onClick = function()
      run({ "login" }, function(d) if d.error then status = d.error; err = d.error; return render() end load() end)
    end }))
  elseif status == "no_track" then
    add(muted("Gra utwór spoza Spotify albo nic nie gra."))
  elseif status == "loading" then
    add(muted("Ładowanie…"))
  elseif status ~= "ready" then
    add(muted("Błąd: " .. tostring(status)))
    add(ui.button({ text = "Spróbuj ponownie", variant = "ghost", onClick = load }))
  else
    add(muted(title))
    local rows = {}
    for _, p in lists do
      rows[#rows + 1] = ui.button({ text = p.name, glyph = if p.contains then "circle-check" else "circle-plus",
        variant = if p.contains then "primary" else "ghost", onClick = function() toggle(p) end })
    end
    if #rows == 0 then add(muted("Brak playlist, które możesz edytować.")) else add(ui.scroll({ height = 380 }, { ui.column({ gap = 4 }, rows) })) end
    if err then add(ui.label({ text = "Nie udało się: " .. err, color = "error", fontSize = 12 })) end
  end
  panel.render(ui.column({ padding = 14, gap = 8 }, kids))
end

function onOpen() isOpen = true; err = nil; load() end
function onClose() isOpen = false end
