http         = require("http")
path         = require("path")
prettyHrtime = require("pretty-hrtime")
stripAnsi    = require("strip-ansi")
Sync         = require("sync")
url          = require("url")
util         = require("./util")

# Filter for serializing the cache, it ignores the contents
debug_filter = (prop, obj) ->
  if prop == "result" and typeof obj == "object" and obj?.type == "Buffer"
    "Buffer(...)"
  else
    obj

content_types = [
  [/\.css$/, "text/css"]
  [/\.html$/, "text/html"]
  [/\.js$/, "application/javascript"]
  [/\.gif$/, "image/gif"]
  [/\.jpg$/, "image/jpeg"]
  [/\.png$/, "image/png"]
  [/\.svg$/, "image/svg+xml"]
]

guess_content_type = (url) ->
  for [re, mime] in content_types
    if url.match(re)
      return mime

  return

# Exposed as Grump#serve method, this method starts a web server that serves
# grump request as well as pretty prints the errors.
module.exports = (options = {}) ->
  if not options.port
    throw new Error("Grump: missing port option")

  grump = @
  root = path.resolve(options.root || grump.root)

  logRequest = (request, response) ->
    start = process.hrtime()
    response.on "finish", ->
      process.stdout.write("#{request.method} #{request.url} - ")
      time = process.hrtime(start)
      console.log("Completed", response.statusCode, "in", prettyHrtime(time))


  handler = (request, response) =>
    logRequest(request, response)

    code = null
    headers = {}
    result = null

    Sync ->
      try
        request_path = url.parse(request.url).pathname

        if request_path == "/__debug"
          result = JSON.stringify(grump.cache, debug_filter, 2)
          headers["Content-Type"] = "application/json"
        else
          if request_path[request_path.length-1] == "/"
            request_path += "/index.html"

          result = grump.getSync(path.join(root, request_path))
          content_type = guess_content_type(request_path)
          headers["Content-Type"] = content_type if content_type

        code = 200

      catch error
        util.logError(error)

        result = (error.stack || error).toString()

        if error._grump_filename
          result = "Grump: error while bulding #{error._grump_filename}\n\n" + result

        result = stripAnsi(result)

        code = if error.code == "ENOENT" then 404 else 500
        headers["Content-Type"] = "text/plain"

      finally
        response.writeHead(code, headers || {})
        response.end(result)

  http.createServer(handler).listen(options.port)
