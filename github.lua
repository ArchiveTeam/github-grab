dofile("table_show.lua")
dofile("urlcode.lua")
JSON = (loadfile "JSON.lua")()
local urlparse = require("socket.url")

local item_value = os.getenv('item_value')
local item_dir = os.getenv('item_dir')
local item_config = os.getenv('item_config')
local warc_file_base = os.getenv('warc_file_base')

local item_value_low = string.lower(item_value)

local url_count = 0
local tries = 0
local downloaded = {}
local addedtolist = {}
local abortgrab = false

local latest_hovercard = nil
local is_fork = nil
local is_site = nil
local stars = nil
local forks = nil
--local site = nil
--local site_escaped = nil
local allowed_archive = {}

if not urlparse then
  io.stdout:write("Could not import socket.url.\n")
  io.stdout:flush()
  abortgrab = true
end

for ignore in io.open("ignore-list", "r"):lines() do
  downloaded[ignore] = true
end

load_json_file = function(file)
  if file then
    return JSON:decode(file)
  else
    return nil
  end
end

read_file = function(file)
  if file then
    local f = assert(io.open(file))
    local data = f:read("*all")
    f:close()
    return data
  else
    return ""
  end
end

allowed = function(url, parenturl)
--[[  if string.match(url, "^https?://www%.") then
    url = string.gsub(url, "^(https?://)www%.(.+)$", "%1%2")
  end

  if parenturl and string.match(parenturl, "^https?://www%.") then
    parenturl = string.gsub(parenturl, "^(https?://)www%.(.+)$", "%1%2")
  end]]

  if string.match(url, "'+")
    or string.match(url, "[<>\\%*%$;%^%[%],%(%){}]")
    or string.match(url, "/hovercard$")
    or string.match(url, "/hovercard%?")
    or string.match(url, "^https?://github%.com/[^/]+/[^/]+/blob/")
    or (
      string.match(url, "^https?://github%.com/[^/]+/[^/]+/tree/")
      and item_config ~= "complete"
    )
    or (
      string.match(url, "^https?://github%.com/[^/]+/[^/]+/commit/")
      and not string.match(url, "/rollup%?")
    )
    or string.match(url, "^https?://github%.com/[^/]+/[^/]+/branches.")
    or string.match(url, "^https?://github%.com/[^/]+/[^/]+/commits/")
    or string.match(url, "^https?://github%.com/[^/]+/[^/]+/commits%?author=")
    or string.match(url, "^https?://github%.com/login%?")
    or string.match(url, "^https?://github%.com/signup%?")
    or string.match(url, "^https?://github%.com/join%?")
    or string.match(url, "^https?://github%.com/[^/]+/[^/]+/search.*[%?&]l=")
    or string.match(url, "^https?://github%.com/[^/]+/[^/]+/search.*[%?&]type=")
    or string.match(url, "^https?://github%.com/[^/]+/[^/]+/compare")
    or string.match(url, "^https?://github%.com/[^/]+/[^/]+/refs$")
    or string.match(url, "^https?://github%.com/[^/]+/[^/]+/find%-definition$")
    or string.match(url, "^https?://github%.com/[^/]+/[^/]+/find/")
    or string.match(url, "^https?://github%.com/[^/]+/[^/]+/pull/?$")
    or string.match(url, "^https?://github%.com/[^/]+/[^/]+/[^/]+/?%?direction=.")
    or string.match(url, "^https?://github%.com/[^/]+/[^/]+/[^/]+/?%?sort=.")
    or string.match(url, "^https?://github%.com/[^/]+/[^/]+/labels/[^/%?&]+/?$")
    or string.match(url, "^https?://github%.com/[^/]+/[^/]+/projects/issues/[0-9]+$")
    or string.match(url, "^https?://github%.com/[^/]+/[^/]+/issues/closing_references")
    or string.match(url, "^https?://github%.com/[^/]+/[^/]+/issues/[0-9]*/?assignees")
    or string.match(url, "^https?://github%.com/[^/]+/[^/]+/issues/[0-9]+/set_milestone")
    or string.match(url, "^https?://github%.com/[^/]+/[^/]+/pulls/[0-9]+/set_milestone")
    or string.match(url, "^https?://github%.com/[^/]+/[^/]+/pulls/?[^%?]")
    or string.match(url, "^https?://github%.com/[^/]+/[^/]+/runs/[0-9]+/toolbar")
    or string.match(url, "^https?://github%.com/[^/]+/[^/]+/runs/[0-9]+/header")
    or string.match(url, "^https?://github%.com/[^/]+/[^/]+/runs/[0-9]+/unseen_check_steps")
    or string.match(url, "^https?://github%.com/[^/]+/[^/]+/runs/[0-9]+/step_summary")
    or string.match(url, "^https?://github%.com/[^/]+/[^/]+/suites/[0-9]+/show_partial%?check_suite_focus=")
    or string.match(url, "^https?://github%.com/[^/]+/[^/]+/actions/workflow%-run/[0-9]+$")
    or string.match(url, "^https?://github%.com/[^/]+/[^/]+/actions/runs/[0-9]+/workflow_run$")
    or string.match(url, "^https?://github%.com/[^/]+/[^/]+/pull/[0-9]+/files")
    or string.match(url, "^https?://github%.com/[^/]+/[^/]+/pull/[0-9]+/checks%?sha=")
    or string.match(url, "^https?://github%.com/[^/]+/[^/]+/pull/[0-9]+/show_partial")
    or string.match(url, "^https?://github%.com/[^/]+/[^/]+/pull/[0-9]+/change_base$")
    or string.match(url, "^https?://github%.com/[^/]+/[^/]+/pull/[0-9]+/review%-requests")
    or string.match(url, "^https?://github%.com/[^/]+/[^/]+/pull/[0-9]+/commits/[a-f0-9]+")
    or string.match(url, "^https?://github%.com/[^/]+/[^/]+/wiki/[^/]*/?_history$")
    or string.match(url, "^https?://github%.com/[^/]+/[^/]+/network/dependents%?")
    or string.match(url, "^https?://github%.com/[^/]+/[^/]+/stargazers/you_know$")
    or string.match(url, "^https?://github%.com/[^/]+/[^/]+/fork$")
    or string.match(url, "^https?://github%.com/[^/]+/[^/]+/search$")
    or string.match(url, "^https?://github%.com/_render_node/[^/]+/pull_requests/body")
    or string.match(url, "^https?://github%.com/_render_node/[^/]+/pull_requests/unread_timeline")
    or string.match(url, "^https?://github%.com/_render_node/[^/]+/pull_requests/commits_partial")
    or string.match(url, "^https?://github%.com/_render_node/[^/]+/issues/body")
    or string.match(url, "^https?://github%.com/_render_node/[^/]+/issues/unread_timeline")
    or string.match(url, "^https?://github%.com/_render_node/[^/]+/timeline/issue_comment")
    or string.match(url, "^https?://github%.com/_render_node/[^/]+/comments/review_comment")
    or string.match(url, "^https?://github%.com/_render_node/[^/]+/statuses/combined_branch_status")
    or string.match(url, "^https?://api%.github%.com/")
    or string.match(url, "^https?://avatars[0-9]*%.githubusercontent%.com/")
    or string.match(url, "/linked_closing_reference%?reference_location=REPO_ISSUES_INDEX$")
    or (
      string.match(url, "^https?://github%.com/[^/]+/[^/]+/archive/[^/]+%.zip$")
      and item_config ~= "complete"
    )
    or not (
      string.match(url, "^https?://[^/]*github%.com/")
      or string.match(url, "^https?://[^/]*githubusercontent%.com/")
      or string.match(url, "^https?://[^/]*github%.io")
      or string.match(url, "^https?://[^/]*amazonaws%.com/")
--      or (site and string.match(string.lower(url), site_escaped))
    ) then
    return false
  end

  local tested = {}
  for s in string.gmatch(url, "([^/]+)") do
    if tested[s] == nil then
      tested[s] = 0
    end
    if tested[s] == 6 then
      return false
    end
    tested[s] = tested[s] + 1
  end

  if string.match(url, "^https?://github%.com/_render_node/")
    or string.match(url, "^https?://github%.com/user_content_edits/") then
    return true
  end

  if parenturl
    and string.match(url, "^https?://github%.com/[^/]+/[^/]+/tree/")
    and (
      string.match(parenturl, "^https?://github%.com/[^/]+/[^/]+/tree/")
      or string.match(parenturl, "^https?://github%.com/[^/]+/[^/]+/file%-list/")
    ) then
    return false
  end

  match = string.match(url, "^https?://github%.com/[^/]+/[^/]+/[^/]+/?%?q=(.+%%3A.+)")
  if not match then
    match = string.match(url, "^https?://github%.com/[^/]+/[^/]+/[^/]+/?%?query=(.+%%3A.+)")
  end
  if match then
    for s in string.gmatch(match, "([a-z%-]+)%%3A") do
      if s ~= "is" then
        return false
      end
    end
  end

  if parenturl
    and item_config ~= "complete"
    and string.match(url, "^https?://github%.com/[^/]+/[^/]+/releases/tag/") then
    if string.match(parenturl, "^https?://github%.com/[^/]+/[^/]+/tags") then
      match = string.match(url, "^https?://github%.com/[^/]+/[^/]+/releases/tag/([^/%?]+)$")
      if (is_fork and not allowed_archive[match])
        or (stars == 0 and forks == 0 and not is_fork and not allowed_archive[match]) then
        return false
      end
    else
      return false
    end
  end

  if parenturl
    and item_config ~= "complete"
    and not string.match(parenturl, "^https?://github%.com/[^/]+/[^/]+/releases/tag/")
    and string.match(url, "^https?://github%.com/[^/]+/[^/]+/archive/") then
    return false
  end

