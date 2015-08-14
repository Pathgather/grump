_ = require("underscore")
fs = require("fs")
path = require("path")
http = require("http")
minimatch = require("minimatch")
prettyHrtime = require('pretty-hrtime')

GrumpFS = require("./grumpfs")
GrumpCache = require("./grump_cache")
util = require("./util")
handlers = require("./handlers")

normalizePath = (filename) -> path.resolve(filename)

module.exports = class Grump
  constructor: (config) ->
    @root = fs.realpathSync(config.root || ".")
    @routes = config.routes || {}
    @cache = new GrumpCache()
    @fs = new GrumpFS(@root, @)

  getUncached: (filename, cache_entry) ->
    if handler = @findHandler(filename)
      console.log "running handler for #{filename}".yellow

      # wrap grump into something that records the calls to "get" to
      # build the dependency graph.
      old_get = @getNormalized
      grump = _.extend Object.create(@),
        get: (_filename) ->
          _filename = normalizePath(_filename)
          cache_entry.deps.push(_filename)
          old_get(_filename)

      promise = Promise.resolve(handler(filename, grump))

      # if handler has an mtime function, we store the current time on the
      # cache_entry and the mtime functon to later compare if the underlying
      # files have been updated.
      if handler.mtime
        cache_entry.mtime = _.partial(handler.mtime, filename)
        updateEntry = (result) ->
          cache_entry.at = new Date()
          return result

        promise.then(updateEntry, updateEntry)

      return promise

    else
      Promise.reject(new GrumpFS.NotFoundError(filename))

  getNormalized: (filename) =>
    if cache_entry = @cache.get(filename)
      result = cache_entry.result

      if typeof result.then == "function"
        console.log "cache hit for".green, "promise".yellow, filename
        return result
      else if @cache.isCurrent(filename)
        if result instanceof Buffer or typeof result == "string"
          console.log "cache hit for".green, filename
          return Promise.resolve(result)
        else # assume it's an error
          console.log "cache hit for".green, "error".red, filename
          return Promise.reject(result)

    cache_entry = @cache.init(filename)

    _.tap @getUncached(filename, cache_entry), (promise) ->
      cache_entry.result = promise
      promise
        .then (result) ->
          console.log "cache save for", filename
          cache_entry.result = result
        .catch (error) ->
          console.log "cache save for " + "error".red, filename
          cache_entry.result = error

  get: (filename) =>
    @getNormalized(normalizePath(filename))

  findHandler: (filename) ->
    for route, handler of @routes
      if minimatch(filename, route)
        return handler
    return null

  serve: (options = {}) ->
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

          console.log @cache
        .catch (error) ->
          util.logError(error)

          response.writeHead(500, {})
          response.end((error.stack || error).toString())

    http.createServer(handler).listen(options.port)

# handlers to the Grump object
_.extend(Grump, handlers)
