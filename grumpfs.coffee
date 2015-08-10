_ = require("underscore")
fs = require("fs")
path = require("path")
minimatch = require("minimatch")
coffee = require("coffee-script")
proxyquire = require('proxyquire')
stream = require("stream")
concat = require('concat-stream')
prettyHrtime = require('pretty-hrtime')
through = require('through2')
colors = require('colors')
angularTemplates = require('gulp-angular-templates')

# run all handlers until one of them resolves to a value
AnyHandler = (handlers...) ->
  return (file, grump) ->
    idx = 0

    catchHandler = (error) ->
      if handlers[idx]
        result = handlers[idx](file, grump)
        Promise.resolve(result)
          .catch (error) ->
            idx += 1
            catchHandler(error)

      else
        Promise.reject(error)

    catchHandler()

CoffeeHandler = (options = {}) ->
  return (file, grump) ->
    file = file.replace(/\.js$/, ".coffee")
    grump.get(file).then (source) ->
      coffee.compile(source, options)

GulpHandler = (options = {}) ->
  File = require("vinyl")
  stream = require("stream")

  if typeof options.transform != "function"
    throw new Error("GulpHandler: transform option to be a function that returns a transform stream")

  if not _.isArray(options.files) or options.files.length == 0
    throw new Error("GulpHandler: required files option missing")

  return (file, grump) ->
    new Promise (resolve, reject) ->

      transform = options.transform()
      transform.on("error", reject)

      pipe_in = new stream.Readable(objectMode: true)
      pipe_in._read = ->

      pipe_in
        .pipe(transform)
        .pipe concat (files) ->
          # join all vinyl files together to resolve the promise
          buffers = files.map (file) -> file.contents
          resolve(Buffer.concat(buffers).toString())

      promises = _.map options.files, (filename) ->
        _.tap grump.get(filename), (promise) ->
          promise.then (result) ->
            pipe_in.push(
              new File(
                path: filename
                contents: new Buffer(result)))

      Promise.all(promises)
        .then -> pipe_in.push(null)
        .catch(reject)

HamlHandler = (options = {}) ->
  hamlc = require('haml-coffee')
  return (file, grump) ->
    htmlfile = file.replace(".html", ".haml")
    grump.get(htmlfile)
      .then (source) ->
        hamlc.render(source)

StaticHandler = ->
  fn = (file) ->
    new Promise (resolve, reject) ->
      fs.readFile file, {encoding: "utf8"}, (err, result) ->
        err && reject(err) || resolve(result)

  fn.mtime = (file) ->
    try fs.statSync(file).mtime

  return fn

BrowserifyHandler = (options = {}) ->
  browserify = null

  initBrowserify = _.once (grump) ->
    browserify = proxyquire("browserify",
      fs: grump.fs
      resolve: proxyquire("browserify/node_modules/resolve",
        "./lib/async": proxyquire("browserify/node_modules/resolve/lib/async", fs: grump.fs))
      "browser-resolve": proxyquire("browserify/node_modules/browser-resolve", fs: grump.fs)
      "module-deps": proxyquire("browserify/node_modules/module-deps", fs: grump.fs))

  cache = {}
  fileCache = {}
  packageCache = {}

  count = 0

  return (targetFile, grump) ->

    initBrowserify(grump)

    console.log "bundle requested for", targetFile
    count += 1
    targetFile = targetFile.replace(/\?bundle$/, "")

    options.cache = cache
    options.fileCache = fileCache
    options.packageCache = packageCache

    bundle = syncBench "new bundle", ->
      browserify([], _.extend(options, basedir: path.dirname(targetFile)))

    new Promise (resolve, reject) ->

      # bundle.reset()

      bundle.pipeline.get("deps").push through.obj (row, enc, next) ->
        # this is for module-deps
        file = row.expose && bundle._expose[row.id] || row.file
        cache[file] =
            source: row.source,
            deps: _.extend({}, row.deps)

        this.push(row)
        next()

      fileStream = grump.fs.createReadStream(targetFile)
      fileStream.file = targetFile

      bundle
        .on("error", -> console.log "browserify error", arguments)
        .add(fileStream)
        .bundle (err, body) ->
          console.log "bundle complete"

          if count == 2

            console.log "cache", cache
            console.log "fileCache", fileCache
            console.log "packageCache", packageCache

          if err
            reject(err)
          else
            resolve(body.toString())

NotFoundError = (filename) ->
  errno: -2
  code: "ENOENT"
  path: filename

ReturnTrue = -> true
ReturnFalse = -> false

FileStat = (result) ->
  isFile: ReturnTrue
  isDirectory: ReturnFalse
  isFIFO: ReturnFalse
  size: result.length

DirStat = ->
  isFile: ReturnFalse
  isDirectory: ReturnTrue
  isFIFO: ReturnFalse

