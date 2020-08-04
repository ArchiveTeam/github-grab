dofile("table_show.lua")
dofile("urlcode.lua")
JSON = (loadfile "JSON.lua")()

local item_value = os.getenv('item_value')
local item_dir = os.getenv('item_dir')
local warc_file_base = os.getenv('warc_file_base')

local url_count = 0
local tries = 0
local downloaded = {}
local addedtolist = {}
local abortgrab = false

local latest_hovercard = nil
local ids = {}

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
  if string.match(url, "'+")
    or string.match(url, "[<>\\%*%$;%^%[%],%(%){}]")
    or string.match(url, "/hovercard$")
    or string.match(url, "^https?://github%.com/[^/]+/[^/]+/blob/")
    or string.match(url, "^https?://github%.com/[^/]+/[^/]+/tree/")
    or string.match(url, "^https?://github%.com/[^/]+/[^/]+/tree%-list/")
    or string.match(url, "^https?://github%.com/[^/]+/[^/]+/tree%-commit/")
    or string.match(url, "^https?://github%.com/[^/]+/[^/]+/commit/")
    or string.match(url, "^https?://github%.com/[^/]+/[^/]+/branches.")
    or string.match(url, "^https?://github%.com/[^/]+/[^/]+/commits/")
    or string.match(url, "^https?://github%.com/[^/]+/[^/]+/commits%?author=")
    or string.match(url, "^https?://github%.com/login%?")
    or string.match(url, "^https?://github%.com/join%?")
    or string.match(url, "^https?://github%.com/[^/]+/[^/]+/search.*[%?&]l=")
    or string.match(url, "^https?://github%.com/[^/]+/[^/]+/search.*[%?&]type=")
    or string.match(url, "^https?://github%.com/[^/]+/[^/]+/compare")
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
    or string.match(url, "^https?://avatars[0-9]*%.githubusercontent%.com/")
    or not (
      string.match(url, "^https?://[^/]*github%.com/")
      or string.match(url, "^https?://[^/]*githubusercontent%.com/")
    ) then
    return false
  end

  local match = string.match(url, "^https?://github%.com/[^/]+/[^/]+/[^/]+/?%?q=(.+%%3A.+)")
  if match then
    for s in string.gmatch(match, "([a-z%-]+)%%3A") do
      if s ~= "is" then
        return false
      end
    end
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

  if string.match(url, "^https?://[^/]*githubusercontent%.com/.") then
    return true
  end

  local prev = nil
  for s in string.gmatch(string.gsub(url, "%%2F", "/"), "([0-9a-zA-Z%-%._]+)") do
    if prev ~= nil and prev .. "/" .. s == item_value then
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

  local function check(urla, headers)
