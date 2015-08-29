_         = require("underscore")
fs        = require("fs")
minimatch = require("minimatch")
path      = require("path")
Sync      = require("sync")
util      = require("./util")

GrumpCache = require("./grump_cache")
GrumpFS    = require("./grumpfs")
handlers   = require("./handlers")

normalizePath = (filename) ->

class Grump
  constructor: (config = {}) ->
    if not (@ instanceof Grump)
      return new Grump(config)

    @root = fs.realpathSync(config.root || ".")
    @routes = config.routes || {}
    @cache = new GrumpCache()

  require: require("./grump_require")
  serve: require("./grump_serve")

  Object.defineProperties @prototype,
    fs:
      get: ->
        if @hasOwnProperty("_fs")
          @_fs
        else
          @_fs ||= new GrumpFS(@)
      set: (@_fs) ->

  get: (filename) ->
    filename = path.resolve(filename)

    if cache_entry = @cache.get(filename)
      result = cache_entry.result

      if cache_entry.rejected == null
        console.log "cache hit for".green, "promise".yellow, filename
        return result
      else if @cache.isCurrent(filename)
        if cache_entry.rejected == false
          console.log "cache hit for".green, filename
          return Promise.resolve(result)
        else # assume it's an error
          console.log "cache hit for".green, "error".red, filename
          return Promise.reject(result)

    cache_entry = @cache.init(filename)
    handler = @findHandler(filename)

    if not handler
      promise = Promise.reject(new Error("file not found: #{filename}"))
      return @_resolveCacheEntry(promise, cache_entry, filename)

    console.log "running handler for #{filename}".yellow

    # create a new grump with attached cache_entry and
    # if we have one attached here, record the dependency
    if @hasOwnProperty("_parent_entry")
      @_parent_entry.deps.push(filename)
      grump = Object.create(Object.getPrototypeOf(@))
    else
      grump = Object.create(@)

    grump._parent_entry = cache_entry
    cache_entry.result = promise = grump.run(handler, filename)

    # if handler has an mtime function, we store the current time on the
    # cache_entry and the mtime functon to later compare if the underlying
    # files have been updated.
    if handler.mtime
      cache_entry.mtime = handler.mtime
      updateEntry = -> cache_entry.at = new Date()
      promise.then(updateEntry, updateEntry)

    return @_resolveCacheEntry(promise, cache_entry, filename)

  getSync: (filename) ->
    promise = @get(filename)
    util.syncPromise(promise)

  _resolveCacheEntry: (promise, cache_entry, filename) ->
    onResult = (result) ->
      console.log "cache save for", filename
      cache_entry.rejected = false
      cache_entry.result = result

    onError = (error) ->
      console.log "cache save for " + "error".red, filename
      cache_entry.rejected = true
      cache_entry.result = error

    promise.then(onResult, onError)
    return promise # return the original promise

  findHandler: (filename) ->
    if filename.indexOf(@root) == 0
      filename = filename.substring(@root.length)

    for route, handler of @routes
      if minimatch(filename, route)
        return handler

    return null

  run: (handler, filename) ->
    Promise.resolve(null).then =>
      handler(filename: filename, grump: @)

# handlers to the Grump object
_.extend(Grump, handlers)

Grump.GrumpFS = GrumpFS
module.exports = Grump
