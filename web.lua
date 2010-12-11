_G = _G
local os = _G.os
local ipairs, pairs, table, string, collectgarbage = ipairs, pairs, table, string, collectgarbage
local arg = arg
local print, type, tostring = print, type, tostring
local getfenv = getfenv
local tonumber = tonumber
local tinsert = table.insert
local gsub = string.gsub
local find = string.find
local strsub = string.sub
local format = string.format
local concat = table.concat
local strfind = string.find
local io = io
local assert = assert
local loadstring = loadstring
local mongrel2 = require 'mongrel2'

local parent_env = getfenv(1)
module("web")
local this_env = getfenv(1)
local exports = { "get", "post", "routing", "redirect_request_to",
                  "mandatory", "optional", "numeric", "lisp_like_id",
		  "redirect_to_root", "render", "p", "include", "escape", "mongrel2connect"
                 }


debugging = false
-- debugging = true 

function redirect_request_to(uri)
  return function(page, req, resp, params)
    req.redirect_to(uri)
    print("Redirecting to uri:", uri)
    -- page:redirect(req.script_name .. uri)
  end
end


function begin_handling(mreq)
  local page = page_new()
  local request = {}
  local response = {}
  if mreq then
    local apath = mreq.headers.PATH
    local apatt = mreq.headers.PATTERN
    local asub = string.sub(apath, 1, #apatt)
    request.method = mreq.headers.METHOD
    # FIXME: this needs to be better than this
    if asub == apatt and not (string.sub(apath, #apath) == '/') then
      if apatt == '/' then
        request.url = apath
      else
        request.url = string.sub(apath, 1+#apatt)
      end
    else
      if apatt == '/' then
        request.url = apath
      else
        request.url = '/' -- mreq.headers.PATH
      end
    end

    if debugging then
      print("apath:", apath, " apatt:", apatt, " asub:", asub, " url:", 
            request.url)
    end
    
    request.query_string = mreq.headers.QUERY
    request.script_name = mreq.headers.PATTERN
    request.fullscripturl = "http://" ..
				mreq.headers.host .. mreq.headers.PATTERN
  else
    if not arg then
      request.method = os.getenv("REQUEST_METHOD")
      request.url = os.getenv("PATH_INFO")
      request.query_string = os.getenv("QUERY_STRING")
      request.script_name = os.getenv("SCRIPT_NAME")
      request.fullscripturl = "http://" .. os.getenv("SERVER_NAME") .. os.getenv("SCRIPT_NAME")
    else
      -- CLI testing
      print("CLI use")
      request.testing = true
      request.method = arg[1] or "GET"
      request.url = arg[2] or "/default_url_please_supply_correct" .. os.date("%s") -- "/"
      request.query_string = arg[3] or "test=1"
      request.script_name = arg[0]
      request.fullscripturl = "http://" .. "myserver" .. "/testscript.lua"
    end
  end

  request.redirect_to = function(uri)
    page:redirect(request.script_name .. uri)
  end
  page.url_to = function(page, path) 
    return(request.script_name .. path)
  end
  page.link_to = function(page, resource, text)
    return '<a href="' .. request.script_name .. resource .. '">' .. text .. '</a>'
  end
  page._ = {} -- temp storage for rendering
  return page, request, response
end

function end_handling(page)
  collectgarbage("step")
  if not page.no_default_response then
    local res = page:full_response()
    return page:zmq_response() 
    -- print(res)
  end
  -- return(res)
  -- print("200 HTTP/1.0 OK\r\nContent-length: 10\r\n\r\n0123456789\r\n")
end


-- core stuff - string operations

function split(str, pat)
  local t = {}  -- NOTE: use {n = 0} in Lua-5.0
  local fpat = "(.-)" .. pat
  local last_end = 1
  if str then
    local s, e, cap = str:find(fpat, 1)
    while s do
      if s ~= 1 or cap ~= "" then
	table.insert(t,cap)
      end
      last_end = e+1
      s, e, cap = str:find(fpat, last_end)
    end
    if last_end <= #str then
      cap = str:sub(last_end)
      table.insert(t, cap)
    end
  end
  return t
end

function split_path(str)
  return split(str,'[\\/]+')
end

function words(str)
  return split(str, "[ ]+")
end

-- serialization

function basicSerialize (o)
  if type(o) == "number" then
    return tostring(o)
  elseif type(o) == "nil" then
    return "nil"
  elseif type(o) == "boolean" then
    return tostring(o)
  else   -- assume it is a string
    return string.format("%q", o)
  end
end

function save (name, value, saved)
  saved = saved or {}       -- initial value
  local ret = name .. " = "
  if type(value) == "number" or type(value) == "string" or type(value) == "nil" or type(value) == "boolean" then
     ret = ret .. basicSerialize(value) .. "\n"
  elseif type(value) == "table" then
     if saved[value] then    -- value already saved?
       ret = ret .. saved[value] .. "\n"
     else
       saved[value] = name   -- save name for next time
       ret = ret .. "{}\n"     -- create a new table
       for k,v in pairs(value) do      -- save its fields
         local fieldname = string.format("%s[%s]", name, basicSerialize(k))
         ret = ret .. save(fieldname, v, saved)
       end
    end
  else
    ret = ret .. ("cannot save a " .. type(value))
  end
  return ret
end

-- string operations


function StringAccumulator()
  local otab = {""}

  otab.p = function(s)
    -- table.insert(otab, s)
    table.insert(otab, s)    -- push 's' into the the stack
    for i=table.getn(otab)-1, 1, -1 do
      if string.len(otab[i]) > string.len(otab[i+1]) then
        break
      end
      otab[i] = otab[i] .. table.remove(otab)
    end
  end

  otab.ppp = function(...)
    for i,v in ipairs(arg) do
      otab.p(v)
    end
  end

  otab.result = function(body)
    return table.concat(otab)
  end

  return otab
end


------ cgilua.urlcode

----------------------------------------------------------------------------
-- Decode an URL-encoded string (see RFC 2396)
----------------------------------------------------------------------------
function unescape (str)
	str = string.gsub (str, "+", " ")
	str = string.gsub (str, "%%(%x%x)", function(h) return string.char(tonumber(h,16)) end)
	str = string.gsub (str, "\r\n", "\n")
	return str
end

----------------------------------------------------------------------------
-- URL-encode a string (see RFC 2396)
----------------------------------------------------------------------------
function escape (str)
	str = string.gsub (str, "\n", "\r\n")
	str = string.gsub (str, "([^0-9a-zA-Z ])", -- locale independent
		function (c) return string.format ("%%%02X", string.byte(c)) end)
	str = string.gsub (str, " ", "+")
	return str
end

----------------------------------------------------------------------------
-- Insert a (name=value) pair into table [[args]]
-- @param args Table to receive the result.
-- @param name Key for the table.
-- @param value Value for the key.
-- Multi-valued names will be represented as tables with numerical indexes
--	(in the order they came).
----------------------------------------------------------------------------
function insertfield (args, name, value)
	if not args[name] then
		args[name] = value
	else
		local t = type (args[name])
		if t == "string" then
			args[name] = {
				args[name],
				value,
			}
		elseif t == "table" then
			table.insert (args[name], value)
		else
			error ("CGILua fatal error (invalid args table)!")
		end
	end
end

----------------------------------------------------------------------------
-- Parse url-encoded request data 
--   (the query part of the script URL or url-encoded post data)
--
--  Each decoded (name=value) pair is inserted into table [[args]]
-- @param query String to be parsed.
-- @param args Table where to store the pairs.
----------------------------------------------------------------------------
function parsequery (query, args)
	if type(query) == "string" then
		local insertfield, unescape = insertfield, unescape
		string.gsub (query, "([^&=]+)=([^&=]*)&?",
			function (key, val)
				insertfield (args, unescape(key), unescape(val))
			end)
	end
end

----------------------------------------------------------------------------
-- URL-encode the elements of a table creating a string to be used in a
--   URL for passing data/parameters to another script
-- @param args Table where to extract the pairs (name=value).
-- @return String with the resulting encoding.
----------------------------------------------------------------------------
function encodetable (args)
  if args == nil or next(args) == nil then   -- no args or empty args?
    return ""
  end
  local strp = ""
 for key, vals in pairs(args) do
    if type(vals) ~= "table" then
      vals = {vals}
    end
    for i,val in ipairs(vals) do
      strp = strp.."&"..escape(key).."="..escape(val)
    end
  end
  -- remove first & 
  return string.sub(strp,2)
end

------ cgilua.cookies

local function optional_value (what, name)
  if name ~= nil and name ~= "" then
    return format("; %s=%s", what, name)
  else
    return ""
  end
end


function build_cookie (name, value, options)
  if not name or not value then
    error("cookie needs a name and a value")
  end
  local expires = ""
  options = options or {}
  if options.expires then
    local t = date("!%A, %d-%b-%Y %H:%M:%S GMT", options.expires)
    expires = optional_value("expires", t)
  end
  return name .. "=" .. escape(value) ..
                        expires ..
                        optional_value("path", options.path) ..
                        optional_value("domain", options.domain) ..
                        optional_value("secure", options.secure)
end




----------------------------------------------------------------------------
-- Sets a value to a cookie, with the given options.
-- Generates an HTML META tag, thus it can be used in Lua Pages.
-- @param name String with the name of the cookie.
-- @param value String with the value of the cookie.
-- @param options Table with the options (optional).

function set_cookie_html (name, value, options)
  return format('<meta http-equiv="Set-Cookie" content="%s">', 
                build_cookie(name, value, options))
end


----------------------------------------------------------------------------
-- Gets the value of a cookie.
-- @param name String with the name of the cookie.
-- @return String with the value associated with the cookie.

function get_cookie (name)
  local cookies = os.getenv("HTTP_COOKIE") or ""
  cookies = ";" .. cookies .. ";"
  cookies = gsub(cookies, "%s*;%s*", ";")   -- remove extra spaces
  local pattern = ";" .. name .. "=(.-);"
  local _, __, value = strfind(cookies, pattern)
  return value and unescape(value)
end


----------------------------------------------------------------------------
-- Deletes a cookie, by setting its value to "xxx".
-- @param name String with the name of the cookie.
-- @param options Table with the options (optional).

function delete_cookie (name, options)
  options = options or {}
  options.expires = 1
  set_cookie(name, "xxx", options)
end

-- webpage stuff

function page_new()
  page = {
    body = StringAccumulator(),

    header = {
      ["Content-Type"] = "text/html; charset=utf-8",
      ["Status"] = "200"
    },

    redirect = function(t, url)
      t.header["Status"] = "302"
      t.header["Location"] = url
    end,


    write = function (pg, ...)
      for i,v in ipairs(arg) do
	pg.body.p(tostring(v))
      end
    end,
   
    render_form = function(pg, form)
      return render_form(form)
    end,

    add_form = function(pg, form)
      pg:write(render_form(form))
    end,

    set_cookie = function (pg, name, value, options)
      pg.header["Set-Cookie"] = build_cookie(name, value, options)
    end,

    zmq_response = function(pg)
      local body, code, status, headers
      body = pg.body.result()  
      code = 200
      status = "OK"
      if(pg.header["Status"]) then
        code = pg.header["Status"]
      end
      headers = pg.header
      return body, code, status, headers
    end, 

    full_response = function(pg) 
      local o = ""
      local hdr = StringAccumulator()
      local cnt = pg.body.result()
      local standalone = true
      pg.header["Content-Length"] = string.len(cnt)
      local firstline = ""
     

      for k, v in pairs(pg.header) do
	hdr.p(k .. ": " .. v .. "\r\n")
      end
      return firstline .. hdr.result() .. "\r\n" .. pg.body.result()

    end,
  }  
  return page
end

function send_response(printfunc)
end

------ forms


function render_form(form)
  if not form then return "" end
  local s = StringAccumulator()
  local p = s.ppp
  local pff = function()
    attrs = { "action", "id", "class", "style" }
    for i,fn in ipairs(attrs) do
      if form[fn] then p(" ", fn, "=\"", form[fn], "\"") end
    end
  end

  local esc = function(str)
    str = string.gsub(str, "\"", "&quot;")
    return str
  end

  local esc2 = function(str)
    str = string.gsub(str, "\<", "&lt;")
    return str
  end

  local pef = function(field, attrs)
    for i,fn in ipairs(attrs) do
      if field[fn] then 
        p(" ", fn, "=\"", esc(field[fn]), "\"") 
      end
    end
  end

  p("<form method=\"", (form.method or "get"), "\"")
  pff()
  p(">\n")
  for i,inp in ipairs(form) do
    if inp.html then
      p(inp.html)
    else
      local attrs  = { "name", "value", "id", "class", "style", "autocomplete", "title", "accesskey" }
      local attrs2 = { "name",          "id", "class", "style", "autocomplete", "title", "accesskey" }
      if inp.label then
        p("<label>", inp.label)
        if inp.small_label then
          p("<span class='small-label'>", inp.small_label, "</span>")
        end
        p("</label>")
      end
      if inp[1] == "textarea" then
        p("<textarea")
        pef(inp, attrs2)
        p(">")
        if inp.value then p(esc2(inp.value)) end
        p("</textarea>")
      else 
        p("<input type=\"", inp[1], "\"")
        pef(inp, attrs) 
        p(" />\n")
      end
    end
  end
  p("</form>\n")
  return s.result()
end

------


function check_param(src, k, v)
  local ret
  for i, chk in ipairs(v) do
    local ret, msg = chk(src, k)
    if ret == 0 then 
      return 0, msg
    elseif ret == 2 then 
      return 2
    end
  end
  -- if we made it to here, means all ok
  return 2 
end

function check_params(src, dst, template)
  local errors = {}
  for k, v in pairs(template) do
    if type(v) == "table" then
      local res, err = check_param(src, k, v)
      if res == 0 then
        errors[#errors + 1] = err
      else
        dst[k] = src[k]
      end
    end
  end
  return #errors == 0, errors
end

function pack(...)
  return arg
end

function request_method(meth, x)
  -- ease on the eye, the matches are always "whole-string"
  x[1] = "^" .. x[1] .. "$"
  return function(page, req, resp, params, predicate)
    -- logprint("page:" , page, req, resp, params)
    if req then
      -- if debugging then print("Method of ", req.method, meth) end
      if req.method == meth then
        local url_match = pack(string.match(req.url, x[1]))
        if debugging then
          print("trying to match:" .. req.url .. " against " .. x[1] .. " with result " .. tostring(#url_match) .. "<br>")
        end
        if #url_match > 0 then
          local local_params = {}
          for i, v in ipairs(url_match) do
            -- print(x[1], ":", i, ":", v)
            params["path_capture_" .. i] = unescape(v)
          end
          -- print("PARAMS", params.test)
          local res, errors = check_params(params, local_params, x.params or {} ) 
          if debugging then print("Param check:", res, errors) end
          if res then
            if predicate then
              if not predicate(page, req, resp, params) then
                if debugging then print("Precall failed, continue checking") end
                return "next"
              end
            end
            local funcname = x[2]
            if type(funcname) == "string" then
	      --- magic - to get the env of the "main" script
              local env = getfenv(4)
	      local func = env[funcname]
	      page._.controller = funcname
              local res2 = func(page, req, resp, local_params)
              if page._.controller and not page.rendered then
                render(page._.controller .. ".html", page, req, resp, local_params)
              end
              return res2
            elseif type(funcname) == "function" then
              local func = funcname
	      page._.controller = nil -- "*unknown*"
              return func(page, req, resp, local_params)
            end
          elseif x.next_if_bad_args then 
            -- fail soft if we were asked to
            if debugging then print("Validation error: " .. msg) end
          else
            -- fail hard (default)
            -- need to bounce off to the coroutine that will handle the error
            if x.on_error then
              return x.on_error(page, req, resp, params, errors)
            else
              return  
            end
          end
        end
      end
      return true
    else
      -- introspection (no request)
      return "Method: " .. meth .. " " .. x[1]
    end
  end
end


function get(x)
  return request_method("GET", x)
end

function post(x)
  return request_method("POST", x)
end

local steps = 0

local matcher = nil

function get_routes()
  return matcher(nil, nil, "routes")
end

function routing(rules, mreq)
  local page, request, response = begin_handling(mreq)
  --XX local parent_env = getfenv(2)
  print = rules.print
  read = rules.read
  --XX print, read = parent_env.print, parent_env.read
  if debugging then
    for i, r in ipairs(rules) do print(i, r(nil, nil)) end
  end
  -- the matcher function is a simple linear walker when it comes to business logic
  matcher = function(page, req, resp, params)
    -- print("Matcher arg:", page, req, resp, params)
    if req and resp then
      for i, func in ipairs(rules) do
	-- profiling
	steps = steps + 1  
	-- note that we are calling the function that was returned by the request_method function
	local res = func(page, req, resp, params, rules.predicate) 
        -- page:write("<br>".. req.url .. tostring(res))
	if res == nil then
          if debugging then print("Found: ", i) end
	  return true
	elseif res == "next" then
	  -- skip to next
	end
      end
    elseif not req and not resp then
      -- some introspection - to know when the version number has been bumped
      return rules.version
    elseif not req and resp == "routes" then
      local s = ""
      for i, r in ipairs(rules) do 
        s = s .. "\n" .. i .. ":" .. r(nil, nil)
      end
      return s
    end
  end
  local arguments = {}
  if request.method == "GET" then
    parsequery(request.query_string, arguments)
  elseif request.method == "POST" then
    parsequery(request.query_string, arguments)
    if not request.testing then
      parsequery(read(1000000), arguments)
    end
  end
  matcher(page, request, response, arguments) 
  return end_handling(page)
end


------ input fields validation predicates 

--[[

parameter predicates, they need to return:

0: failure.
1: continue checking
2: success, stop checking

]]

function optional(dirty_params, pname, clean_params)
  if dirty_params[pname] then
    return 1 
  else
    return 2
  end
end

function mandatory(dirty_params, pname, clean_params)
  if dirty_params[pname] then
    return 1 
  else
    return 0, { field = pname, message = "a mandatory parameter" }
  end
end

function numeric(dirty_params, pname, clean_params)
  -- FIXME
  if string.match(dirty_params[pname], "^[0-9]+$") then
    return 1
  else
    return 0, { field = pname, message = "should be numeric" }
  end
end

function lisp_like_id(dirty_params, pname, clean_params)
  if pname and dirty_params[pname] and string.match(dirty_params[pname], "^[-_a-zA-Z0-9]+$") then
    return 1 
  else
    return 0, { field = pname, message = "lisp-like field needed" }
  end
end

function redirect_to_root(page, req, resp, params)
  print("Redirecting to root")
  req.redirect_to("/")
end

---------- rendering / templating


function p(val)
  return (string.gsub(string.gsub(tostring(val or ""), "\"", "&quot;"), "\<", "&lt;"))
end

local outfunc = "table.insert(_render_result_,"


local function out (s, i, f)
        s = strsub(s, i, f or -1)
        if s == "" then return s end
        -- we could use `%q' here, but this way we have better control
        s = gsub(s, "([\\\n\'])", "\\%1")
        -- substitute '\r' by '\'+'r' and let `loadstring' reconstruct it
        s = gsub(s, "\r", "\\r")
        return format(" %s'%s'); ", outfunc, s)
end


function translate (s)
        s = gsub(s, "^#![^\n]+\n", "")
        if compatmode then
                s = gsub(s, "$|(.-)|%$", "<?lua = %1 ?>")
                s = gsub(s, "<!%-%-$$(.-)$$%-%->", "<?lua %1 ?>")
        end
        s = gsub(s, "<%%(.-)%%>", "<?lua %1 ?>")
        local res = { [[
function _render_(page, req, resp, params)
  local _render_result_ = {}
]] }
        local start = 1   -- start of untranslated part in `s'
        while true do
                local ip, fp, target, exp, code = find(s, "<%?(%w*)[ \t]*(=?)(.-)%?>", start)
                if not ip then break end
                tinsert(res, out(s, start, ip-1))
                if target ~= "" and target ~= "lua" then
                        -- not for Lua; pass whole instruction to the output
                        tinsert(res, out(s, ip, fp))
                else
                        if exp == "=" then   -- expression?
                                tinsert(res, format(" %s%s);", outfunc, code))
                        else  -- command
                                tinsert(res, format(" %s ", code))
                        end
                end
                start = fp + 1
        end
        tinsert(res, out(s, start))
        tinsert(res, "\rreturn table.concat(_render_result_);\rend\rreturn _render_\r")
        return concat(res)
end



local template_cache = {}

function compile (string, chunkname)
        local f, err = template_cache[string]
	-- FIXME: caching - the next line.
        -- if f then return f.func end
        f = {}
        f.func, err = loadstring (translate (string), chunkname)
        if f.func then 
          f.name = chunkname
          template_cache[string] = f
          return f.func
        else
          error (err, 3) 
          return nil
        end
end

local BOM = string.char(239) .. string.char(187) .. string.char(191)

function include(fname, page, req, resp, params)
  local fh = assert (io.open("./" .. req.script_name .. ".d/" .. fname))
  local src = fh:read("*a")
  fh:close()
  if src:sub(1,3) == BOM then src = src:sub(4) end
  local func = compile(src, fname)
  return func()(page, req, resp, params)
end

function render(fname, page, req, resp, params)
  page:write(include(fname, page, req, resp, params))
  page.rendered = true
  -- page:write(translate(src, fname))
end


function mongrel2connect(rules)
  local io_threads = 1
  local ctx = mongrel2.new(io_threads)

  -- Creates a new connection object using the mongrel2 context
  local conn = ctx:new_connection(rules.sender_id, rules.sub_addr, rules.pub_addr)

  while true do
    local req = conn:recv()

    if req:is_disconnect() then
        -- print 'Disconnected'
    else
        local response = ""
        -- response = response_string:format(req.sender, req.conn_id, req.path, dump(req.headers), req.body)
        conn:reply_http(req, routing(rules, req))
    end
  end

  ctx:term()
end

for i, v in ipairs(exports) do
  parent_env[v] = this_env[v]
end
