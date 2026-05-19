-- videogen.lua -- video generation for Archimedes.
--
-- Adds `video.generate` and `video.status` agent tools and a `.video`
-- command. Video generation is slow and asynchronous: a request is submitted
-- to a Replicate-hosted model, a background loop polls the job, and the
-- finished video is posted into the channel automatically when it is ready.
--
-- An admin configures the plugin once per server:
--   .video setup <replicate-api-token> <owner/model-name>
--
-- The token lives in the plugin key/value store, never in a prompt.

local M = {}

M.manifest = {
  id = "videogen",
  name = "Video Generation",
  version = "1.0.0",
  description = "Generate videos from a text prompt via Replicate-hosted models.",
  author = "HiLleywyn",
  category = "Creative",
}

local API = "https://api.replicate.com/v1"
local JOB_TTL = 1800  -- give up polling a job stuck for over 30 minutes

local function trim(s)
  return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

-- ── per-server configuration ─────────────────────────────────────────────────
local function ckey(guild_id, name)
  return "cfg:" .. (guild_id or "0") .. ":" .. name
end

local function get_cfg(guild_id, name)
  local value = arch.kv.get(ckey(guild_id, name))
  if value == nil or value == "" then return nil end
  return value
end

local function set_cfg(guild_id, name, value)
  arch.kv.set(ckey(guild_id, name), value)
end

local function is_owner(ctx)
  local guild = arch.discord.guild(ctx.guild_id)
  return guild ~= nil and guild.owner_id == ctx.author_id
end

-- ── submitting a job ─────────────────────────────────────────────────────────
-- Returns (job_table, nil) on success, or (nil, error_string) on failure.
local function submit(guild_id, channel_id, user_id, prompt)
  prompt = trim(prompt)
  if prompt == "" then
    return nil, "a prompt is required"
  end
  local token = get_cfg(guild_id, "token")
  local model = get_cfg(guild_id, "model")
  if not token or not model then
    return nil, "video generation is not set up on this server. An admin "
      .. "must run `.video setup <replicate-token> <owner/model>` first."
  end
  local res = arch.http.post(API .. "/models/" .. model .. "/predictions", {
    headers = { Authorization = "Bearer " .. token },
    json = { input = { prompt = prompt:sub(1, 2000) } },
    timeout = 45,
  })
  if not res then
    return nil, "the video request could not be sent"
  end
  if not res.ok then
    local msg = res.error
    if res.json then msg = res.json.detail or res.json.title or msg end
    return nil, "video API error: " .. tostring(msg or ("http " .. res.status))
  end
  local prediction_id = res.json and res.json.id
  local get_url = res.json and res.json.urls and res.json.urls.get
  if not prediction_id or not get_url then
    return nil, "the video API did not return a job"
  end
  local job_id = arch.store.put("jobs", {
    prediction_id = prediction_id, get_url = get_url, status = "pending",
    prompt = prompt, model = model, guild_id = guild_id,
    channel_id = channel_id, user_id = user_id, created_at = arch.now(),
  })
  return { id = job_id, prediction_id = prediction_id }, nil
end

-- Pull a video URL out of a Replicate prediction `output` field.
local function output_url(output)
  if type(output) == "table" then return output[1] end
  if type(output) == "string" then return output end
  return nil
end

-- ── polling a job ────────────────────────────────────────────────────────────
-- Polls one pending job once. On a terminal state it posts the result into
-- the job's channel and marks the job done. Returns the current status.
local function poll_job(job)
  local token = get_cfg(job.guild_id, "token")
  if not token then return job.status end

  if arch.now() - (job.created_at or arch.now()) > JOB_TTL then
    job.status = "done"
    arch.store.update("jobs", job.id, job)
    arch.discord.send(job.channel_id, {
      title = "Video generation timed out",
      description = "The video for **" .. arch.clip(job.prompt, 200)
        .. "** did not finish in time.",
      color = arch.colors.error, footer = "video #" .. job.id,
    })
    return "done"
  end

  local res = arch.http.get(job.get_url, {
    headers = { Authorization = "Bearer " .. token }, timeout = 30,
  })
  if not res or not res.ok or not res.json then
    return job.status  -- a transient failure; the loop retries next cycle
  end
  local status = res.json.status or "unknown"

  if status == "succeeded" then
    local url = output_url(res.json.output)
    job.status = "done"
    job.video_url = url
    arch.store.update("jobs", job.id, job)
    if url then
      arch.discord.send(job.channel_id, {
        title = "Video ready",
        description = "Your video for **" .. arch.clip(job.prompt, 200)
          .. "** is ready:\n" .. url,
        url = url, color = arch.colors.purple, footer = "video #" .. job.id,
      })
    end
    return "done"
  elseif status == "failed" or status == "canceled" then
    job.status = "done"
    arch.store.update("jobs", job.id, job)
    arch.discord.send(job.channel_id, {
      title = "Video generation failed",
      description = "The video for **" .. arch.clip(job.prompt, 200)
        .. "** could not be generated (" .. status .. ").",
      color = arch.colors.error, footer = "video #" .. job.id,
    })
    return "done"
  end
  return status  -- still starting or processing
end

