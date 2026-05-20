# Archimedes-Plugins

The plugin marketplace for [Archimedes](https://github.com/HiLleywyn/Archimedes).

A plugin is a single `.lua` file that can register prefix commands (with
nested subcommand groups), agent tools the model can call, background loops,
and event handlers that react to Discord activity -- with no Python. This
repository is the catalogue Archimedes reads when an operator runs
`.ai plugins search` and `.ai plugins install`.

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
| `archapp` | Utility | A guide to the Archimedes 3.0 application surface (Soul, Heartbeat, Scheduler, MCP, Dynamic UI, Service Chain). |
| `notes` | Productivity | Private and shared notes, with sharing and groups. |
| `tasks` | Productivity | Tasks and to-do lists, with reminders. |
| `events` | Productivity | Calendar events with reminders. |
| `groups` | Productivity | Shared groups for notes, tasks and events. |
| `git` | Developer | Read GitHub repositories: info, commits, files, issues, search. |
| `webtools` | Utility | Fetch web pages, look up Wikipedia, check the weather. |
| `expertmode` | Utility | Let the model retune its own turn into precise expert mode. |
| `coinflip` | Fun | Flip a coin -- the worked example. |
| `dice` | Fun | Roll dice with standard NdM notation. |
| `eightball` | Fun | Ask the magic 8-ball a question. |

The `coinflip` plugin also ships bundled with Archimedes, so it is installed
out of the box. Every other plugin here -- `notes`, `tasks`, `events`,
`groups`, `git`, `webtools`, `expertmode`, `dice` and `eightball` -- is an
install-only marketplace plugin.

### Agent tools

Beyond prefix commands, some plugins register **agent tools** -- functions
the model itself can call mid-conversation:

| Plugin | Tools |
|---|---|
| `archapp` | `arch.about` |
| `git` | `git.repo`, `git.commits`, `git.file`, `git.issues`, `git.search` |
| `webtools` | `web.fetch`, `web.wikipedia`, `web.weather` |
| `expertmode` | `mode.expert` |

`git` works on public repositories with no setup; an optional GitHub token --
the `.git setup` command, or the `PLUGIN_GIT_TOKEN` environment variable --
raises the API rate limit. `webtools` needs nothing; its APIs are free.
`expertmode` has no command at all: the model calls `mode.expert` mid-answer
to drop into a low-temperature, rigorous mode for the rest of the turn.

Image and video generation are not plugins: they are built into Archimedes
as the `image.generate` and `video.generate` tools, both running on
OpenRouter and tuned per server with `.ai model set image|video`.

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

M.commands  = { ... }           -- prefix commands
M.tools     = { ... }           -- agent tools
M.loops     = { ... }           -- background jobs
M.events    = { ... }           -- gateway and cross-plugin event handlers
M.on_load   = function() end    -- optional load hook
M.on_unload = function() end    -- optional unload hook

return M
```

The full plugin contract -- the `arch` global (the document and key/value
stores, the HTTP client, the Discord helpers, JSON and encoding utilities),
the per-call `ctx` table, events and card tables -- is documented in
[`plugins/README.md`](https://github.com/HiLleywyn/Archimedes/blob/main/plugins/README.md)
in the Archimedes repository. The `coinflip` and `dice` plugins here are
small, complete examples.

## Contributing a plugin

1. Add `plugins/<id>.lua`. The file name must equal `manifest.id`.
2. Run `python scripts/build_index.py` (needs `pip install lupa`).
3. Commit the plugin and the regenerated `index.json`.

CI compiles every plugin and fails if `index.json` is stale.
