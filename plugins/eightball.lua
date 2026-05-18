-- eightball.lua -- a magic 8-ball, as a command and an agent tool.
--
-- A marketplace plugin: install it with `.ai plugins install eightball`.

local M = {}

M.manifest = {
  id = "eightball",
  name = "Magic 8-Ball",
  version = "1.0.0",
  description = "Ask the magic 8-ball a yes/no question.",
  author = "HiLleywyn",
  category = "Fun",
}

math.randomseed(os.time())

local ANSWERS = {
  "It is certain.", "Without a doubt.", "Yes, definitely.",
  "You may rely on it.", "Most likely.", "Outlook good.",
  "Signs point to yes.", "Reply hazy, try again.", "Ask again later.",
  "Cannot predict now.", "Do not count on it.", "My reply is no.",
  "Outlook not so good.", "Very doubtful.",
}

local function shake()
  return ANSWERS[math.random(#ANSWERS)]
end

M.commands = {
  {
    name = "8ball", aliases = { "eightball" },
    summary = "Ask the magic 8-ball a question.",
    run = function(ctx)
      if ctx.args == "" then
        ctx.error("Ask the 8-ball a question.")
        return
      end
      ctx.reply({
        title = "Magic 8-Ball", color = arch.colors.purple,
        description = "> " .. arch.clip(ctx.args, 240)
          .. "\n\n**" .. shake() .. "**",
      })
    end,
  },
}

M.tools = {
  {
    name = "fun.magic_eightball",
    description = "Consult a magic 8-ball for a playful yes/no answer to a "
      .. "user's question.",
    parameters = { type = "object", properties = {} },
    handler = function(args)
      return { answer = shake() }
    end,
  },
}

return M
