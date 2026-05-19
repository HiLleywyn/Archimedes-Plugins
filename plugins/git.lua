-- git.lua -- GitHub repository tools for Archimedes.
--
-- Read-only access to public GitHub repositories: repository summaries,
-- recent commits, file contents, issues and pull requests, and repository
-- search. Every call goes through the guarded plugin HTTP client.
--
-- Public repositories work with no configuration. To raise the API rate
-- limit and reach private repositories, supply a GitHub token either with
-- the `.git setup <token>` command (per server) or with the
-- PLUGIN_GIT_TOKEN environment variable (bot-wide).

local M = {}

M.manifest = {
  id = "git",
  name = "Git Tools",
  version = "1.0.0",
  description = "Read GitHub repositories: info, commits, files, issues, search.",
  author = "HiLleywyn",
  category = "Developer",
}

local API = "https://api.github.com"

local function trim(s)
  return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function clamp(value, low, high, default)
  local n = math.floor(tonumber(value) or default)
  if n < low then return low end
  if n > high then return high end
  return n
end

-- Percent-encode one URL component.
local function urlencode(s)
  return (tostring(s or ""):gsub("[^%w%-%._~]", function(c)
    return string.format("%%%02X", string.byte(c))
  end))
end

-- ── per-server configuration ─────────────────────────────────────────────────
local function ckey(guild_id, name)
  return "cfg:" .. (guild_id or "0") .. ":" .. name
end

local function get_token(guild_id)
  local value = arch.kv.get(ckey(guild_id, "token"))
  if value ~= nil and value ~= "" then return value end
  -- Fall back to the operator-set PLUGIN_GIT_TOKEN environment variable.
  local env = (arch.config or {}).token
  if env ~= nil and env ~= "" then return env end
  return nil
end

local function is_owner(ctx)
  local guild = arch.discord.guild(ctx.guild_id)
  return guild ~= nil and guild.owner_id == ctx.author_id
end

-- ── the GitHub API call ──────────────────────────────────────────────────────
-- GETs an API path. Returns (json, nil) on success, or (nil, error) on failure.
local function gh_get(guild_id, path)
  local headers = {
    Accept = "application/vnd.github+json",
    ["User-Agent"] = "Archimedes-Plugin",
    ["X-GitHub-Api-Version"] = "2022-11-28",
  }
  local token = get_token(guild_id)
  if token then headers.Authorization = "Bearer " .. token end

  local res = arch.http.get(API .. path, { headers = headers, timeout = 20 })
  if not res then return nil, "the request could not be sent" end
  if res.status == 404 then return nil, "not found on GitHub" end
  if res.status == 403 or res.status == 429 then
    return nil, "GitHub rate limit reached. An admin can raise it with "
      .. "`.git setup <token>`."
  end
  if not res.ok then
    local msg = res.json and res.json.message
    return nil, "GitHub error: " .. tostring(msg or res.error
      or ("http " .. res.status))
  end
  if res.json == nil then
    return nil, "GitHub returned an unreadable response"
  end
  return res.json, nil
end

-- Validate an `owner/name` repository slug.
local function valid_repo(repo)
  repo = trim(repo)
  if repo:match("^[%w%.%-_]+/[%w%.%-_]+$") then return repo end
  return nil
end

