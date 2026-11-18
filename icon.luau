--!nonstrict
-- Icon-only bar widget: Claude logo; the tooltip shows 5h / weekly usage.
-- Click launches Claude Code (default: alacritty -e claude).

local size = tonumber(noctalia.getConfig("size")) or 20
local snapshot = noctalia.state.get("usage")

-- Custom logo: the `logo_path` setting, or logo.svg inside the plugin folder.
local function logoFile()
  if noctalia.getConfig("logo") == "star" then return noctalia.pluginDir() .. "/assets/star.svg" end
  local p = noctalia.string.trim(tostring(noctalia.getConfig("logo_path") or ""))
  if p ~= "" then return (p:gsub("^~", os.getenv("HOME") or "~")) end
  return noctalia.pluginDir() .. "/logo.svg"
end

local function effective(pct, resetAt)
  if pct == nil then return nil end
  if resetAt ~= nil and tonumber(resetAt) <= os.time() then return 0 end
  return math.floor(tonumber(pct) + 0.5)
end

local function left(resetAt)
  if resetAt == nil then return "-" end
  local s = tonumber(resetAt) - os.time()
  if s <= 0 then return "now" end
  local d, h, m = s // 86400, (s % 86400) // 3600, (s % 3600) // 60
  if d > 0 then return `{d}d {h}h` end
  if h > 0 then return `{h}h {m}m` end
  return `{m}m`
end

local function fmtTokens(n)
  if n == nil then return "--" end
  n = tonumber(n)
  if n >= 1000000 then return string.format("%.1fM", n / 1000000) end
  if n >= 1000 then return string.format("%.0fk", n / 1000) end
  return tostring(n)
end

local function render()
  local logoMode = noctalia.getConfig("logo")
  if logoMode == "custom" or logoMode == "star" then
    barWidget.render(ui.image({
      path = logoFile(),
      width = size,
      height = size,
      fit = "contain",
    }))
  else
    barWidget.render(ui.glyph({ name = "brain", size = size, color = "on_surface" }))
  end
  local data = snapshot and snapshot.data
  local lines = { "Claude Code" }
  if data then
    lines[#lines + 1] = `5h: {effective(data.five_hour, data.five_reset) or "--"}%  (resets in {left(data.five_reset)})\n    tokens: {fmtTokens(effective(data.five_hour, data.five_reset) == 0 and 0 or data.five_tokens)}`
    lines[#lines + 1] = `7d: {effective(data.weekly, data.weekly_reset) or "--"}%  (resets in {left(data.weekly_reset)})\n    tokens: {fmtTokens(effective(data.weekly, data.weekly_reset) == 0 and 0 or data.weekly_tokens)}`
  end
  if snapshot and snapshot.error then lines[#lines + 1] = "Error: " .. tostring(snapshot.error) end
  if snapshot == nil then lines[#lines + 1] = "Loading..." end
  barWidget.setTooltip(table.concat(lines, "\n"))
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
  local command = noctalia.string.trim(tostring(noctalia.getConfig("command") or ""))
  if command == "" then command = "alacritty -e claude" end
  noctalia.runAsync("PATH=\"$HOME/.local/bin:$PATH\" setsid -f " .. command .. " >/dev/null 2>&1", function() end)
end

render()