--[[  if parenturl
    and string.match(url, "^https?://github%.com/[^/]+/[^/]+/archive/") then
    match = string.match(parenturl, "^https?://github%.com/[^/]+/[^/]+/releases/tag/([^/%?]+)$")
    if match then
      if is_fork and not allowed_archive[match] then
        return false
      end
    else
      return false
    end
  end]]

--[[  if site and string.lower(string.match(url, "^https?://([^/]+)")) == site then
    return true
  end]]

  if string.match(url, "^https?://[^/]*githubusercontent%.com/.") then
    return true
  end

  if string.match(url, "^https?://[^/]+amazonaws%.com/.")
    and not (
      parenturl
      and string.lower(string.match(parenturl, "^https?://(.+)$")) == "github.com/" .. item_value_low
    ) then
    return true
  end

  local a, b = string.match(url, "^https?://([^%.]+)%.github%.io/?([0-9a-zA-Z%-%._]*)")
  if a and b then
    a = string.lower(a)
    b = string.lower(b)
    if (not is_site and a .. "/" .. b == item_value_low)
      or (is_site and a == string.match(item_value_low, "^([^/]+)")) then
      return true
    end
  end

  local prev = nil
  for s in string.gmatch(string.gsub(url, "%%2F", "/"), "([0-9a-zA-Z%-%._]+)") do
    s = string.lower(s)
    if prev ~= nil and prev .. "/" .. s == item_value_low then
      return true
    end
    prev = s
  end

  return false