--[[    if string.match(urla, "/hovercard$") then
      if latest_hovercard == nil then
        print("No hovercard found...")
        abortgrab = true
      end
      return check(
        urla ..
        "?subject=" .. latest_hovercard ..
        "&current_path=" .. string.gsub(string.match(url, "^https?://[^/]+(/[^%?&]+)"), "/", "%%2F")
      )
    end]]
    local origurl = url
    local url = string.match(urla, "^([^#]+)")
    local url_ = string.gsub(string.match(url, "^(.-)%.?$"), "&amp;", "&")
    local url_ = string.match(url_, "^(.-)/?$")
    if (downloaded[url_] ~= true and addedtolist[url_] ~= true)
      and allowed(url_, origurl) then
      if string.match(url, "^https?://github%.com/[^/]*/[^/]+/graphs/contributors%-data$")
        or string.match(url, "^https?://github%.com/[^/]+/[^/]+/graphs/code%-frequency%-data$")
        or string.match(url, "^https?://github%.com/[^/]+/[^/]+/graphs/commit%-activity%-data$")
        or string.match(url, "^https?://github%.com/[^/]+/[^/]+/pulse_committer_data/daily$")
        or string.match(url, "^https?://github%.com/[^/]+/[^/]+/pulse_committer_data/weekly$")
        or string.match(url, "^https?://github%.com/[^/]+/[^/]+/pulse_committer_data/monthly$")
        or string.match(url, "^https?://github%.com/[^/]+/[^/]+/pulse_committer_data/halfweekly$")
        or string.match(url, "^https?://github%.com/[^/]+/[^/]+/pulse_committer_data$")
        or string.match(url, "^https?://github%.com/.+/hovercard%?subject=")
        or string.match(url, "^https?://github%.com/[^/]+/[^/]+/network/meta$")
        or string.match(url, "^https?://github%.com/[^/]+/[^/]+/network/chunk$") then
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

  local function checknewurl(newurl, headers)
    if string.match(newurl, "^https?:////") then
      check(string.gsub(newurl, ":////", "://"), headers)
    elseif string.match(newurl, "^https?://") then
      check(newurl, headers)
    elseif string.match(newurl, "^https?:\\/\\?/") then
      check(string.gsub(newurl, "\\", ""), headers)
    elseif string.match(newurl, "^\\/\\/") then
      check(string.match(url, "^(https?:)") .. string.gsub(newurl, "\\", ""), headers)
    elseif string.match(newurl, "^//") then
      check(string.match(url, "^(https?:)") .. newurl, headers)
    elseif string.match(newurl, "^\\/") then
      check(string.match(url, "^(https?://[^/]+)") .. string.gsub(newurl, "\\", ""), headers)
    elseif string.match(newurl, "^/") then
      check(string.match(url, "^(https?://[^/]+)") .. newurl, headers)
    elseif string.match(newurl, "^%./") then
      checknewurl(string.match(newurl, "^%.(.+)"), headers)
    end
  end

  local function checknewshorturl(newurl, headers)
    if string.match(newurl, "^%?") then
      check(string.match(url, "^(https?://[^%?]+)") .. newurl, headers)
    elseif not (string.match(newurl, "^https?:\\?/\\?//?/?")
        or string.match(newurl, "^[/\\]")
        or string.match(newurl, "^%./")
        or string.match(newurl, "^[jJ]ava[sS]cript:")
        or string.match(newurl, "^[mM]ail[tT]o:")
        or string.match(newurl, "^vine:")
        or string.match(newurl, "^android%-app:")
        or string.match(newurl, "^ios%-app:")
        or string.match(newurl, "^%${")) then
      check(string.match(url, "^(https?://.+/)") .. newurl, headers)
    end
  end

  if allowed(url, nil) and status_code == 200
    and not (
      string.match(url, "^https?://codeload%.github%.com/")
      or string.match(url, "^https?://github%.com/[^/]+/[^/]+/network/dependents$")
      or string.match(url, "^https?://[^/]*githubusercontent%.com/")
    ) then
    html = read_file(file)
    find = string.match(html, '<meta[^>]+name="hovercard%-subject%-tag"[^>]+content="([^"]+)"')
    if find then
      latest_hovercard = string.gsub(find, ":", "%%3A")
    end
    if string.match(url, "^https?://github%.com/[^/]+/[^/]+/pull/[0-9]+$")
      or string.match(url, "^https?://github%.com/[^/]+/[^/]+/issues/[0-9]+$") then
      local num = tonumber(string.match(url, "/([0-9]+)$"))
      for i=1,num do
        checknewshorturl(tostring(i))
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

wget.callbacks.httploop_result = function(url, err, http_stat)
  status_code = http_stat["statcode"]
  
  url_count = url_count + 1
  io.stdout:write(url_count .. "=" .. status_code .. " " .. url["url"] .. "  \n")
  io.stdout:flush()

  if status_code >= 300 and status_code <= 399 then
    local newloc = string.match(http_stat["newloc"], "^([^#]+)")
    if string.match(newloc, "^//") then
      newloc = string.match(url["url"], "^(https?:)") .. string.match(newloc, "^//(.+)")
    elseif string.match(newloc, "^/") then
      newloc = string.match(url["url"], "^(https?://[^/]+)") .. newloc
    elseif not string.match(newloc, "^https?://") then
      newloc = string.match(url["url"], "^(https?://.+/)") .. newloc
    end
    if downloaded[newloc] == true or addedtolist[newloc] == true or not allowed(newloc, url["url"]) then
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
      or (status_code >= 400 and status_code ~= 404)
      or status_code  == 0 then
    io.stdout:write("Server returned "..http_stat.statcode.." ("..err.."). Sleeping.\n")
    io.stdout:flush()
    local maxtries = 10
    if not allowed(url["url"], nil) then
        maxtries = 2
    end
    if tries > maxtries then
      io.stdout:write("\nI give up...\n")
      io.stdout:flush()
      tries = 0
      if allowed(url["url"], nil) then
        io.open("BANNED", "w"):close()
        return wget.actions.ABORT
      else
        return wget.actions.EXIT
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
