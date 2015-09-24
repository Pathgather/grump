_         = require("underscore")
chalk     = require("chalk")
fs        = require("fs")
glob      = require("glob")
minimatch = require("minimatch")
path      = require("path")
Sync      = require("sync")

require('es6-promise').polyfill()
require('promise.prototype.finally')

GrumpCache = require("./grump_cache")
GrumpFS    = require("./grumpfs")
handlers   = require("./handlers")
util       = require("./util")

debug = false

# https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/RegExp/flags
if RegExp.prototype.flags == undefined
  Object.defineProperty RegExp.prototype, 'flags',
    configurable: true,
    get: -> this.toString().match(/[gimuy]*$/)[0]


tryStatic = (filename, cache_entry, options = {}) ->
  cache_entry.mtime = Grump.mtime
  new Promise (resolve, reject) ->
    fs.readFile filename, options, (err, result) ->
      if err
        cache_entry._static_error = true
        reject(err)
      else
        resolve(result)

# take a minimatch pattern and compile it to an array of regexes with capturing groups
makeCapturingRegexes = (pattern) ->
  # patterns used by minimatch for * and **. these can clearly change at any
  # time, so it's a good idea to keep minimatch locked and spec everything.
  qmark        = '[^/]'
  star         = qmark + '*?'
  twoStarDot   = '(?:(?!(?:\\\/|^)(?:\\.{1,2})($|\\\/)).)*?'
  twoStarNoDot = '(?:(?!(?:\\\/|^)\\.).)*?'

  makeRe = (pattern) ->
    if regex = minimatch.makeRe(pattern)
      addCapturingGroups = (str, pat) ->
        str.replace(pat, "(" + pat + ")")

      reSrc = [star, twoStarDot, twoStarNoDot].reduce(addCapturingGroups, regex.source)
      new RegExp(reSrc, regex.flags)

  minimatch.braceExpand(pattern).map(makeRe).filter(_.identity)

makeFilenamePattern = (route, filename) ->
  globs = route.match(/(\*+)/g)
  filename.replace /\$\d+/g, (match) ->
    globs[parseInt(match.slice(1)) - 1]

makeReverseFilenames = (route, filename) ->
  for route in minimatch.braceExpand(route)
    submatches = filename.match(/\$\d+/g)
    i = 0
    route.replace /\*+/g, (match) ->
      submatches[i++]

assertValidFilename = (route, filename) ->
  if route.split(/\*+/g).length != filename.split(/\$\d+/).length
    throw new Error("Grump: mismatched filename option '#{filename}' for route '#{route}'")

resolveCacheEntry = (promise, cache_entry, filename) ->
  ok = (result) ->
    console.log chalk.gray("cache save for"), filename if debug
    cache_entry.at = new Date()
    cache_entry.rejected = false
    cache_entry.result = result

  fail = (error) ->
    console.log chalk.red("cache save for " + "error"), filename if debug
    cache_entry.at = new Date()
    cache_entry.rejected = true
    cache_entry.result = error

    # attach a filename info the the error
    if not error._grump_filename
      error._grump_filename = filename

    return Promise.reject(error)

  # we want the cache entry to be updated before the caller
  # gets the resolved result, so we return a new promise here.
  return cache_entry.result = promise.then(ok, fail)