end

wget.callbacks.download_child_p = function(urlpos, parent, depth, start_url_parsed, iri, verdict, reason)
  local url = urlpos["url"]["url"]
  local html = urlpos["link_expect_html"]

  if string.match(url, "[<>\\%*%$;%^%[%],%(%){}\"]") then
    return false
  end
  
  return false
end

wget.callbacks.get_urls = function(file, url, is_css, iri)
  local urls = {}
  local html = nil
  
  downloaded[url] = true

  local function check(urla)
    local origurl = url
    local url = string.match(urla, "^([^#]+)")
    local url_ = string.gsub(string.match(url, "^(.-)%.?$"), "&amp;", "&")
    if not string.match(url_, "^https?://[^/]*github%.io/") then
      local url_ = string.match(url_, "^(.-)/?$")
    end
    if (downloaded[url_] ~= true and addedtolist[url_] ~= true)
      and allowed(url_, origurl) then
      if string.match(url, "^https?://github%.com/[^/]+/[^/]+/graphs/contributors%-data$")
        or string.match(url, "^https?://github%.com/[^/]+/[^/]+/graphs/code%-frequency%-data$")
        or string.match(url, "^https?://github%.com/[^/]+/[^/]+/graphs/commit%-activity%-data$")
        or string.match(url, "^https?://github%.com/[^/]+/[^/]+/graphs/traffic%-data$")
        or string.match(url, "^https?://github%.com/[^/]+/[^/]+/pulse_committer_data/daily$")
        or string.match(url, "^https?://github%.com/[^/]+/[^/]+/pulse_committer_data/weekly$")
        or string.match(url, "^https?://github%.com/[^/]+/[^/]+/pulse_committer_data/monthly$")
        or string.match(url, "^https?://github%.com/[^/]+/[^/]+/pulse_committer_data/halfweekly$")
        or string.match(url, "^https?://github%.com/[^/]+/[^/]+/pulse_committer_data$")
        or string.match(url, "^https?://github%.com/.+/hovercard%?subject=")
        or string.match(url, "^https?://github%.com/[^/]+/[^/]+/network/meta$")
        or string.match(url, "^https?://github%.com/[^/]+/[^/]+/network/chunk$")
        or string.match(url, "^https?://github%.com/user_content_edits/") then
        table.insert(urls, {
          url=url_,
          headers={["X-Requested-With"]="XMLHttpRequest"}
        })
      else
        table.insert(urls, { url=url_ })
      end
      addedtolist[url_] = true
      addedtolist[url] = true
    end
  end

  local function checknewurl(newurl)
    if string.match(url, "^https?://[^/]*%.github%.io/")
      and string.match(newurl, "[^A-Za-z0-9%-%._~:/%?#%[%]@!%$&'%(%)%*%+,;%%%\"=]") then
      return false
    end
    if string.match(newurl, "^https?:////") then
      check(string.gsub(newurl, ":////", "://"))
    elseif string.match(newurl, "^https?://") then
      check(newurl)
    elseif string.match(newurl, "^https?:\\/\\?/") then
      check(string.gsub(newurl, "\\", ""))
    elseif string.match(newurl, "^\\/") then
      checknewurl(string.gsub(newurl, "\\", ""))
    elseif string.match(newurl, "^//") then
      check(urlparse.absolute(url, newurl))
    elseif string.match(newurl, "^/") then
      check(urlparse.absolute(url, newurl))
    elseif string.match(newurl, "^%.%./") then
      if string.match(url, "^https?://[^/]+/[^/]+/") then
        check(urlparse.absolute(url, newurl))
      else
        checknewurl(string.match(newurl, "^%.%.(/.+)$"))
      end
    elseif string.match(newurl, "^%./")
      and newurl ~= "./chunk-webgl-warp.js"
      and newurl ~= "./chunk-contributions-spider-graph.js"
      and newurl ~= "./chunk-drag-drop.js"
      and newurl ~= "./chunk-image-crop-element-loader.js"
      and newurl ~= "./chunk-jump-to.js"
      and newurl ~= "./chunk-profile-pins-element.js"
      and newurl ~= "./chunk-runner-groups.js"
      and newurl ~= "./chunk-randomColor.js"
      and newurl ~= "./chunk-sortable-behavior.js"
      and newurl ~= "./chunk-tweetsodium.js"
      and newurl ~= "./chunk-user-status-submit.js"
      and newurl ~= "./chunk-unveil.js"
      and newurl ~= "./chunk-toast.js"
      and newurl ~= "./chunk-three.module.js"
      and newurl ~= "./chunk-severity-calculator-element.js"
      and newurl ~= "./chunk-series-table.js"
      and newurl ~= "./chunk-responsive-underlinenav.js"
      and newurl ~= "./chunk-ref-selector.js"
      and newurl ~= "./chunk-readme-toc-element.js"
      and newurl ~= "./chunk-profile.js"
      and newurl ~= "./chunk-notification-list-focus.js"
      and newurl ~= "./chunk-metric-selection-element.js"
      and newurl ~= "./chunk-line-chart.js"
      and newurl ~= "./chunk-launch-code-element.js"
      and newurl ~= "./chunk-invitations.js"
      and newurl ~= "./chunk-insights-query.js"
      and newurl ~= "./chunk-insights-graph.js"
      and newurl ~= "./chunk-filter-input.js"
      and newurl ~= "./chunk-failbot.js"
      and newurl ~= "./chunk-emoji-picker-element.js"
      and newurl ~= "./chunk-edit.js"
      and newurl ~= "./chunk-edit-hook-secret-element.js"
      and newurl ~= "./chunk-delayed-loading-element.js"
      and newurl ~= "./chunk-confetti.js"
      and newurl ~= "./chunk-color-modes.js"
      and newurl ~= "./chunk-codemirror.js"
      and newurl ~= "./chunk-animate-on-scroll.js"
      and newurl ~= "./compat.js" then
      check(urlparse.absolute(url, newurl))
    end
  end

  local function checknewshorturl(newurl)
    if string.match(newurl, "^%?") then
      check(urlparse.absolute(url, newurl))
    elseif not (string.match(newurl, "^https?:\\?/\\?//?/?")
        or string.match(newurl, "^[/\\]")
        or string.match(newurl, "^%./")
        or string.match(newurl, "^[jJ]ava[sS]cript:")
        or string.match(newurl, "^[mM]ail[tT]o:")
        or string.match(newurl, "^vine:")
        or string.match(newurl, "^android%-app:")
        or string.match(newurl, "^ios%-app:")
        or string.match(newurl, "^%${")) then
      check(urlparse.absolute(url, newurl))
    end
  end