GrumpFS = (root, grump) ->
  grumpfs = {
    createReadStream: (filename, options) ->
      console.log ("createReadStream " + filename).gray

      st = new stream.Readable()
      st._read = ->

      grump.get(filename)
        .then (result) ->
          st.push(result)
          st.push(null)
        .catch (error) -> st.emit("error", error)

      return st

    readFile: (filename, options, callback) ->
      console.log ("readFile " + filename).gray
      if typeof options == "function"
        callback = options
        options = null

      grump.get(filename)
        .then (result) -> callback(null, result)
        .catch (error) -> callback(error, null)

    realpath: (filename, cache, callback) ->
      console.log ("realpath " + filename).gray

      if typeof cache == "function"
        callback = cache

      if not path.isAbsolute(filename)
        throw new Error("grump: unimplemented realpath #{filename}")

      callback(null, filename)

    stat: (filename, callback) ->
      console.log ("stat " + filename).gray
      grump.get(filename)
        .then (result) ->
          callback(null, FileStat(result))
        .catch (error) ->
          if error.code == "EISDIR"
            callback(null, DirStat())
          else
            callback(error, null)
  }

  # only run the functions above if the path is in the root
  checkRootFilename = (fn, fallback_fn) ->
    return (filename) ->
      if not path.isAbsolute(filename) or filename.indexOf("../") >= 0
        filename = path.resolve(filename)

      if filename.substring(0, root.length) == root
        fn(arguments...)
      else
        fallback_fn(arguments...)

  for func in Object.keys(grumpfs)
    grumpfs[func] = checkRootFilename(grumpfs[func], fs[func])

  # add logging to all non overridden fs methods
  logArguments = (func) ->
    return ->
      console.log "grump.fs: passing through to", func, arguments...
      return fs[func](arguments...)

  for func of require("fs")
    if not grumpfs[func]
      grumpfs[func] = logArguments(func)

  return grumpfs

class GrumpCache
  constructor: -> @_cache = {}
  get: (key) -> @_cache[key]
  init: (key) -> @_cache[key] = {deps: [], result: null}

  # an entry is current (not stale) if:
  # a) all deps are in cache and current
  # b) it has an at prop AND mtime prop and mtime() is less than at
  isCurrent: (key, expire = true) =>
    entry = @get(key)
    return false if not entry

    deps_current = _.map(entry.deps, @isCurrent)
    return false if not _.every(deps_current)

    if entry.mtime
      mtime = entry.mtime()

      if not entry.at?
        throw new Error("GrumpCache: possibly pending file tested for isCurrent: #{key}")

      if mtime? and entry.at > mtime
        return true
      else
        if expire
          @_cache[key] = undefined
        return false
    else
      return true

class Grump
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
        getNormalized: (_filename) ->
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

        promise = promise.then(updateEntry, updateEntry)

      return promise

    else
      Promise.reject(new NotFoundError(filename))

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
    @getNormalized(path.resolve(filename))

  findHandler: (filename) ->
    for route, handler of @routes
      if minimatch(filename, route)
        return handler
    return null

grump = new Grump
  root: "src"
  routes:
    "**/templates.js": GulpHandler
      files: ["src/hello.html"]
      transform: ->
        angularTemplates
          basePath: "/"
          module: "Pathgather"
    "**/*.js?bundle": BrowserifyHandler(grump)
    "**/*.js": AnyHandler(CoffeeHandler(), StaticHandler())
    "**/*.html": HamlHandler()
    "**": StaticHandler()

logRead = (err, src) ->
  if err
    logError(err)
  else
    console.log "src", src.toString()

asyncBench = (message = "", fn) ->
  start = process.hrtime()
  return ->
    done = process.hrtime(start)
    fn(arguments...)
    console.log message, "time", prettyHrtime(done).white

syncBench = (message = "", fn) ->
  start = process.hrtime()
  result = fn()
  done = process.hrtime(start)
  console.log message, "time", prettyHrtime(done).white
  return result

logError = (error) ->
  if error.stack
    console.log "error".red, error.stack
  else
    console.log "error".red, error.toString()

# fs.readFile("grumpfz.coffee", encoding: "utf8", logRead)
# grump.fs.readFile "src/hello.js?bundle", encoding: "utf8", (err, src) ->
#   if err
#     logError(err)
#   else
#     console.log "src length", src.length

#   grump.fs.readFile("src/hello.js?bundle", encoding: "utf8", asyncBench("try 2x", logRead))

# for i in [0...10]
#   grump.fs.readFile "src/hello.html", encoding: "utf8", ->

# setTimeout ->
#     grump.fs.readFile "src/hello.html", encoding: "utf8", ->
#   , 2000

grump.fs.readFile("src/templates.js", logRead)
# fn = -> grump.fs.readFile("src/templates.js", asyncBench("fetcheroo", ->))
# setInterval(fn, 1000)

# grump.fs.readFile "src/templates.js", ->
#   logRead(arguments...)
#   console.log grump.cache
