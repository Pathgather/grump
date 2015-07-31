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

# run all handlers until one of them resolves to a value
AnyHandler = (handlers...) ->
  return (file) ->
    idx = 0

    catchHandler = (error) ->
      if handlers[idx]
        result = handlers[idx](file)
        Promise.resolve(result)
          .catch (error) ->
            idx += 1
            catchHandler(error)

      else
        Promise.reject(error)

    catchHandler()

CoffeeHandler = (grump, options = {}) ->
  return (file) ->
    file = file.replace(/\.js$/, ".coffee")
    grump.get(file).then (source) ->
      coffee.compile(source, options)

StaticHandler = ->
  return (file) ->
    new Promise (resolve, reject) ->
      fs.readFile file, {encoding: "utf8"}, (err, result) ->
        err && reject(err) || resolve(result)

BrowserifyHandler = (grump, options = {}) ->
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

  return (targetFile) ->
    console.log "bundle requested for", targetFile
    count += 1
    targetFile = targetFile.replace(/\?bundle$/, "")

    options.cache = cache
    options.fileCache = fileCache
    options.packageCache = packageCache

    bundle = syncBench "new bundle", -> browserify([], options)

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

      bundle
        .on("error", -> console.log "browserify error", arguments)
        .add(targetFile)
        .bundle (err, body) ->
          console.log "bundle complete"

          if count == 3

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

class Grump
  constructor: (root, configFunc) ->
    root = fs.realpathSync(root)

    if typeof configFunc != "function"
      throw new Error("grump: missing config function")

    findHandler = (filename, routes) ->
      for route, handler of routes
        if minimatch(filename, route)
          # console.log "route matched", route, "with", filename
          return handler

      return null

    @cache = cache = {}

    @get = (filename) ->
        # console.log "grump: getting", filename
        if filename.indexOf("?bundle") == -1
          switch typeof @cache[filename]
            when "string"
              console.log ("cache hit for " + filename).green
              return Promise.resolve(@cache[filename])
            when "undefined"
              break
            when "object"
              console.log ("cache hit for (error) " + filename).green
              return Promise.reject(@cache[filename])

        if handler = findHandler(filename, routes)
          Promise.resolve(handler(filename, @))
            .then (result) ->
              console.log "cache save for", filename
              cache[filename] = result
            .catch (error) ->
              console.log "cache save for error", filename
              cache[filename] = error
              return Promise.reject(error)

        else
          console.log "Grump.get didn't resolve file", filename
          Promise.reject(new NotFoundError(filename))

    @fs = new GrumpFS(root, @)

    options = configFunc(@)
    routes = options.routes || {}

grump = new Grump "src", (grump) ->
  coffeeHandler = CoffeeHandler(grump)
  staticHandler = StaticHandler()
  routes:
    "**/*.js?bundle": BrowserifyHandler(grump)
    "**/*.js": AnyHandler(coffeeHandler, staticHandler)
    "**": staticHandler

logread = (err, data) ->
  if data and data.substring
    data = data.substring(0,200) + "..."

  console.log "logread: err =", err, "data =", data.length

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

# fs.readFile("grumpfz.coffee", encoding: "utf8", logread)
grump.fs.readFile "src/hello.js?bundle", encoding: "utf8", ->
  grump.fs.readFile("src/hello.js?bundle", encoding: "utf8", asyncBench("try 2x", logread))

module.exports = {AnyHandler, BrowserifyHandler, CoffeeHandler, StaticHandler, GrumpFS, Grump}
