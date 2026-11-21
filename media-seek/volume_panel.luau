--!nonstrict
-- Vertical volume bar for the active MPRIS player (hover card next to the volume button).
-- The UI toolkit's slider is horizontal only, so this is a stack of SEGMENTS clickable boxes.
-- shortcut: 5% steps; dragging works only while the pointer stays captured by the first segment, click is the reliable path.
local SEGMENTS = 20
local m = noctalia.state.get("media")
local isOpen, pressed, lastSent = false, false, 0

local function send(v)
  local p = m and m.player
  if p then noctalia.state.set("cmd", { kind = "volume", bus = p.bus, arg = string.format("%.2f", math.clamp(v, 0, 1)), n = noctalia.nowMs() }) end
end

local function render()
  if not isOpen then return end
  local p = m and m.player
  if not p then return panel.render(ui.column({ padding = 12 }, { ui.label({ text = "Nic nie gra", color = "on_surface_variant" }) })) end
  local v = p.volume or 1
  local filled = math.floor(v * SEGMENTS + 0.5)
  local segs = {}
  for i = SEGMENTS, 1, -1 do -- top segment = 100%
    local level = i / SEGMENTS
    local function set()
      local now = noctalia.nowMs()
      if now - lastSent > 100 then lastSent = now; send(level) end
    end
    segs[#segs + 1] = ui.box({ width = 30, height = 7, radius = 3, fill = if i <= filled then "primary" else "surface_container_high",
      onClick = function() send(level) end,
      onPointerDown = function() pressed = true; send(level) end,
      onPointerMove = function() if pressed then set() end end,
      onPointerUp = function() pressed = false end })
  end
  panel.render(ui.column({ padding = 14, gap = 10, align = "center", fill = "surface_container", radius = 14, border = "outline_variant", borderWidth = 1,
    onPointerMove = function() noctalia.state.set("vol_keep", true) end,
    onPointerLeave = function() pressed = false; noctalia.state.set("vol_keep", false) end,
  }, {
    ui.label({ text = `{math.floor(v * 100 + 0.5)}%`, fontSize = 14, fontWeight = "medium" }),
    ui.column({ gap = 2 }, segs),
  }))
end

noctalia.state.watch("media", function(x) m = x; render() end)
function onOpen() isOpen = true; noctalia.state.set("vol_open", true); render() end
function onClose() isOpen = false; pressed = false; noctalia.state.set("vol_open", false); noctalia.state.set("vol_keep", false) end
