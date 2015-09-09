http         = require("http")
path         = require("path")
prettyHrtime = require("pretty-hrtime")
stripAnsi    = require("strip-ansi")
Sync         = require("sync")
url          = require("url")
util         = require("./util")

# Exposed as Grump#serve method, this method starts a web server that serves
# grump request as well as pretty prints the errors.
module.exports = (options = {}) ->
  if not options.port
    throw new Error("Grump: missing port option")

  grump = @

  logRequest = (request, response) ->
    start = process.hrtime()
    response.on "finish", ->
      process.stdout.write("#{request.method} #{request.url} - ")
      time = process.hrtime(start)
      console.log("Completed", response.statusCode, "in", prettyHrtime(time))


  handler = (request, response) =>
    logRequest(request, response)

    Sync ->
      try
        result = grump.getSync(path.join(grump.root, url.parse(request.url).pathname))
        code = 200

      catch error
        util.logError(error)

        result = (error.stack || error).toString()

        if error._grump_filename
          result = "Grump: error while bulding #{error._grump_filename}\n\n" + result

        result = stripAnsi(result)

        code = if error.code == "ENOENT" then 404 else 500
        headers = "Content-Type": "text/plain"

      finally
        response.writeHead(code, headers || {})
        response.end(result)

  http.createServer(handler).listen(options.port)
