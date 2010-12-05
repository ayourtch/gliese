This is a small framework for easily writing tiny 
and fast web apps in Lua for Mongrel2.

(There are still some remnants of FCGI but I focus 
on working as a zmq backend for mongrel2)

This code is in alpha stage - lots of things may change.

Don't use it in production.

An example client:
-----------------
require 'gliese/web'
require 'gliese/redis'

function default_page(page, req, resp, params)
  -- this makes ab happy for microbenchmarking
  page.header["Connection"] = "Keep-Alive"

  page:write("<h1>This is a test!</h1>")
  page:write("param:", params["test"])
end

function foo_page(page, req, resp, params)
  page:write("<h1>This is a foo test page!</h1>")
  page:write("param:", params["test"])
end


mongrel2connect {
  sender_id = '558c92aa-1644-4e24-a524-39baad0f8e78',
  sub_addr = 'tcp://127.0.0.1:8989',
  pub_addr = 'tcp://127.0.0.1:8988',

  print = print, read = read,

  -- Routing 

  get { "/", default_page, params = {
       test = { optional },
     }
  },
  get { "/foo", foo_page, params = {
       test = { mandatory },
     }
  },
  -- Anything else just redirect to root
  get { ".*", redirect_request_to("/") },
}

