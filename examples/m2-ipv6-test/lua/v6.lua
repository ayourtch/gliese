require "gliese/web"
require "gliese/redis"
require "bit"
require "Sha1"

local secret = "change-me-please"
local v4_host = "testv6.stdio.be"
local v46_host = "v46.probe-v6.stdio.be"
local v6_host = "v6.probe-v6.stdio.be"
local v6_dns6_host = "v6-probe-for-stdio-be.onlyv6.com"
local script = "/v6.lua/"

--[[

Steps:

0. get the image via IPv4-only. ("counter.gif")
1. get the image via A+AAAA
2. get the image via IPv6-only. IPv4 NS.
3. get the image via IPv6-only, PMTU test.
4. get the image via IPv6-only, IPv6 DNS

]]

local redis = nil

function before_any_page(page, req, resp, params)
  -- restore connection to redis if needed
  if redis or not pcall(function() redis:get('*connect-test*') end) then
    redis = Redis.connect('127.0.0.1', 6379)
  end
  return true
end


function record_count(ref, step, remote_ip)
  -- this function records the hit for a given step on a given referer. 
  local hash = Sha1(ref)
  redis:increment(hash .. ":" .. tostring(step))
end

function default_page(page, req, resp, params) 
  -- rendered via template
end

function report_page(page, req, resp, params) 
  local r = params.r
  local hash = Sha1(r)
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
  local hash = Sha1(r)
  for i=0,4 do
    local v = redis:get(hash .. ":" .. tostring(i)) or 0
    page:write("<li>" .. v)
  end
end

function get_test_hash(referer, times)
  local hash = referer  
  for i = 1, times do
    hash = Sha1(secret .. ":" .. hash)
  end
  return hash
end

function counter_page(page, req, resp, params) 
  local ref = params.r or os.getenv("HTTP_REFERER")
  if ref then
    local hash = get_test_hash(ref, 1)
    record_count(ref, 0, os.getenv("REMOTE_ADDR"))
    page:redirect("http://" .. v46_host .. script .. hash .. "?r=" .. escape(ref) .. "&s=1")
  else
    page:redirect(script)
  end
end

function static_css(page, req, resp, params)
  render_verbatim(params.path_capture_1, page, req, resp, params)
  page.header["Content-Type"] = "text/css";
end

function static_js(page, req, resp, params)
  render_verbatim(params.path_capture_1, page, req, resp, params)
  page.header["Content-Type"] = "application/javascript";
end

function counter_next_page(page, req, resp, params)
  local s = tonumber(params.s)
  local r = params.r
  if s > 4 then 
    s = 4 
  end
  local hash_chk = get_test_hash(r, s)
  if params.path_capture_1 == hash_chk then
    local hash_nxt = get_test_hash(r, s + 1)
    record_count(r, s, os.getenv("REMOTE_ADDR"))
    if s == 1 then
      -- now IPv6-only
      page:redirect("http://" .. v6_host .. script .. hash_nxt .. "?r=" .. escape(r) .. "&s=2")
    elseif s == 2 then
      -- now lets send a big reply over IPv6.
      local filler = string.rep("X", 1500)
      page.header["X-MTU-Filler-1"] = filler
      page:redirect("http://" .. v6_host .. script .. hash_nxt .. "?r=" .. escape(r) .. "&s=3")
    elseif s == 3 then
      -- now let's send them to IPv6 with IPv6 DNS
      page:redirect("http://" .. v6_dns6_host .. script .. hash_nxt .. "?r=" .. escape(r) .. "&s=4")
    elseif s == 4 then
      -- They've reached us - full success!
      page.header["Content-Type"] = "image/gif"
      page:write(gif)
    end
  else
    page.header["Content-Type"] = "image/gif"
    page:write(gif)
  end
end


function gif_page(page, req, resp, params)
  page.header["Content-Type"] = "image/gif"
  page:write(gif)
end

-- single-pixel gif

if not gif then
  local c00 = string.char(0)
  local c01 = string.char(1)
  local c02 = string.char(2)
  local cFF = string.char(255)
  local c80 = string.char(128)
  local c04 = string.char(4)
  local cF9 = string.char(249)
  
  gif = "GIF89a" .. c01 .. c00 .. c01 .. c00 .. c80 .. c00 .. c00 .. c00 .. c00 .. c00 ..
        cFF .. cFF .. cFF .. "!" .. cF9 .. c04 .. c01 .. c00 .. c00 .. c00 .. c00 .. "," .. c00 .. c00 .. c00 .. c00 ..
        c01 .. c00 .. c01 .. c00 .. c00 .. c02 .. c01 .. "D" .. c00 .. ";"
     
end


-- restore connection to redis if needed
if not _G['redis'] or not pcall(function() _G['redis']:get('*connect-test*') end) then
  _G['redis'] = Redis.connect('127.0.0.1', 6379)
end
redis = _G['redis']

-- routing

mongrel2connect {
  sender_id = '558c92aa-1644-4e24-a524-39baad0f8e78',
  sub_addr = 'tcp://127.0.0.1:8989',
  pub_addr = 'tcp://127.0.0.1:8988',
  predicate = before_any_page,

  get { "/", "default_page", params = {
       test = { optional },
     }
  },
  post { "/", "default_page" },
  get { "/counter.gif", counter_page, params = {
      r = { optional },
    },
  },
  get { "(/css/[%-a-z]+%.css)", static_css, params = {
      path_capture_1 = { mandatory },
    },
  },
  get { "(/js/[%-a-z]+%.js)", static_js, params = {
      path_capture_1 = { mandatory },
    },
  },
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