class Grump
  constructor: (config = {}) ->
    if not (@ instanceof Grump)
      return new Grump(config)

    @minimatch_opts = config.minimatch || {}
    @root = fs.realpathSync(config.root || ".")

    @routes = {}
    for route, handler of config.routes || {}
      handler = if typeof handler == "function"
        {handler}
      else
        _.extend({}, handler)

      route = path.join(@root, route)
      handler._expandedRoute = minimatch.braceExpand(route)

      if handler.tryStatic == true
        handler.tryStatic = "before"

      if handler.glob and typeof handler.glob != "function"
        throw new Error("Grump: glob option should be a function that returns all absolute paths matching the route")

      if handler.filename
        handler.filename = path.join(@root, handler.filename)
        assertValidFilename(route, handler.filename)
        handler._capturingRegexes = makeCapturingRegexes(route)

        # filenamePattern is used to match potential input files
        handler._filenamePattern = makeFilenamePattern(route, handler.filename)
        handler._filenamePatternRegexes = makeCapturingRegexes(handler._filenamePattern)

        # reverseFilename is used to generate output filenames from matched inputs
        handler._reverseFilenames = makeReverseFilenames(route, handler.filename)

      @routes[route] = handler

    if Object.keys(@routes).length == 0 and debug
      console.log "Grump: no routes were defined, Grump is not going to be very useful"

    @cache = new GrumpCache()

  glob: require("./grump_glob")
  require: require("./grump_require")
  serve: require("./grump_serve")

  _bypassSync: (fn) ->
    @__bypassSync = true
    result = fn()
    @__bypassSync = false
    return result

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

    filename = path.resolve(filename)

    # if there isn't a cache entry for this filename, create one assuming it's a real file
    if not @cache.get(filename)
      cache_entry = @cache.init(filename)
      cache_entry.mtime = Grump.mtime
      cache_entry.at = Grump.mtime(filename) || new Date()

    @_parent_entry.deps[filename] = true

  get: (filename) ->
    filename = path.resolve(filename)

    if @hasOwnProperty("_parent_entry")
      @_parent_entry.deps[filename] = true

    if cache_entry = @cache.get(filename)
      result = cache_entry.result

      if cache_entry.rejected == null and result and typeof result.then == "function"
        console.log chalk.green("cache hit for"), chalk.yellow("promise"), filename if debug
        return result
      else if @cache.current(filename)
        if cache_entry.rejected == false
          console.log chalk.green("cache hit for"), filename if debug
          return Promise.resolve(result)
        else if cache_entry.rejected == true
          console.log chalk.green("cache hit for"), chalk.red("error"), filename if debug
          return Promise.reject(result)

    cache_entry = @cache.init(filename)

    for route of @routes
      if minimatch(filename, route, @minimatch_opts)
        handler = @routes[route]
        break

    promise = if handler
      tryHandler = =>
        console.log chalk.yellow("running handler for #{filename}") if debug

        # create a new grump with attached cache_entry
        if @hasOwnProperty("_parent_entry")
          grump = Object.create(Object.getPrototypeOf(@))
        else
          grump = Object.create(@)

        # if we have a filename option on the handler, use it to transform the
        # the request filename using String.replace
        if handler.filename
          for regex in handler._capturingRegexes
            if regex.test(filename)
              reqFilename = filename.replace(regex, handler.filename)
              break

          if not reqFilename?
            # TODO: this is a known bug with patterns like /**/*.js and filename like /hello.js
            # normal minimatch will be ok with it, but our capturing regexes seem to miss it.
            throw new Error("Grump: the route '#{route}' in regex form didn't match #{filename}")
        else
          reqFilename = filename

        grump._parent_entry = cache_entry
        return grump.run(handler.handler, reqFilename)

      if handler.tryStatic == "before"
        # try reading the file from the file system and only try the handler
        # if that fails
        tryStatic(filename, cache_entry).catch(tryHandler)
      else if handler.tryStatic == "after"
        # try handler first and then the fs if that fails. return the original
        # error from the handler, though.
        tryHandler().catch (error) ->
          tryStatic(filename, cache_entry).catch ->
            Promise.reject(error)
      else
        tryHandler()

    else
      Promise.reject(new Error("Grump: no handler matched for #{filename}"))

    return resolveCacheEntry(promise, cache_entry, filename)

  getSync: (filename) ->
    if not Sync.Fibers.current
      throw new Error("Grump: tried to use a *Sync function while not in a fiber")

    promise = @get(filename)
    util.syncPromise(promise)

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
Grump.mtime    = (filename) -> try fs.statSync(filename).mtime
module.exports = Grump
