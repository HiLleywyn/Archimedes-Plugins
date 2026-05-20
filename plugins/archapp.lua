-- archapp.lua -- a guide to the Archimedes 3.0 application surface.
--
-- Archimedes 3.0 lifted the agent out of the Discord cog and into an
-- application with a coherent product surface: Soul, Heartbeat, Scheduler,
-- MCP, Dynamic UI and a multi-provider Service Chain. This plugin gives
-- the model and the user a way to discover that surface without leaving
-- the channel.
--
-- It registers two things: an `arch.about` agent tool the model calls
-- when asked "what can you do" or "what is new in 3.0", and an `.arch3`
-- command that prints the same guide as a static reply.

local M = {}

M.manifest = {
  id = "archapp",
  name = "Archimedes 3.0 Guide",
  version = "1.0.0",
  description = "Surfaces the Archimedes 3.0 application layer to the "
    .. "model and the user: Soul, Heartbeat, Scheduler, MCP, Dynamic UI, "
    .. "Service Chain.",
  author = "HiLleywyn",
  category = "Utility",
}

local FEATURES = {
  {
    name = "Soul",
    summary = "The editable system-prompt persona. Switch presets at "
      .. "runtime (.app soul preset tutor) or write a custom soul "
      .. "(.app soul set <text>). Presets: default, short, tutor, "
      .. "creative, expert.",
  },
  {
    name = "Heartbeat",
    summary = "An autonomous self-check loop. Every N minutes during a "
      .. "configured active-hours window the assistant reviews its "
      .. "memories and pending tasks. Off by default.",
  },
  {
    name = "Scheduler",
    summary = "Durable scheduled tasks: oneshot reminders and standard "
      .. "five-field cron, both surviving restarts and firing back "
      .. "into the channel that scheduled them.",
  },
  {
    name = "MCP",
    summary = "Model Context Protocol server integration. Declare "
      .. "servers in ARCHIMEDES_MCP_SERVERS or add at runtime with "
      .. ".app mcp add <name> <url>. Their tools bridge into the agent.",
  },
  {
    name = "Dynamic UI",
    summary = "Cards, tiles, sections, buttons and follow-up suggestions "
      .. "rendered natively as Discord embeds plus interactive views.",
  },
  {
    name = "Service Chain",
    summary = "An ordered list of model providers with per-provider "
      .. "circuit breakers. When the primary errors, the chain falls "
      .. "through to the next entry.",
  },
}

local function build_summary()
  local lines = {}
  for _, f in ipairs(FEATURES) do
    table.insert(lines, "**" .. f.name .. "**: " .. f.summary)
  end
  return table.concat(lines, "\n\n")
end

-- The .arch3 command: a static reply listing every 3.0 feature.
M.commands = {
  {
    name = "arch3", aliases = { "appguide", "archguide" },
    summary = "Show what the Archimedes 3.0 application layer can do.",
    run = function(ctx)
      ctx.reply({
        title = "Archimedes 3.0",
        color = arch.colors.purple,
        description = "A personal-assistant application that lives in "
          .. "Discord. The agent core (arch/) is transport-agnostic; "
          .. "Discord is one channel into it.",
        fields = {
          { name = "Soul",         value = "Editable persona with named presets.", inline = true },
          { name = "Heartbeat",    value = "Optional autonomous self-check loop.", inline = true },
          { name = "Scheduler",    value = "Durable cron and oneshot tasks.",      inline = true },
          { name = "MCP",          value = "External tool servers, live wiring.",  inline = true },
          { name = "Dynamic UI",   value = "Structured cards plus interactive views.", inline = true },
          { name = "Service Chain", value = "Multi-provider fallback with circuit breakers.", inline = true },
        },
        footer = ".app soul / heartbeat / schedule / mcp / services",
      })
    end,
  },
}

-- An agent tool: the model calls this when asked what is new or what
-- the assistant can do beyond plain chat.
M.tools = {
  {
    name = "arch.about",
    description = "Return a short summary of the Archimedes 3.0 "
      .. "application surface (Soul, Heartbeat, Scheduler, MCP, Dynamic "
      .. "UI, Service Chain). Call when the user asks 'what can you do', "
      .. "'what is new', or 'how do I use the new features'.",
    parameters = { type = "object", properties = {} },
    handler = function(args)
      local features = {}
      for _, f in ipairs(FEATURES) do
        table.insert(features, { name = f.name, summary = f.summary })
      end
      return {
        version = "3.0",
        codename = "Pivot",
        summary = build_summary(),
        features = features,
        operator_surface = {
          ".app soul",
          ".app heartbeat",
          ".app schedule",
          ".app mcp",
          ".app services",
        },
      }
    end,
  },
}

return M
