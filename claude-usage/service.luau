--!nonstrict
-- Headless poller: runs fetch.sh and publishes the result to shared state, so every
-- widget on every monitor shares one request. Widgets ask for a refresh via "refresh".
-- When costs are shown in another currency without a manual rate, it also fetches the
-- ECB reference rates (rates.sh) at most every 12 hours and publishes them as "rates".

local busy = false

-- The last good reading is kept on disk, so a restart or an API error (e.g. a rate limit)
-- shows stale numbers instead of an empty widget.
local DATA_DIR = noctalia.pluginDataDir()
local CACHE = DATA_DIR and DATA_DIR .. "/last.json"
local last = nil
if CACHE then
  local raw = noctalia.readFile(CACHE)
  local ok, data = pcall(noctalia.json.decode, raw or "")
  if raw and ok and type(data) == "table" then last = data end
end

local function publish(err)
  noctalia.state.set("usage", { data = last, error = err, fetched = os.time() })
end

local RATES_MAX_AGE = 12 * 3600
local ratesFetched, ratesBusy = 0, false

local function needsRates()
  local currency = tostring(noctalia.getConfig("currency") or "USD")
  local manual = tonumber(noctalia.getConfig("exchange_rate")) or 0
  return currency ~= "USD" and manual <= 0
end

local function pollRates()
  if ratesBusy or not needsRates() or os.time() - ratesFetched < RATES_MAX_AGE then return end
  ratesBusy = true
  noctalia.runAsync({ noctalia.pluginDir() .. "/rates.sh" }, function(result)
    ratesBusy = false
    local ok, rates = pcall(noctalia.json.decode, result.stdout or "")
    if ok and type(rates) == "table" and rates.error == nil and rates.USD then
      ratesFetched = os.time()
      noctalia.state.set("rates", rates)
    end
  end)
end

local function poll()
  pollRates()
  if busy then return end
  busy = true
  noctalia.runAsync({ noctalia.pluginDir() .. "/fetch.sh" }, function(result)
    busy = false
    local ok, data = pcall(noctalia.json.decode, result.stdout or "")
    if not ok or type(data) ~= "table" then return publish("bad_response") end
    if data.error ~= nil then return publish(tostring(data.error)) end
    last = data
    if CACHE then noctalia.writeFile(CACHE, result.stdout) end
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
