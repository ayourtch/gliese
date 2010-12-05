require 'gliese/web'
require 'gliese/redis'

function default_page(page, req, resp, params)
  -- this makes ab happy for microbenchmarking
  page.header["Connection"] = "Keep-Alive"

  page:write("<h1>This is a test!</h1>")
  page:write("\n\n")
  page:write("param:", params["test"])
  page:write("\n\n")
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
  get { "/", default_page, params = {
       test = { optional },
     }
  },
  get { "/foo", foo_page, params = {
       test = { optional },
     }
  },
  -- the rest does not really belong here, leftovers...
  -- but gives some impression

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
