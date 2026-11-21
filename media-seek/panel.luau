--!nonstrict
-- Full Media card, laid out like Noctalia's own Media tab: "Now Playing" card (cover, title, artist,
-- album, seek slider, repeat / prev / play / next / shuffle) next to a mirrored audio spectrum.
local m = noctalia.state.get("media")
local isOpen, dragging, bands = false, nil, {}

local function cmd(kind, arg, arg2)
  local p = m and m.player
  if p then noctalia.state.set("cmd", { kind = kind, bus = p.bus, arg = arg, arg2 = arg2, n = noctalia.nowMs() }) end
end
local function muted(text, size) return ui.label({ text = text, color = "on_surface_variant", fontSize = size or 13 }) end
local function card(props, nodes)
  props.padding = props.padding or 14; props.gap = props.gap or 8
  props.fill = "surface_container"; props.radius = 14; props.border = "outline_variant"; props.borderWidth = 1
  return ui.column(props, nodes)
end

local function spectrum()
  local rows = {}
  for i = 1, 40 do
    local v = tonumber(bands[math.ceil(i / 40 * math.max(#bands, 1))]) or 0
    rows[#rows + 1] = ui.box({ width = 8 + math.floor(math.clamp(v, 0, 1) * 70), height = 3, radius = 2, fill = "primary" })
  end
  return card({ align = "center", justify = "center", gap = 2, width = 120 }, rows)
end

local function render()
  if not isOpen then return end
  local p = m and m.player
  if not p then
    panel.render(card({ padding = 20 }, { muted("Nic nie gra") }))
    return
  end
  local pos = dragging or p.position
  local frac = if p.length > 0 then math.clamp(pos / p.length, 0, 1) else 0
  local looping = p.loop ~= "None"
  local function btn(glyph, active, onClick, variant)
    return ui.button({ glyph = glyph, variant = variant or (if active then "primary" else "ghost"), onClick = onClick })
  end

  local now = card({ grow = 1 }, {
    ui.row({ justify = "space_between", align = "center" }, {
      ui.label({ text = "Now Playing", fontWeight = "bold", fontSize = 16 }),
      ui.glyph({ name = "headphones", color = "on_surface_variant" }),
    }),
    if p.cover then ui.image({ path = p.cover, width = 180, height = 180, fit = "cover", radius = 8 }) else nil,
    ui.label({ text = p.title, fontWeight = "bold", fontSize = 16 }),
    muted(p.artist, 14),
    muted(p.album, 12),
    if p.canSeek and p.length > 0 then
      ui.slider({ value = frac, min = 0, max = 1,
        onChange = function(v) dragging = v * p.length; render() end,
        onChangeEnd = function(v) dragging = nil; cmd("seek", p.trackid, tostring(math.floor(v * p.length))) end })
      else ui.progress({ progress = frac, height = 6, radius = 3 }),
    ui.row({ justify = "space_between", align = "center" }, {
      btn("repeat", looping, function() cmd("loop", if looping then "None" else "Playlist") end),
      btn("player-skip-back", false, function() cmd("ctl", "Previous") end),
      btn(if p.status == "Playing" then "player-pause" else "player-play", true, function() cmd("ctl", "PlayPause") end, "primary"),
      btn("player-skip-forward", false, function() cmd("ctl", "Next") end),
      btn("arrows-shuffle", p.shuffle, function() cmd("shuffle", if p.shuffle then "false" else "true") end),
    }),
  })
  panel.render(ui.row({ padding = 8, gap = 8 }, { now, spectrum() }))
end

noctalia.state.watch("media", function(v) m = v; if not dragging then render() end end)
function onAudioSpectrum(b) if type(b) == "table" then bands = b; render() end end
function onOpen() isOpen = true; render() end
function onClose() isOpen = false; dragging = nil end