-- ── agent tools ──────────────────────────────────────────────────────────────
M.tools = {
  {
    name = "video.generate",
    description = "Start generating a video from a text description. Video "
      .. "generation is slow, so this returns immediately with a job id and "
      .. "the finished video is posted into the channel automatically when "
      .. "ready. Use when a user asks you to make or generate a video.",
    parameters = {
      type = "object",
      properties = {
        prompt = {
          type = "string",
          description = "A detailed description of the video to generate.",
        },
      },
      required = { "prompt" },
    },
    handler = function(args, ctx)
      local job, err = submit(ctx.guild_id, ctx.channel_id, ctx.user_id,
        args.prompt)
      if err then return { error = err } end
      return {
        ok = true,
        job_id = job.id,
        status = "submitted",
        note = "Video generation has started. It usually takes one to a few "
          .. "minutes; the finished video is posted into this channel "
          .. "automatically. Tell the user it is on the way.",
      }
    end,
  },
  {
    name = "video.status",
    description = "Check on a video generation job by its job id.",
    parameters = {
      type = "object",
      properties = {
        job_id = {
          type = "string",
          description = "The job id returned by video.generate.",
        },
      },
      required = { "job_id" },
    },
    handler = function(args, ctx)
      local job = arch.store.get("jobs", args.job_id)
      if not job then
        return { error = "no video job with id " .. tostring(args.job_id) }
      end
      local status = job.status
      if status == "pending" then status = poll_job(job) end
      return {
        ok = true, job_id = job.id, status = status,
        video_url = job.video_url, prompt = job.prompt,
      }
    end,
  },
}

-- ── delivery loop ────────────────────────────────────────────────────────────
local function poll_loop()
  for _, job in ipairs(arch.store.query("jobs", { status = "pending" })) do
    poll_job(job)
  end
end

M.loops = {
  { name = "video-poll", interval = 20, run = poll_loop },
}

-- ── owner-only config subcommand bodies ──────────────────────────────────────
local function need_owner(ctx)
  if is_owner(ctx) then return true end
  ctx.error("Only the server owner can configure video generation.")
  return false
end

local function cmd_setup(ctx)
  if not need_owner(ctx) then return end
  local token, model = (ctx.args or ""):match("^(%S+)%s+(%S+)")
  if not token then
    ctx.error("Usage: `" .. ctx.prefix
      .. "video setup <replicate-token> <owner/model>`")
    return
  end
  set_cfg(ctx.guild_id, "token", token)
  set_cfg(ctx.guild_id, "model", model)
  ctx.ok("Video generation is configured with model `" .. model .. "`.")
end

local function cmd_model(ctx)
  if not need_owner(ctx) then return end
  local model = trim(ctx.args)
  if not model:match("^[%w%.%-_]+/[%w%.%-_]+$") then
    ctx.error("Give a Replicate model as `owner/name`.")
    return
  end
  set_cfg(ctx.guild_id, "model", model)
  ctx.ok("Video model set to `" .. model .. "`.")
end

local function cmd_status(ctx)
  local id = trim(ctx.args)
  if id ~= "" then
    local job = arch.store.get("jobs", id)
    if not job then ctx.error("No video job `#" .. id .. "`.") return end
    local status = job.status
    if status == "pending" then status = poll_job(job) end
    ctx.reply({
      title = "Video job #" .. job.id, color = arch.colors.info,
      description = "**" .. arch.clip(job.prompt, 200) .. "**",
      fields = {
        { name = "Status", value = status, inline = true },
        { name = "Video", value = job.video_url or "pending", inline = true },
      },
    })
    return
  end
  local configured = get_cfg(ctx.guild_id, "token") ~= nil
    and get_cfg(ctx.guild_id, "model") ~= nil
  ctx.reply({
    title = "Video generation",
    color = configured and arch.colors.success or arch.colors.neutral,
    description = configured
      and ("Ready. Model `" .. get_cfg(ctx.guild_id, "model") .. "`.")
      or ("Not set up. The server owner runs `" .. ctx.prefix
          .. "video setup <replicate-token> <owner/model>`."),
  })
end

-- ── command tree ─────────────────────────────────────────────────────────────
M.commands = {
  {
    name = "video", aliases = { "vid" },
    summary = "Generate a video from a prompt.",
    usage = "video <prompt>",
    guild_only = true,
    run = function(ctx)
      local prompt = trim(ctx.args)
      if prompt == "" then
        ctx.error("Give a prompt, e.g. `" .. ctx.prefix
          .. "video a paper boat drifting down a stream`.")
        return
      end
      local job, err = submit(ctx.guild_id, ctx.channel_id, ctx.author_id,
        prompt)
      if err then ctx.error(err) return end
      ctx.reply({
        title = "Video generation started",
        description = "Working on **" .. arch.clip(prompt, 200) .. "**. I will "
          .. "post it here when it is ready, usually within a few minutes.",
        color = arch.colors.purple, footer = "video #" .. job.id,
      })
    end,
    subcommands = {
      { name = "setup", usage = "setup <replicate-token> <owner/model>",
        summary = "Set the Replicate token and video model (owner only).",
        run = cmd_setup },
      { name = "model", usage = "model <owner/name>",
        summary = "Set the video model (server owner only).",
        run = cmd_model },
      { name = "status", usage = "status [job-id]",
        summary = "Show the configuration, or check one job.",
        run = cmd_status },
    },
  },
}

return M
