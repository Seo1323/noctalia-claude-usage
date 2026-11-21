--!nonstrict
-- One capsule: [volume icon] [add-to-playlist icon] [marquee title + spinning cover].
--   title  : hover = seek card, click = full Media panel
--   plus   : click = playlist menu (green check when the track is already on a playlist)
--   volume : hover = vertical volume card
local m, any = noctalia.state.get("media"), noctalia.state.get("in_any")
local ART = tonumber(noctalia.getConfig("art_size")) or 18
local MAXW = tonumber(noctalia.getConfig("max_length")) or 260
local SPIN = noctalia.getConfig("rotate_cover") ~= false
local HIDE = noctalia.getConfig("hide_when_idle") ~= false
local FONT, ICON, ADD_ICON, GREEN = 13, 22, 19, "#1ed760"
local CHAR = FONT * 0.55 -- rough glyph width; shortcut: no text measuring API, upgrade if one appears
local WINDOW = math.max(8, math.floor(MAXW / CHAR))
local offset, angle = 0, 0
local lastTick = noctalia.nowMs()

-- A hover card that opens on enter and closes shortly after leaving, unless the pointer is on the card.
-- The card publishes its real state (openKey / keepKey) from its onOpen/onClose/pointer handlers.
local function hoverCard(panelId, openKey, keepKey)
  local card, leaveAt = {}, nil
  local function isOpen() return noctalia.state.get(openKey) == true end
  function card.hover(state)
    if tostring(state) == "true" then
      leaveAt = nil
      if not isOpen() then noctalia.togglePanel(panelId) end
    else
      leaveAt = noctalia.nowMs() + 400 -- grace period to move onto the card
    end
  end
  function card.close() if isOpen() then noctalia.togglePanel(panelId) end end
  function card.pending() return leaveAt ~= nil end
  function card.tick(now)
    if leaveAt and now >= leaveAt and not noctalia.state.get(keepKey) then leaveAt = nil; card.close() end
  end
  return card
end
local seek = hoverCard("seo/media-seek:hover", "hover_open", "hover_keep")
local vol = hoverCard("seo/media-seek:volume-card", "vol_open", "vol_keep")

local function label(p) return if p.artist ~= "" then `{p.title} - {p.artist}` else p.title end
local function marquee(text)
  local n = utf8.len(text) or #text
  if n <= WINDOW then return text end
  local padded = text .. "   •   "
  local start = math.floor(offset) % utf8.len(padded)
  local doubled = padded .. padded
  return doubled:sub(utf8.offset(doubled, start + 1), utf8.offset(doubled, start + WINDOW + 1) - 1)
end

local function clickTitle()
  seek.close()
  noctalia.togglePanel("seo/media-seek:panel")
end
local function clickAdd() noctalia.togglePanel("seo/media-seek:playlists") end

local function render()
  local p = m and m.player
  if not p then
    barWidget.render(if HIDE then ui.spacer({ width = 0, height = 0 }) else ui.glyph({ name = "music-off", color = "on_surface/0.5" }))
    return
  end
  local id = tostring(p.trackid):match("^/com/spotify/track/(%w+)$")
  local added = id ~= nil and any ~= nil and any.track == id and any.value == true
  local v = p.volume or 1
  local vglyph = if v <= 0.001 then "volume-off" elseif v < 0.34 then "volume-3" elseif v < 0.67 then "volume-2" else "volume"

  local cover = if p.cover
    then ui.image({ path = p.cover, width = ART, height = ART, fit = "cover", radius = ART / 2, rotation = if SPIN then angle else 0 })
    else ui.glyph({ name = if p.status == "Playing" then "player-play" else "player-pause" })
  barWidget.render(ui.row({ gap = 10, align = "center" }, {
    ui.row({ key = "vol", align = "center", onHover = vol.hover }, { ui.glyph({ name = vglyph, size = ICON }) }),
    ui.row({ key = "add", align = "center", onClick = clickAdd }, {
      ui.glyph({ name = if added then "circle-check-filled" else "circle-plus", size = ADD_ICON, color = if added then GREEN else "on_surface" }) }),
    ui.row({ key = "title", gap = 6, align = "center", onClick = clickTitle, onHover = seek.hover }, {
      ui.label({ text = marquee(label(p)), fontSize = FONT, fontWeight = "medium", maxWidth = MAXW }), cover }),
  }))
end

noctalia.state.watch("media", function(x) m = x; render() end)
noctalia.state.watch("in_any", function(x) any = x; render() end)

function onMiddleClick()
  local p = m and m.player
  if p then noctalia.state.set("cmd", { kind = "ctl", bus = p.bus, arg = "PlayPause", n = noctalia.nowMs() }) end
end

-- `noctalia msg plugin seo/media-seek:player <output> <click-title|click-add|hover-title|hover-vol> [true|false]`
-- drives the same handlers as the pointer (used for testing)
function onIpc(event, payload)
  if event == "click-title" then clickTitle()
  elseif event == "click-add" then clickAdd()
  elseif event == "hover-title" then seek.hover(payload)
  elseif event == "hover-vol" then vol.hover(payload) end
end

function update()
  local now = noctalia.nowMs()
  local dt = (now - lastTick) / 1000
  lastTick = now
  local p = m and m.player
  if p and p.status == "Playing" then offset += dt * 6; angle = (angle + dt * 20) % 360 end
  seek.tick(now); vol.tick(now)
  noctalia.setUpdateInterval(if (p and p.status == "Playing") or seek.pending() or vol.pending() then 100 else 1000)
  render()
end
render()