--[[  local function checknewurlsite(newurl)
    if not site or not string.match(string.lower(url), site_escaped)
      or not string.match(newurl, "([^A-Za-z0-9%-%._~:/%?#%[%]@!%$&'%(%)%*%+,;%%%\"=])") then
      checknewurl(newurl)
    end
  end]]

  if allowed(url, nil) and status_code == 200
    and not (
      string.match(url, "^https?://codeload%.github%.com/")
      or string.match(url, "^https?://github%.com/[^/]+/[^/]+/network/dependents$")
      or string.match(url, "^https?://[^/]*githubusercontent%.com/")
      or string.match(url, "^https?://[^/]+amazonaws%.com/")
    ) then
    html = read_file(file)
    find = string.match(html, '<meta[^>]+name="hovercard%-subject%-tag"[^>]+content="([^"]+)"')
    if find then
      latest_hovercard = string.gsub(find, ":", "%%3A")
    end
    if string.match(url, "^https?://github%.com/[^/]+/[^/%?&]+$") and stars == nil then
      local match = string.match(html, '<meta%s+name="octolytics%-dimension%-repository_is_fork"%s+content="([^"]+)"%s*/>')
      if not match then
        io.stdout:write("Could not find fork information.\n")
        io.stdout:flush()
        abortgrab = True
      end
      match = string.lower(match)
      if match == "true" then
        is_fork = true
      elseif match == "false" then
        is_fork = false
      else
        io.stdout:write("Invalid value for fork information.\n")
      end
      match = string.match(html, '<a[^>]+href="[^"]+/stargazers"[^>]+aria%-label="([0-9]+) users? starred this repository">')
      if not match then
        io.stdout:write("Could not find number of stars.\n")
        io.stdout:flush()
        abortgrab = true
      end
      stars = tonumber(match)
      match = string.match(html, '<a[^>]+href="[^"]+/network/members"[^>]+aria%-label="([0-9]+) users? forked this repository">')
      if not match then
        io.stdout:write("Could not find number of forks.\n")
        io.stdout:flush()
        abortgrab = true
      end
      forks = tonumber(match)
      local a, b = string.match(item_value, "^([^/]+)/(.+)$")
      if string.match(item_value, "^[^/]+/[^%.]+%.github%.io$")
        and string.lower(a) == string.lower(string.match(item_value, "^[^/]+/([^%.]+)")) then
        is_site = true
        check("https://" .. b .. "/")
      else
        is_site = false
        check("https://" .. a .. ".github.io/" .. b .. "/")
      end
    elseif string.match(url, "^https?://github%.com/[^/]+/[^/]+/pull/[0-9]+$")
      or string.match(url, "^https?://github%.com/[^/]+/[^/]+/issues/[0-9]+$") then
      local num = tonumber(string.match(url, "/([0-9]+)$"))
      for i=1,num do
        checknewshorturl(tostring(i))
      end