-- ── agent tools ──────────────────────────────────────────────────────────────
M.tools = {
  {
    name = "git.repo",
    description = "Get information about a GitHub repository: description, "
      .. "star and fork counts, primary language, open issue count and "
      .. "default branch.",
    parameters = {
      type = "object",
      properties = {
        repo = {
          type = "string",
          description = "Repository as owner/name, e.g. discord/discord.py.",
        },
      },
      required = { "repo" },
    },
    handler = function(args, ctx)
      local repo = valid_repo(args.repo)
      if not repo then return { error = "repo must be in owner/name form" } end
      local j, err = gh_get(ctx.guild_id, "/repos/" .. repo)
      if err then return { error = err } end
      return {
        full_name = j.full_name,
        description = j.description,
        stars = j.stargazers_count,
        forks = j.forks_count,
        language = j.language,
        open_issues = j.open_issues_count,
        default_branch = j.default_branch,
        topics = j.topics,
        archived = j.archived,
        pushed_at = j.pushed_at,
        url = j.html_url,
      }
    end,
  },
  {
    name = "git.commits",
    description = "List recent commits on a GitHub repository branch.",
    parameters = {
      type = "object",
      properties = {
        repo = { type = "string", description = "Repository as owner/name." },
        branch = {
          type = "string",
          description = "Branch name. Defaults to the repository default branch.",
        },
        limit = {
          type = "integer",
          description = "How many commits to return, 1 to 20. Default 10.",
        },
      },
      required = { "repo" },
    },
    handler = function(args, ctx)
      local repo = valid_repo(args.repo)
      if not repo then return { error = "repo must be in owner/name form" } end
      local limit = clamp(args.limit, 1, 20, 10)
      local path = "/repos/" .. repo .. "/commits?per_page=" .. limit
      if args.branch and trim(args.branch) ~= "" then
        path = path .. "&sha=" .. urlencode(trim(args.branch))
      end
      local j, err = gh_get(ctx.guild_id, path)
      if err then return { error = err } end
      local commits = {}
      for _, c in ipairs(j) do
        local commit = c.commit or {}
        local author = commit.author or {}
        commits[#commits + 1] = {
          sha = (c.sha or ""):sub(1, 7),
          message = (commit.message or ""):match("^[^\n]*"),
          author = author.name,
          date = author.date,
        }
      end
      return { repo = repo, count = #commits, commits = commits }
    end,
  },
  {
    name = "git.file",
    description = "Read a text file from a GitHub repository.",
    parameters = {
      type = "object",
      properties = {
        repo = { type = "string", description = "Repository as owner/name." },
        path = { type = "string", description = "Path to the file in the repo." },
        ref = {
          type = "string",
          description = "Branch, tag or commit to read from. Optional.",
        },
      },
      required = { "repo", "path" },
    },
    handler = function(args, ctx)
      local repo = valid_repo(args.repo)
      if not repo then return { error = "repo must be in owner/name form" } end
      local fpath = trim(args.path):gsub("^/+", "")
      if fpath == "" then return { error = "a file path is required" } end
      local url = "/repos/" .. repo .. "/contents/"
        .. fpath:gsub("[^/]+", urlencode)
      if args.ref and trim(args.ref) ~= "" then
        url = url .. "?ref=" .. urlencode(trim(args.ref))
      end
      local j, err = gh_get(ctx.guild_id, url)
      if err then return { error = err } end
      if j.type ~= "file" then return { error = "that path is not a file" } end
      if not j.content or j.content == "" then
        return { error = "the file is empty or too large to read" }
      end
      if j.encoding ~= "base64" then
        return { error = "the file could not be decoded" }
      end
      local text = arch.base64.decode((j.content:gsub("%s", "")))
      if text == nil then return { error = "the file is not UTF-8 text" } end
      return {
        repo = repo, path = j.path, size = j.size,
        content = arch.clip(text, 6000),
      }
    end,
  },
  {
    name = "git.issues",
    description = "List recent issues and pull requests on a GitHub repository.",
    parameters = {
      type = "object",
      properties = {
        repo = { type = "string", description = "Repository as owner/name." },
        state = {
          type = "string",
          enum = { "open", "closed", "all" },
          description = "Which issues to list. Default open.",
        },
        limit = {
          type = "integer",
          description = "How many to return, 1 to 20. Default 10.",
        },
      },
      required = { "repo" },
    },
    handler = function(args, ctx)
      local repo = valid_repo(args.repo)
      if not repo then return { error = "repo must be in owner/name form" } end
      local state = args.state
      if state ~= "closed" and state ~= "all" then state = "open" end
      local limit = clamp(args.limit, 1, 20, 10)
      local j, err = gh_get(ctx.guild_id, "/repos/" .. repo
        .. "/issues?state=" .. state .. "&per_page=" .. limit)
      if err then return { error = err } end
      local issues = {}
      for _, it in ipairs(j) do
        issues[#issues + 1] = {
          number = it.number,
          title = it.title,
          state = it.state,
          author = it.user and it.user.login,
          is_pull_request = it.pull_request ~= nil,
          comments = it.comments,
          url = it.html_url,
        }
      end
      return { repo = repo, state = state, count = #issues, issues = issues }
    end,
  },
  {
    name = "git.search",
    description = "Search GitHub for repositories by keyword.",
    parameters = {
      type = "object",
      properties = {
        query = { type = "string", description = "Search keywords." },
        limit = {
          type = "integer",
          description = "How many results to return, 1 to 15. Default 8.",
        },
      },
      required = { "query" },
    },
    handler = function(args, ctx)
      local query = trim(args.query)
      if query == "" then return { error = "a search query is required" } end
      local limit = clamp(args.limit, 1, 15, 8)
      local j, err = gh_get(ctx.guild_id, "/search/repositories?q="
        .. urlencode(query) .. "&per_page=" .. limit)
      if err then return { error = err } end
      local repos = {}
      for _, r in ipairs(j.items or {}) do
        repos[#repos + 1] = {
          full_name = r.full_name,
          description = r.description,
          stars = r.stargazers_count,
          language = r.language,
          url = r.html_url,
        }
      end
      return { query = query, count = #repos, repos = repos }
    end,
  },
}

-- ── command tree ─────────────────────────────────────────────────────────────
M.commands = {
  {
    name = "git", aliases = { "github" },
    summary = "Look up GitHub repositories.",
    usage = "git repo <owner/name>",
    run = function(ctx)
      ctx.reply({
        title = "Git Tools", color = arch.colors.info,
        description = "Read GitHub from chat.\n"
          .. "`" .. ctx.prefix .. "git repo <owner/name>` -- repository summary\n"
          .. "`" .. ctx.prefix .. "git setup <token>` -- raise the rate limit "
          .. "(server owner only)\n"
          .. "Archimedes can also call the `git.*` tools itself.",
      })
    end,
    subcommands = {
      { name = "repo", usage = "repo <owner/name>",
        summary = "Show a GitHub repository summary.",
        run = function(ctx)
          local repo = valid_repo(ctx.args)
          if not repo then
            ctx.error("Usage: `" .. ctx.prefix .. "git repo owner/name`")
            return
          end
          local j, err = gh_get(ctx.guild_id, "/repos/" .. repo)
          if err then ctx.error(err) return end
          ctx.reply({
            title = j.full_name, url = j.html_url, color = arch.colors.info,
            description = j.description or "(no description)",
            fields = {
              { name = "Stars", value = tostring(j.stargazers_count or 0),
                inline = true },
              { name = "Forks", value = tostring(j.forks_count or 0),
                inline = true },
              { name = "Language", value = j.language or "n/a", inline = true },
              { name = "Open issues",
                value = tostring(j.open_issues_count or 0), inline = true },
              { name = "Default branch", value = j.default_branch or "n/a",
                inline = true },
            },
          })
        end },
      { name = "setup", usage = "setup <github-token>", guild_only = true,
        summary = "Set a GitHub API token (server owner only).",
        run = function(ctx)
          if not is_owner(ctx) then
            ctx.error("Only the server owner can set the GitHub token.")
            return
          end
          local token = (ctx.args or ""):gsub("%s", "")
          if token == "" then
            ctx.error("Usage: `" .. ctx.prefix .. "git setup <github-token>`")
            return
          end
          arch.kv.set(ckey(ctx.guild_id, "token"), token)
          ctx.ok("GitHub token saved. The API rate limit is now raised.")
        end },
      { name = "status", usage = "status",
        summary = "Show whether a GitHub token is configured.",
        run = function(ctx)
          local has = get_token(ctx.guild_id) ~= nil
          ctx.reply({
            title = "Git Tools",
            color = has and arch.colors.success or arch.colors.neutral,
            description = has and "A GitHub token is configured."
              or "No token set. Public repositories work at a lower rate limit.",
          })
        end },
    },
  },
}

return M
