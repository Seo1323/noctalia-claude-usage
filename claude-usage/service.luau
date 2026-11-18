--!nonstrict
-- Headless poller: runs fetch.sh and publishes the result to shared state, so every
-- widget on every monitor shares one request. Widgets ask for a refresh via "refresh".

local busy = false
local last = nil -- last good reading, kept while errors occur

local function publish(err)
  noctalia.state.set("usage", { data = last, error = err, fetched = os.time() })
end

local function poll()
  if busy then return end
  busy = true
  noctalia.runAsync({ noctalia.pluginDir() .. "/fetch.sh" }, function(result)
    busy = false
    local ok, data = pcall(noctalia.json.decode, result.stdout or "")
    if not ok or type(data) ~= "table" then return publish("bad_response") end
    if data.error ~= nil then return publish(tostring(data.error)) end
    last = data
    publish(nil)
  end)
end

function update()
  local minutes = math.clamp(tonumber(noctalia.getConfig("refresh_minutes")) or 5, 1, 120)
  noctalia.setUpdateInterval(math.floor(minutes * 60000))
  poll()
end

function onIpc(event)
  if event == "refresh" then poll() end
end

noctalia.state.watch("refresh", function() poll() end)

poll()
