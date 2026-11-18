--!nonstrict
-- Icon-only bar widget: a logo or a usage ring; the tooltip shows both windows.
-- Click launches Claude Code (default: alacritty -e claude).

local S = require("./shared.luau")

local mode = S.conf("logo", "glyph") -- glyph | star | custom | ring
local glyph = S.text("glyph", "brain")
local logoPath = S.text("logo_path", "")
local size = tonumber(S.conf("size", 20)) or 20
local snapshot = noctalia.state.get("usage")

local function render()
  local node
  if mode == "ring" then
    local pct = S.windows(snapshot and snapshot.data, false).five.pct
    node = S.ring(1 - (pct or 0) / 100, S.colorFor(pct, S.DEFAULT_COLORS), size)
  else
    node = S.logo(mode, size, nil, glyph, logoPath)
  end
  barWidget.render(node or ui.glyph({ name = "brain", size = size }))
  barWidget.setTooltip(S.tooltip(snapshot))
end

noctalia.state.watch("usage", function(value)
  snapshot = value
  render()
end)

function update()
  noctalia.setUpdateInterval(60000)
  render()
end

function onClick()
  local command = S.text("command", "")
  if command == "" then command = "alacritty -e claude" end
  noctalia.runAsync(`PATH="$HOME/.local/bin:$PATH" setsid -f {command} >/dev/null 2>&1`, function() end)
end

render()
