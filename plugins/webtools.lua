-- webtools.lua -- general web utility tools for Archimedes.
--
-- Three agent tools for reaching the open web through the guarded plugin
-- HTTP client:
--
--   web.fetch     -- fetch a page or API URL and return its text
--   web.wikipedia -- look up a topic on Wikipedia
--   web.weather   -- current weather for a place, via the free Open-Meteo API
--
-- The Wikipedia and weather APIs need no key, so this plugin works the
-- moment it is installed. The `.wiki` and `.weather` commands expose the
-- same lookups to people directly.

local M = {}

M.manifest = {
  id = "webtools",
  name = "Web Tools",
  version = "1.0.0",
  description = "Fetch web pages, look up Wikipedia, and check the weather.",
  author = "HiLleywyn",
  category = "Utility",
}

local function trim(s)
  return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

-- Percent-encode one URL component.
local function urlencode(s)
  return (tostring(s or ""):gsub("[^%w%-%._~]", function(c)
    return string.format("%%%02X", string.byte(c))
  end))
end

-- Strip HTML down to readable plain text.
local function to_text(html)
  local t = html or ""
  t = t:gsub("<script.->.-</script>", " ")
  t = t:gsub("<style.->.-</style>", " ")
  t = t:gsub("<!%-%-.-%-%->", " ")
  t = t:gsub("<[^>]*>", " ")
  t = t:gsub("&nbsp;", " "):gsub("&#39;", "'"):gsub("&quot;", '"')
  t = t:gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&amp;", "&")
  t = t:gsub("%s+", " ")
  return trim(t)
end

-- WMO weather codes used by the Open-Meteo forecast API.
local WEATHER_CODES = {
  [0] = "clear sky", [1] = "mainly clear", [2] = "partly cloudy",
  [3] = "overcast", [45] = "fog", [48] = "rime fog",
  [51] = "light drizzle", [53] = "drizzle", [55] = "dense drizzle",
  [56] = "freezing drizzle", [57] = "dense freezing drizzle",
  [61] = "light rain", [63] = "rain", [65] = "heavy rain",
  [66] = "freezing rain", [67] = "heavy freezing rain",
  [71] = "light snow", [73] = "snow", [75] = "heavy snow",
  [77] = "snow grains", [80] = "light rain showers",
  [81] = "rain showers", [82] = "violent rain showers",
  [85] = "light snow showers", [86] = "heavy snow showers",
  [95] = "thunderstorm", [96] = "thunderstorm with hail",
  [99] = "thunderstorm with heavy hail",
}

-- ── lookups: each returns (result_table, nil) or (nil, error_string) ─────────
local function fetch_url(url)
  url = trim(url)
  if not url:match("^https?://") then
    return nil, "url must start with http:// or https://"
  end
  local res = arch.http.get(url, { timeout = 15 })
  if not res then return nil, "the request could not be sent" end
  if not res.ok then
    return nil, "fetch failed: "
      .. tostring(res.error or ("http " .. res.status))
  end
  local ctype = (res.headers and res.headers["content-type"]) or ""
  local body = res.body or ""
  local content
  if ctype:find("json", 1, true) or ctype:find("text/plain", 1, true) then
    content = trim(body)
  else
    content = to_text(body)
  end
  local clipped = arch.clip(content, 4000)
  return {
    url = url, status = res.status, content_type = ctype,
    content = clipped, truncated = #content > #clipped,
  }, nil
end

local function wiki_lookup(query)
  query = trim(query)
  if query == "" then return nil, "a query is required" end
  local url = "https://en.wikipedia.org/w/api.php?format=json&action=query"
    .. "&generator=search&gsrlimit=1&prop=extracts|info&inprop=url"
    .. "&exintro=1&explaintext=1&redirects=1&gsrsearch=" .. urlencode(query)
  local res = arch.http.get(url, {
    headers = { ["User-Agent"] = "Archimedes-Plugin" }, timeout = 15,
  })
  if not res or not res.ok or not res.json then
    return nil, "the Wikipedia lookup failed"
  end
  local pages = res.json.query and res.json.query.pages
  if not pages then return nil, "no Wikipedia article found for that" end
  local page
  for _, p in pairs(pages) do page = p break end
  if not page or not page.extract or page.extract == "" then
    return nil, "no Wikipedia article found for that"
  end
  return {
    title = page.title,
    summary = arch.clip(page.extract, 2500),
    url = page.fullurl
      or ("https://en.wikipedia.org/wiki/" .. urlencode(page.title)),
  }, nil
