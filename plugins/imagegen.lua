-- imagegen.lua -- image generation for Archimedes.
--
-- Adds an `image.generate` agent tool and a `.image` command that turn a
-- text prompt into a picture through an OpenAI-compatible image API. The
-- generated image is posted into the channel as an embed.
--
-- An admin configures the plugin once per server with `.image setup <key>`.
-- The API key lives in the plugin key/value store, never in a prompt.
--
-- Operator note: image APIs are slower than the default plugin HTTP timeout.
-- Set PLUGIN_HTTP_TIMEOUT_S to 60 or more for reliable generation.

local M = {}

M.manifest = {
  id = "imagegen",
  name = "Image Generation",
  version = "1.0.0",
  description = "Generate images from a text prompt via an OpenAI-compatible API.",
  author = "HiLleywyn",
  category = "Creative",
}

local DEFAULT_ENDPOINT = "https://api.openai.com/v1"
local DEFAULT_MODEL = "dall-e-3"
local SIZES = { ["1024x1024"] = true, ["1792x1024"] = true, ["1024x1792"] = true }

local function trim(s)
  return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

-- ── per-server configuration ─────────────────────────────────────────────────
-- Config is namespaced by guild id, so each server sets its own API key.
local function ckey(guild_id, name)
  return "cfg:" .. (guild_id or "0") .. ":" .. name
end

local function get_cfg(guild_id, name, default)
  local value = arch.kv.get(ckey(guild_id, name))
  if value == nil or value == "" then return default end
  return value
end

local function set_cfg(guild_id, name, value)
  arch.kv.set(ckey(guild_id, name), value)
end

local function is_owner(ctx)
  local guild = arch.discord.guild(ctx.guild_id)
  return guild ~= nil and guild.owner_id == ctx.author_id
end

-- ── the image API call ───────────────────────────────────────────────────────
-- Returns (result_table, nil) on success, or (nil, error_string) on failure.
local function generate(guild_id, prompt, size)
  prompt = trim(prompt)
  if prompt == "" then
    return nil, "a prompt is required"
  end
  local key = get_cfg(guild_id, "api_key")
  if not key then
    return nil, "image generation is not set up on this server. An admin "
      .. "must run `.image setup <api-key>` first."
  end
  local endpoint = get_cfg(guild_id, "endpoint", DEFAULT_ENDPOINT)
  local model = get_cfg(guild_id, "model", DEFAULT_MODEL)
  if not (size and SIZES[size]) then size = "1024x1024" end

  local res = arch.http.post(endpoint .. "/images/generations", {
    headers = { Authorization = "Bearer " .. key },
    json = { model = model, prompt = prompt:sub(1, 4000), size = size, n = 1 },
    timeout = 90,
  })
  if not res then
    return nil, "the image request could not be sent"
  end
  if not res.ok then
    local msg = res.error
    if res.json and res.json.error then
      msg = res.json.error.message or res.json.error
    end
    if msg and tostring(msg):find("timed out", 1, true) then
      return nil, "the image request timed out. An admin may need to raise "
        .. "PLUGIN_HTTP_TIMEOUT_S (image APIs are slow)."
    end
    return nil, "image API error: " .. tostring(msg or ("http " .. res.status))
  end
  local data = res.json and res.json.data
  local first = data and data[1]
  if not first or not first.url then
    return nil, "the image API returned no image"
  end
  return {
    url = first.url,
    revised_prompt = first.revised_prompt,
    model = model,
    size = size,
    prompt = prompt,
  }, nil
end

-- A card showing a finished image, used by both the command and the tool.
local function image_card(result)
  return {
    title = "Generated image",
    description = arch.clip(result.revised_prompt or result.prompt, 400),
    image = result.url,
    color = arch.colors.purple,
    footer = result.model .. "  -  " .. result.size,
  }
end

