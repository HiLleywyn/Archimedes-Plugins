# Archimedes-Plugins

The plugin marketplace for [Archimedes](https://github.com/HiLleywyn/Archimedes).

A plugin is a single `.lua` file that can register prefix commands (with
nested subcommand groups), agent tools the model can call, and background
loops -- with no Python. This repository is the catalogue Archimedes reads
when an operator runs `.ai plugins search` and `.ai plugins install`.

## Layout

```
index.json              the marketplace catalogue (generated)
plugins/                one .lua file per plugin
scripts/build_index.py  regenerates index.json from plugins/
.github/workflows/      CI: compiles every plugin, checks the index
```

## Plugins

| Plugin | Category | What it does |
|---|---|---|
| `notes` | Productivity | Private and shared notes, with sharing and groups. |
| `tasks` | Productivity | Tasks and to-do lists, with reminders. |
| `events` | Productivity | Calendar events with reminders. |
| `groups` | Productivity | Shared groups for notes, tasks and events. |
| `coinflip` | Fun | Flip a coin -- the worked example. |
| `dice` | Fun | Roll dice with standard NdM notation. |
| `eightball` | Fun | Ask the magic 8-ball a question. |

The `notes`, `tasks`, `events`, `groups` and `coinflip` plugins also ship
bundled with Archimedes, so they are installed out of the box. `dice` and
`eightball` are install-only -- they show the marketplace working end to end.

## Installing a plugin

From a server where Archimedes runs, a moderator runs:

```
.ai plugins search          browse the catalogue
.ai plugins install dice    install a plugin
.ai plugins update dice     pull the latest version
```

Installed plugins persist across restarts: the plugin's Lua source is stored
in the bot's database.

## Authoring a plugin

Each plugin file `return`s one table:

```lua
local M = {}

M.manifest = {
  id          = "myplugin",     -- slug; must match the file name
  name        = "My Plugin",
  version     = "1.0.0",
  description = "What it does.",
  author      = "you",
  category    = "General",
  storage     = "myplugin",     -- optional shared document-store namespace
}

M.commands = { ... }            -- prefix commands
M.tools    = { ... }            -- agent tools
M.loops    = { ... }            -- background jobs

return M
```

The full plugin contract -- the `arch` global, the per-call `ctx` table, the
document store and card tables -- is documented in
[`plugins/README.md`](https://github.com/HiLleywyn/Archimedes/blob/main/plugins/README.md)
in the Archimedes repository. The `coinflip` and `dice` plugins here are
small, complete examples.

## Contributing a plugin

1. Add `plugins/<id>.lua`. The file name must equal `manifest.id`.
2. Run `python scripts/build_index.py` (needs `pip install lupa`).
3. Commit the plugin and the regenerated `index.json`.

CI compiles every plugin and fails if `index.json` is stale.