end

local function weather_for(location)
  location = trim(location)
  if location == "" then return nil, "a location is required" end
  local geo = arch.http.get(
    "https://geocoding-api.open-meteo.com/v1/search?count=1&name="
    .. urlencode(location), { timeout = 15 })
  if not geo or not geo.ok or not geo.json then
    return nil, "could not look up that location"
  end
  local hit = geo.json.results and geo.json.results[1]
  if not hit then
    return nil, "no place found named '" .. location .. "'"
  end
  local fc = arch.http.get(
    "https://api.open-meteo.com/v1/forecast?current=temperature_2m,"
    .. "relative_humidity_2m,weather_code,wind_speed_10m&latitude="
    .. tostring(hit.latitude) .. "&longitude=" .. tostring(hit.longitude),
    { timeout = 15 })
  if not fc or not fc.ok or not fc.json or not fc.json.current then
    return nil, "could not fetch the forecast"
  end
  local cur = fc.json.current
  local place = hit.name
  if hit.admin1 then place = place .. ", " .. hit.admin1 end
  if hit.country then place = place .. ", " .. hit.country end
  return {
    location = place,
    temperature_c = cur.temperature_2m,
    humidity_percent = cur.relative_humidity_2m,
    wind_kph = cur.wind_speed_10m,
    conditions = WEATHER_CODES[cur.weather_code]
      or ("weather code " .. tostring(cur.weather_code)),
  }, nil
end

-- ── agent tools ──────────────────────────────────────────────────────────────
M.tools = {
  {
    name = "web.fetch",
    description = "Fetch a web page or API URL and return its text content. "
      .. "Use to read a specific page a user links or names. Not for general "
      .. "search -- use the web search tool for that.",
    parameters = {
      type = "object",
      properties = {
        url = { type = "string", description = "The http(s) URL to fetch." },
      },
      required = { "url" },
    },
    handler = function(args)
      local result, err = fetch_url(args.url)
      if err then return { error = err } end
      return result
    end,
  },
  {
    name = "web.wikipedia",
    description = "Look up a topic on Wikipedia and return the article "
      .. "summary. Use for encyclopaedic facts about people, places and things.",
    parameters = {
      type = "object",
      properties = {
        query = {
          type = "string",
          description = "The topic or article title to look up.",
        },
      },
      required = { "query" },
    },
    handler = function(args)
      local result, err = wiki_lookup(args.query)
      if err then return { error = err } end
      return result
    end,
  },
  {
    name = "web.weather",
    description = "Get the current weather for a place by name: temperature, "
      .. "conditions, humidity and wind.",
    parameters = {
      type = "object",
      properties = {
        location = {
          type = "string",
          description = "A city or place name, e.g. Lisbon or Tokyo.",
        },
      },
      required = { "location" },
    },
    handler = function(args)
      local result, err = weather_for(args.location)
      if err then return { error = err } end
      return result
    end,
  },
}

-- ── commands ─────────────────────────────────────────────────────────────────
M.commands = {
  {
    name = "wiki", aliases = { "wikipedia" },
    summary = "Look up a topic on Wikipedia.",
    usage = "wiki <topic>",
    run = function(ctx)
      local result, err = wiki_lookup(ctx.args)
      if err then ctx.error(err) return end
      ctx.reply({
        title = result.title, url = result.url, color = arch.colors.info,
        description = arch.clip(result.summary, 1500),
        footer = "Wikipedia",
      })
    end,
  },
  {
    name = "weather",
    summary = "Show the current weather for a place.",
    usage = "weather <place>",
    run = function(ctx)
      local result, err = weather_for(ctx.args)
      if err then ctx.error(err) return end
      ctx.reply({
        title = "Weather -- " .. result.location, color = arch.colors.teal,
        description = result.conditions,
        fields = {
          { name = "Temperature",
            value = tostring(result.temperature_c) .. " C", inline = true },
          { name = "Humidity",
            value = tostring(result.humidity_percent) .. " %", inline = true },
          { name = "Wind",
            value = tostring(result.wind_kph) .. " km/h", inline = true },
        },
      })
    end,
  },
}

return M
