_         = require("underscore")
chalk     = require("chalk")
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

    @minimatch_opts = config.minimatch || {}
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

  # add filename as a dependency for the current request
  dep: (filename) ->
    if not @_parent_entry
      throw new Error("Grump: dep() called with #{filename}, but no cache entry attached")

    if not @cache.get(filename)
      @get(filename)
    else
      @_parent_entry.deps.push(filename)

  get: (filename) ->
    filename = path.resolve(filename)

    if @hasOwnProperty("_parent_entry")
      @_parent_entry.deps.push(filename)

    if cache_entry = @cache.get(filename)
      result = cache_entry.result

      if cache_entry.rejected == null
        console.log chalk.green("cache hit for"), chalk.yellow("promise"), filename
        return result
      else if @cache.current(filename)
        if cache_entry.rejected == false
          console.log chalk.green("cache hit for"), filename
          return Promise.resolve(result)
        else # assume it's an error
          console.log chalk.green("cache hit for"), chalk.red("error"), filename
          return Promise.reject(result)

    cache_entry = @cache.init(filename)
    handler = @findHandler(filename)

    if not handler
      promise = Promise.reject(new Error("file not found: #{filename}"))
      return @_resolveCacheEntry(promise, cache_entry, filename)

    console.log chalk.yellow("running handler for #{filename}")

    # create a new grump with attached cache_entry
    if @hasOwnProperty("_parent_entry")
      grump = Object.create(Object.getPrototypeOf(@))
    else
      grump = Object.create(@)

    grump._parent_entry = cache_entry
    cache_entry.result = promise = grump.run(handler, filename)

    # if handler has an mtime function, we store the mtime functon to
    # later compare if the underlying files have been updated.
    cache_entry.mtime = handler.mtime if handler.mtime

    return @_resolveCacheEntry(promise, cache_entry, filename)

  getSync: (filename) ->
    if not Sync.Fibers.current
      throw new Error("Grump: tried to use a *Sync function while not in a fiber")

    console.log chalk.cyan("Grump#_assertInFiber: running in a fiber id = "), Sync.Fibers.current.id

    promise = @get(filename)
    util.syncPromise(promise)

  _resolveCacheEntry: (promise, cache_entry, filename) ->
    onResult = (result) ->
      console.log "cache save for", filename
      cache_entry.at = new Date()
      cache_entry.rejected = false
      cache_entry.result = result

    onError = (error) ->
      console.log chalk.red("cache save for " + "error"), filename
      cache_entry.at = new Date()
      cache_entry.rejected = true
      cache_entry.result = error

      # attach a filename info the the error
      if not error._grump_filename
        error._grump_filename = filename

    promise.then(onResult, onError)
    return promise # return the original promise

  findHandler: (filename) ->
    if filename.indexOf(@root) == 0
      filename = filename.substring(@root.length)

    for route, handler of @routes
      if minimatch(filename, route, @minimatch_opts)
        return handler

    return null

  run: (handler, filename) ->
    grump = @
    new Promise (resolve, reject) ->
      Sync ->
        try
          resolve(handler({filename, grump}))
        catch err
          reject(err)

# handlers to the Grump object
_.extend(Grump, handlers)

Grump.GrumpFS  = GrumpFS
Grump.Sync     = Sync
module.exports = Grump
