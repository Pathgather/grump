http = require("http")
prettyHrtime = require('pretty-hrtime')

# Exposed as Grump#serve method, this method starts a web server that serves
# grump request as well as pretty prints the errors.
module.exports = (options = {}) ->
  if not options.port
    throw new Error("Grump: missing port option")

  logRequest = (request, response) ->
    start = process.hrtime()
    response.on "finish", ->
      process.stdout.write("#{request.method} #{request.url} - ")
      time = process.hrtime(start)
      console.log("Completed", response.statusCode, "in", prettyHrtime(time))


  handler = (request, response) =>
    logRequest(request, response)

    @get(@root + request.url)
      .then (result) =>
        response.writeHead(200, {})
        response.end(result)

        # console.log @cache

      .catch (error) ->
        util.logError(error)

        response.writeHead(500, {})
        response.end((error.stack || error).toString())

  http.createServer(handler).listen(options.port)