-- ── agent tool ───────────────────────────────────────────────────────────────
M.tools = {
  {
    name = "image.generate",
    description = "Generate an image from a text description and post it "
      .. "into the channel. Use when a user asks you to draw, paint, create, "
      .. "make or generate a picture or image.",
    parameters = {
      type = "object",
      properties = {
        prompt = {
          type = "string",
          description = "A detailed description of the image to generate.",
        },
        size = {
          type = "string",
          enum = { "1024x1024", "1792x1024", "1024x1792" },
          description = "Image dimensions. Default 1024x1024.",
        },
      },
      required = { "prompt" },
    },
    handler = function(args, ctx)
      local result, err = generate(ctx.guild_id, args.prompt, args.size)
      if err then return { error = err } end
      ctx.reply(image_card(result))
      return {
        ok = true,
        image_url = result.url,
        model = result.model,
        size = result.size,
        revised_prompt = result.revised_prompt,
        note = "The image has been posted into the channel as an embed.",
      }
    end,
  },
}

-- ── owner-only config subcommand bodies ──────────────────────────────────────
local function need_owner(ctx)
  if is_owner(ctx) then return true end
  ctx.error("Only the server owner can configure image generation.")
  return false
end

local function cmd_setup(ctx)
  if not need_owner(ctx) then return end
  local key = (ctx.args or ""):gsub("%s", "")
  if key == "" then
    ctx.error("Usage: `" .. ctx.prefix .. "image setup <api-key>`")
    return
  end
  set_cfg(ctx.guild_id, "api_key", key)
  ctx.ok("Image generation is configured. Endpoint `"
    .. get_cfg(ctx.guild_id, "endpoint", DEFAULT_ENDPOINT) .. "`, model `"
    .. get_cfg(ctx.guild_id, "model", DEFAULT_MODEL) .. "`.")
end

local function cmd_model(ctx)
  if not need_owner(ctx) then return end
  local model = trim(ctx.args)
  if model == "" then
    ctx.error("Usage: `" .. ctx.prefix .. "image model <name>`")
    return
  end
  set_cfg(ctx.guild_id, "model", model)
  ctx.ok("Image model set to `" .. model .. "`.")
end

local function cmd_endpoint(ctx)
  if not need_owner(ctx) then return end
  local url = (ctx.args or ""):gsub("%s", "")
  if not url:match("^https?://") then
    ctx.error("Give a full http(s) URL.")
    return
  end
  set_cfg(ctx.guild_id, "endpoint", (url:gsub("/+$", "")))
  ctx.ok("Image API endpoint set.")
end

local function cmd_status(ctx)
  local configured = get_cfg(ctx.guild_id, "api_key") ~= nil
  ctx.reply({
    title = "Image generation",
    color = configured and arch.colors.success or arch.colors.neutral,
    description = configured and "Ready. Generate with `" .. ctx.prefix
      .. "image <prompt>`."
      or ("Not set up. The server owner runs `" .. ctx.prefix
          .. "image setup <api-key>`."),
    fields = {
      { name = "Endpoint",
        value = get_cfg(ctx.guild_id, "endpoint", DEFAULT_ENDPOINT),
        inline = true },
      { name = "Model",
        value = get_cfg(ctx.guild_id, "model", DEFAULT_MODEL),
        inline = true },
    },
  })
end

-- ── command tree ─────────────────────────────────────────────────────────────
M.commands = {
  {
    name = "image", aliases = { "img", "imagine" },
    summary = "Generate an image from a prompt.",
    usage = "image <prompt>",
    guild_only = true,
    run = function(ctx)
      local prompt = trim(ctx.args)
      if prompt == "" then
        ctx.error("Give a prompt, e.g. `" .. ctx.prefix
          .. "image a red fox asleep in snow`.")
        return
      end
      local result, err = generate(ctx.guild_id, prompt, nil)
      if err then ctx.error(err) return end
      ctx.reply(image_card(result))
    end,
    subcommands = {
      { name = "setup", usage = "setup <api-key>",
        summary = "Set the image API key (server owner only).",
        run = cmd_setup },
      { name = "model", usage = "model <name>",
        summary = "Set the image model (server owner only).",
        run = cmd_model },
      { name = "endpoint", usage = "endpoint <url>",
        summary = "Set an OpenAI-compatible base URL (server owner only).",
        run = cmd_endpoint },
      { name = "status", usage = "status",
        summary = "Show the image generation configuration.",
        run = cmd_status },
    },
  },
}

return M
