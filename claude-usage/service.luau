--!nonstrict
-- Headless poller: runs fetch.sh and publishes the result to shared state.
-- The bar widget(s) only subscribe, so N monitors still cost one request.

local function intervalMs()
  local minutes = tonumber(noctalia.getConfig("refresh_minutes")) or 5
  minutes = math.max(1, math.min(120, minutes))
  return math.floor(minutes * 60 * 1000)
end

local last = nil -- last successful reading, kept while errors occur
local busy = false

local function publish(err)
  noctalia.state.set("usage", { data = last, error = err, fetched = os.time() })
end

local function poll()
  if busy then return end
  busy = true
  noctalia.runAsync("'" .. noctalia.pluginDir() .. "/fetch.sh'", function(result)
    busy = false
    local ok, data = pcall(noctalia.json.decode, result.stdout or "")
    if not ok or type(data) ~= "table" then
      publish("bad_response")
    elseif data.error ~= nil then
      publish(tostring(data.error))
    else
      last = data
      publish(nil)
    end
  end)
end

function update()
  noctalia.setUpdateInterval(intervalMs())
  poll()
end

function onIpc(event)
  if event == "refresh" then poll() end
end

poll()
