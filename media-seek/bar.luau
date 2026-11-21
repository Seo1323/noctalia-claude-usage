--!nonstrict
-- Drop-in for the built-in media widget: marquee "title - artist", round cover that spins while
-- playing. Hover opens the seek card under the bar, click opens the full Media panel.
local m = noctalia.state.get("media")
local ART = tonumber(noctalia.getConfig("art_size")) or 18
local MAXW = tonumber(noctalia.getConfig("max_length")) or 260
local SPIN = noctalia.getConfig("rotate_cover") ~= false
local HIDE = noctalia.getConfig("hide_when_idle") ~= false
local FONT = 13
local CHAR = FONT * 0.55 -- rough glyph width; shortcut: no text measuring API, upgrade if one appears
local WINDOW = math.max(8, math.floor(MAXW / CHAR))

local offset, angle, leaveAt = 0, 0, nil
local function hoverOpen() return noctalia.state.get("hover_open") == true end -- real state, set by hover.luau
local lastTick = noctalia.nowMs()

local function label(p) return if p.artist ~= "" then `{p.title} - {p.artist}` else p.title end

-- Scrolls a window of WINDOW characters over `text` (+ gap), looping; short text stays still.
local function marquee(text)
  local n = utf8.len(text) or #text
  if n <= WINDOW then return text end
  local padded = text .. "   •   "
  local len = utf8.len(padded)
  local start = math.floor(offset) % len
  local doubled = padded .. padded
  local a = utf8.offset(doubled, start + 1)
  local b = utf8.offset(doubled, start + WINDOW + 1)
  return doubled:sub(a, b - 1)
end

local function render()
  local p = m and m.player
  if not p or (HIDE and p.status ~= "Playing" and p.status ~= "Paused") then
    barWidget.render(if HIDE then ui.spacer({ width = 0, height = 0 }) else ui.glyph({ name = "music-off", color = "on_surface/0.5" }))
    return
  end
  local parts = { ui.label({ text = marquee(label(p)), fontSize = FONT, fontWeight = "medium", maxWidth = MAXW }) }
  if p.cover then
    parts[#parts + 1] = ui.image({ path = p.cover, width = ART, height = ART, fit = "cover", radius = ART / 2,
      rotation = if SPIN then angle else 0 })
  else
    parts[#parts + 1] = ui.glyph({ name = if p.status == "Playing" then "player-play" else "player-pause" })
  end
  barWidget.render(ui.row({ gap = 6, align = "center" }, parts))
  barWidget.setTooltip(nil)
end

noctalia.state.watch("media", function(v) m = v; render() end)

function onHover(state)
  if state == "true" then
    leaveAt = nil
    if not hoverOpen() then noctalia.togglePanel("seo/media-seek:hover") end
  else
    leaveAt = noctalia.nowMs() + 400 -- grace period to move the cursor onto the card
  end
end

function onClick()
  if hoverOpen() then noctalia.togglePanel("seo/media-seek:hover") end
  noctalia.togglePanel("seo/media-seek:panel")
end

function onMiddleClick()
  local p = m and m.player
  if p then noctalia.state.set("cmd", { kind = "ctl", bus = p.bus, arg = "PlayPause", n = noctalia.nowMs() }) end
end

-- 100 ms frame: marquee + spin. Idle when there is nothing to animate.
function update()
  local now = noctalia.nowMs()
  local dt = (now - lastTick) / 1000
  lastTick = now
  local p = m and m.player
  if p and p.status == "Playing" then
    offset += dt * 6 -- characters per second
    angle = (angle + dt * 20) % 360
  end
  if leaveAt and now >= leaveAt and not noctalia.state.get("hover_keep") then
    leaveAt = nil
    if hoverOpen() then noctalia.togglePanel("seo/media-seek:hover") end
  end
  noctalia.setUpdateInterval(if (p and p.status == "Playing") or leaveAt then 100 else 1000)
  render()
end
render()
