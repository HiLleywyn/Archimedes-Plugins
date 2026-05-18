-- dice.lua -- roll dice from a command or as an agent tool.
--
-- A marketplace plugin: install it with `.ai plugins install dice`.

local M = {}

M.manifest = {
  id = "dice",
  name = "Dice",
  version = "1.0.0",
  description = "Roll dice with standard NdM notation.",
  author = "HiLleywyn",
  category = "Fun",
}

math.randomseed(os.time())

local function roll(spec)
  spec = (spec or ""):gsub("%s", ""):lower()
  if spec == "" then spec = "1d6" end
  local count, sides = spec:match("^(%d*)d(%d+)$")
  if not sides then return nil end
  count = tonumber(count) or 1
  sides = tonumber(sides)
  if count < 1 or count > 100 or sides < 2 or sides > 1000 then
    return nil
  end
  local rolls, total = {}, 0
  for _ = 1, count do
    local r = math.random(sides)
    rolls[#rolls + 1] = r
    total = total + r
  end
  return rolls, total
end

M.commands = {
  {
    name = "roll", aliases = { "dice" },
    summary = "Roll dice, e.g. .roll 2d6.",
    run = function(ctx)
      local rolls, total = roll(ctx.args)
      if not rolls then
        ctx.error("Use dice notation like `2d6` or `d20` "
          .. "(1-100 dice, 2-1000 sides).")
        return
      end
      ctx.reply({
        title = "Dice roll", color = arch.colors.gold,
        description = "Rolled **" .. total .. "**  ("
          .. table.concat(rolls, ", ") .. ")",
      })
    end,
  },
}

M.tools = {
  {
    name = "fun.roll_dice",
    description = "Roll dice in NdM notation (for example 2d6). Use when a "
      .. "user asks to roll dice or for a random number in a range.",
    parameters = {
      type = "object",
      properties = {
        notation = { type = "string",
                     description = "Dice notation, e.g. 2d6 or d20." },
      },
    },
    handler = function(args)
      local rolls, total = roll(args.notation or "1d6")
      if not rolls then return { error = "invalid dice notation" } end
      return { total = total, rolls = rolls }
    end,
  },
}

return M
