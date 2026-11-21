--!nonstrict
-- Round bar button: speaker glyph for the active player's volume. Hover opens a vertical slider card.
local function num(key, default) return tonumber(noctalia.getSetting(key)) or default end
local THICK = num("bar.default.thickness", 40) * num("bar.default.capsule_thickness", 0.8)
local SIZE = math.max(12, math.floor(THICK - 2 * num("bar.default.capsule_padding", 8)))

local m, leaveAt = noctalia.state.get("media"), nil
local function isOpen() return noctalia.state.get("vol_open") == true end -- real state, published by the panel

local function render()
  local v = m and m.player and m.player.volume or 1
  local glyph = if v <= 0.001 then "volume-off" elseif v < 0.34 then "volume-3" elseif v < 0.67 then "volume-2" else "volume"
  barWidget.render(ui.row({ width = SIZE, height = SIZE, align = "center", justify = "center" }, {
    ui.glyph({ name = glyph, size = SIZE }),
  }))
  barWidget.setTooltip(`Głośność {math.floor(v * 100 + 0.5)}%`)
end

noctalia.state.watch("media", function(x) m = x; render() end)

function onHover(state)
  if state == "true" then
    leaveAt = nil
    if not isOpen() then noctalia.togglePanel("seo/media-seek:volume-card") end
  else
    leaveAt = noctalia.nowMs() + 400 -- grace period to move the cursor onto the card
  end
end
function onClick() if not isOpen() then noctalia.togglePanel("seo/media-seek:volume-card") end end

function update()
  if leaveAt and noctalia.nowMs() >= leaveAt and not noctalia.state.get("vol_keep") then
    leaveAt = nil
    if isOpen() then noctalia.togglePanel("seo/media-seek:volume-card") end
  end
  noctalia.setUpdateInterval(if leaveAt then 100 else 1000)
  render()
end
render()