--[[    elseif string.match(url, "^https?://api%.github%.com/repos/") then
      local json_data = load_json_file(html)
      is_fork = json_data["fork"]
      check("https://github.com/" .. item_value)
      if json_data["homepage"] and string.len(json_data["homepage"]) > 0
        and not string.match(json_data["homepage"], "^https?://[^/]*github%.io/.") then
        if not string.match(json_data["homepage"], "^https?://[^/]+/?$") then
          io.stdout:write("Unsupported homepage found.\n")
          io.stdout:flush()
          abortgrab = true
          return nil
        end
        site = string.lower(string.match(json_data["homepage"], "^https?://([^/]+)/?$"))
        local match = string.match(site, "^www%.(.+)$")
        if match then
          site = match
        end
        site_escaped = "^https?://" .. string.gsub(site, "([^%w])", "%%%1")
        check(json_data["homepage"])
      end]]
    elseif string.match(url, "^https?://github%.com/[^/]+/[^/]+/tags") then
      for s in string.gmatch(html, '<a%s+class="muted%-link"[^>]+href="/[^/]+/[^/]+/releases/tag/([^"]+)">[^<]+<svg[^>]+>%s*<path[^>]+>%s*</path>%s*</svg>%s*Notes%s*</a>') do
        allowed_archive[s] = true
      end
      for s in string.gmatch(html, '<a%s+class="muted%-link"[^>]+href="/[^/]+/[^/]+/releases/tag/([^"]+)">[^<]+<svg[^>]+>%s*<path[^>]+>%s*</path>%s*</svg>%s*Downloads%s*</a>') do
        allowed_archive[s] = true
      end
    end
    for newurl in string.gmatch(string.gsub(html, "&quot;", '"'), '([^"]+)') do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(string.gsub(html, "&#039;", "'"), "([^']+)") do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, ">%s*([^<%s]+)") do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, "href='([^']+)'") do
      checknewshorturl(newurl)
    end
    for newurl in string.gmatch(html, "[^%-]href='([^']+)'") do
      checknewshorturl(newurl)
    end
    for newurl in string.gmatch(html, '[^%-]href="([^"]+)"') do
      checknewshorturl(newurl)
    end
    for newurl in string.gmatch(html, ":%s*url%(([^%)]+)%)") do
      checknewurl(newurl)
    end
  end

  return urls
