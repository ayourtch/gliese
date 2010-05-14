This is a small framework for easily writing tiny and fast web apps in Lua. 

The FastCGI configuration for lighttpd:

#----------------
server.modules   += ( "mod_fastcgi" )
#
fastcgi.server = ( ".lua" =>
    (( "socket" => "/tmp/lua.socket",
       "bin-path" => "/usr/local/bin/lwp.magnet",
       "max-procs" => 4 ))
)
#------------------

Here's an example of use:

require "lib/web"
require "lib/redis"

-- ...


function report_page(page, req, resp, params)
  local r = params.r
  local hash = sha1(r)
  local v4_count = redis:get(hash .. ":0")
  local prev_count = v4_count
  page.data = {}
  page.ref = r
  if v4_count then
    for i=1,4 do
      local v = redis:get(hash .. ":" .. tostring(i)) or 0
      page.data[i] = (prev_count - v)
      prev_count = v
    end
    page.data[5] = prev_count
  else
    page:redirect(script)
  end
end

function report_raw_page(page, req, resp, params)
  local r = params.r
  local hash = sha1(r)
  for i=0,4 do
    local v = redis:get(hash .. ":" .. tostring(i)) or 0
    page:write("<li>" .. v)
  end
end

-- ...

-- restore connection to redis if needed
if not _G['redis'] or not pcall(function() _G['redis']:get('*connect-test*') end) then
  _G['redis'] = Redis.connect('127.0.0.1', 6379)
end
redis = _G['redis']

-- routing

routing {
  print = print, read = read,
  get { "/", default_page, params = {
       test = { optional },
     }
  },
  post { "/", default_page },
  get { "/counter.gif", counter_page },
  get { "/report", "report_page", params = {
      r = { mandatory },
    },
  },
  get { "/report_raw", report_raw_page, params = {
      r = { mandatory },
    },
  },
  get { "/([0-9a-f]+)", counter_next_page, params = {
      s = { mandatory },
      r = { mandatory },
      path_capture_1 = { mandatory },
    },
  },
  get { ".*", redirect_request_to("/") },
}

