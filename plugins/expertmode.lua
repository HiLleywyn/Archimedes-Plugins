-- expertmode.lua -- let the model steer its own turn into expert mode.
--
-- A marketplace plugin: install it with `.ai plugins install expertmode`.
--
-- The mode.expert tool returns a next_turn directive. When the model calls
-- it mid-turn, every following step of the same answer runs at a low
-- temperature with extra expert instructions injected. It is a worked
-- example of an agent tool that retunes its own turn through next_turn.

local M = {}

M.manifest = {
  id = "expertmode",
  name = "Expert Mode",
  version = "1.0.0",
  description = "Let the model switch itself into a precise, rigorous "
    .. "answering mode for the rest of a turn.",
  author = "HiLleywyn",
  category = "Utility",
}

M.tools = {
  {
    name = "mode.expert",
    description = "Switch into precise expert mode for the rest of this "
      .. "turn. Call this when the user asks for a rigorous, technical or "
      .. "carefully reasoned answer. It lowers the model temperature and "
      .. "adds expert instructions to every step that follows in this turn.",
    parameters = {
      type = "object",
      properties = {
        topic = {
          type = "string",
          description = "Optional subject to be precise about, for example "
            .. "'distributed systems'.",
        },
      },
    },
    handler = function(args)
      local focus = ""
      local topic = args.topic
      if type(topic) == "string" and topic ~= "" then
        focus = " Focus on " .. topic .. "."
      end
      return {
        mode = "expert",
        note = "Expert mode is on for the rest of this turn.",
        next_turn = {
          temperature = 0.1,
          instructions = "Expert mode: answer with rigorous, technically "
            .. "precise detail. State your assumptions, avoid hand-waving, "
            .. "and prefer exactness over brevity." .. focus,
        },
      }
    end,
  },
}

return M