end

wget.callbacks.write_to_warc = function(url, http_stat)
  if http_stat["statcode"] == 429
    and string.match(url["url"], "^https?://github%.com/") then
    return false
  end
  return true
end

wget.callbacks.httploop_result = function(url, err, http_stat)
  status_code = http_stat["statcode"]
  
  url_count = url_count + 1
  io.stdout:write(url_count .. "=" .. status_code .. " " .. url["url"] .. "  \n")
  io.stdout:flush()

  if status_code >= 300 and status_code <= 399 then
    local newloc = urlparse.absolute(url["url"], http_stat["newloc"])
    if string.match(url["url"], "^https?://github%.com/[^/]+/[^/]+/releases/download/")
      and not string.match(newloc, "^https?://[^/]*amazonaws%.com/") then
      io.stdout:write("Found bad release download URL.\n")
      io.stdout:flush()
      abortgrab = true
    end
    if downloaded[newloc] == true or addedtolist[newloc] == true
      or not allowed(newloc, url["url"]) then
      tries = 0
      return wget.actions.EXIT
    end
  end
  
  if status_code >= 200 and status_code <= 399 then
    downloaded[url["url"]] = true
    downloaded[string.gsub(url["url"], "https?://", "http://")] = true
  end

  if abortgrab == true then
    io.stdout:write("ABORTING...\n")
    io.stdout:flush()
    return wget.actions.ABORT
  end
  
  if status_code >= 500
      or (
        status_code >= 400
        and status_code ~= 404
        and status_code ~= 406
        and status_code ~= 451
      )
      or status_code  == 0 then
    io.stdout:write("Server returned "..http_stat.statcode.." ("..err.."). Sleeping.\n")
    io.stdout:flush()
    local maxtries = 10
    if not allowed(url["url"], nil)
      or (
        string.match(url["url"], "^https?://[^/]*amazonaws%.com")
        and not string.match(url["url"], "^https?://[^/]*github")
      )
      or (
        string.match(url["url"], "^https?://camo%.githubusercontent%.com/")
        and status_code ~= 0
      )
      or (
        string.match(url["url"], "^https?://[^/]*githubusercontent%.com/")
        and status_code == 400
      ) then
      maxtries = 3
    end
    if tries >= maxtries then
      io.stdout:write("\nI give up...\n")
      io.stdout:flush()
      tries = 0
      if maxtries == 3 then
        return wget.actions.EXIT
      else
        return wget.actions.ABORT
      end
    else
      os.execute("sleep " .. math.floor(math.pow(2, tries)))
      tries = tries + 1
      return wget.actions.CONTINUE
    end
  end

  tries = 0

  local sleep_time = 0

  if sleep_time > 0.001 then
    os.execute("sleep " .. sleep_time)
  end

  return wget.actions.NOTHING
end

wget.callbacks.before_exit = function(exit_status, exit_status_string)
  if abortgrab == true then
    return wget.exits.IO_FAIL
  end
  return exit_status
end

