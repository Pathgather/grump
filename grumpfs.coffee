_ = require("underscore")
fs = require("fs")
path = require("path")
minimatch = require("minimatch")
coffee = require("coffee-script")
proxyquire = require('proxyquire')
stream = require("stream")
concat = require('concat-stream')

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

  return (file) ->
    file = file.replace(/\?bundle$/, "")

    new Promise (resolve, reject) ->
      output = concat (buf) -> resolve(buf)
      browserify(options)
        .on("error", -> console.log "browserify error", arguments)
        .add(file)
        .bundle()
        .pipe(output)

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
      console.log "createReadStream", filename

      st = new stream.Readable()
      st._read = ->

      grump.get(filename)
        .then (result) ->
          st.push(result)
          st.push(null)
        .catch (error) -> st.emit("error", error)

      return st

    readFile: (filename, options, callback) ->
      console.log "readFile", filename
      if typeof options == "function"
        callback = options
        options = null

      grump.get(filename)
        .then (result) -> callback(null, result)
        .catch (error) -> callback(error, null)

    realpath: (filename, cache, callback) ->
      console.log "realpath", filename

      if typeof cache == "function"
        callback = cache

      if not path.isAbsolute(filename)
        throw new Error("grump: unimplemented realpath #{filename}")

      callback(null, filename)

    stat: (filename, callback) ->
      console.log "stat", filename
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

    findHandler = (filename) ->
      for route, handler of routes
        if minimatch(filename, route)
          # console.log "route matched", route, "with", filename
          return handler

      return null

    @get = (filename) ->
        # console.log "grump: getting", filename
        if handler = findHandler(filename)
          Promise.resolve(handler(filename, this))
        else
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

# fs.readFile("grumpfz.coffee", encoding: "utf8", logread)
grump.fs.readFile("src/hello.js?bundle", encoding: "utf8", logread)
