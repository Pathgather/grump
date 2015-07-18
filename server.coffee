http   = require("http")
Q      = require("q")
FS     = require("q-io/fs")
Reader = require("q-io/reader")
URL    = require("url")
path   = require("path")
events = require("events")
_      = require("underscore")
coffee = require("coffee-script")
minimatch = require("minimatch")
prettyHrtime = require('pretty-hrtime')

PORT = 8080

# TODO:
#   coffeescript
#   recursive gets
#   browserify / watchify
#   generate index files
#   annotate
#
#   sass
#   compass
#
# PRODUCTION:
#   env dependent settings
#   uglify

compileCoffee = (source, opts) ->
  coffee.compile(source, opts)

staticHandler = (root) ->
  return (env) -> FS.read(root + env.url)

coffeeHandler = (options) ->
  return (env) ->
    filename = "src/" + path.basename(env.url, ".js") + ".coffee"
    get(filename)
      .then (content) ->
        # console.log "got cofee to compile", content
        compileCoffee(content, filename: filename)
      .catch (error) ->
        # console.log "failed getting coffee source", error
        if error.code == "ENOENT"
          notFoundHandler(env)
        else
          if error.stack
            console.log error.stack
          errorHandler(env, error.toString() + "\n")

errorHandler = (env, body = "") ->
  [500, {"Content-Type": "text/plain"}, body || "500 Internal server error\n"]

notFoundHandler = (env) ->
  [404, {"Content-Type": "text/plain"}, "404 Not Found\n"]

buildPatternCache = (routes) ->
  patterns = _.keys(routes)
  regexes = _.map(patterns, minimatch.makeRe)
  _.object(patterns, regexes)

findMatchingPattern = (request, patternCache) ->
  _.find _.keys(patternCache), (pat) ->
    patternCache[pat].test(request.url)

logRequest = (request, response) ->
  start = process.hrtime()
  response.on "finish", ->
    process.stdout.write("#{request.method} #{request.url} - ")
    time = process.hrtime(start)
    console.log("Completed", response.statusCode, "in", prettyHrtime(time))

logError = (error) ->
  console.log error.stack

normalizeHandler = (handler) ->
  # wrap the handler to normalize the return value
  # it can be either:
  # * a string which is then sent to the client (with 200 ok)
  # * an array of [status, headers, body]
  # * a promise which resolves to one of the above
  normalize = (value) ->
    # console.log "normalizing", value
    if _.isArray(value) and value.length == 3
      # console.log "is.. array?"
      value
    else if _.isString(value)
      # console.log "be string"
      [200, {}, value]
    else
      # console.log "be something else"
      # console.log "unknown stuff", value
      [200, {}, value.toString()]

  return ->
    resp = handler.apply(undefined, arguments)
    # console.log "handler returned resp", resp
    if Q.isPromiseAlike(resp)
      # console.log "is promise"
      resp.then(normalize)
    else
      Q(normalize(resp))

# build the context that's received by all handlers
buildEnv = (request, response) ->
  method: request.method
  request: request
  response: response
  url: request.url

sendResponse = (response, [status, headers, body]) ->
  response.writeHead(status, headers)
  response.end(body)

fileNotFoundError = new Error("File not found")
fileNotFoundError.code = "ENOENT"

# request a file at this url. we do a real request here, but eventually
# it can short circuit the whole http stack and just direcly look up the
# right handler
get = (url) ->
  parsed = URL.parse(url)
  if not parsed.protocol
    parsed.protocol = "http:"
    parsed.hostname = "localhost"
    parsed.port = PORT

  deferred = Q.defer()

  http.get(URL.format(parsed))
    .on "response", (result) ->
      if result.statusCode == 200
        Reader(result).then (reader) ->
          reader.read().then (result) ->
            deferred.resolve(result.toString())
      else
        deferred.reject(fileNotFoundError)

    .on "error", (error) ->
      deferred.reject(error)

  deferred.promise

createHandler = (config) ->
  routes = _.clone(config.routes)

  # default that always matches
  if not routes["**"]
    routes["**"] = notFoundHandler

  for pattern, handler of routes
    routes[pattern] = normalizeHandler(handler)

  patternCache = buildPatternCache(routes)

  return (request, response) ->
    logRequest(request, response)
    env = buildEnv(request, response)
    pattern = findMatchingPattern(request, patternCache)

    callHandler = ->
      if handler = routes[pattern]
        handler(env)
      else
        notFoundHandler(env)

    Q.try(callHandler)
      .then (result) ->
        sendResponse(response, result)
      .catch (error) ->
        logError(error)
        sendResponse(response, errorHandler({}))
      .done()

handleRequest = createHandler
  routes:
    "/src/*.js": coffeeHandler()
    "/src/*.coffee": staticHandler(".")


http.createServer(handleRequest).listen(PORT)
