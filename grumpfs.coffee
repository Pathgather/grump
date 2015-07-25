_ = require("underscore")
fs = require("fs")
path = require("path")
minimatch = require("minimatch")
coffee = require("coffee-script")
proxyquire = require('proxyquire')
stream = require("stream")
concat = require('concat-stream')

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
  mdeps = proxyquire('browserify/node_modules/module-deps', fs: grump.fs)
  browserify = proxyquire("browserify",
    fs: grump.fs
    "module-deps": mdeps)

  return (file) ->
    file = file.replace(/\?bundle$/, "")

    new Promise (resolve, reject) ->
      output = concat (buf) -> resolve(buf)
      browserify(options)
        .on("error", -> console.log "error", arguments)
        .add(file)
        .bundle()
        .pipe(output)

NotFoundError = (filename) ->
  errno: -2
  code: "ENOENT"
  path: filename

Grump = (root, configFunc) ->
  root = fs.realpathSync(root)
  grump = @

  if typeof configFunc != "function"
    throw new Error("grump: missing config function")

  @get = (filename) ->
      console.log "grump: getting", filename

      if handler = findHandler(filename)
        Promise.resolve(handler(filename, this))
      else
        Promise.reject(new NotFoundError(filename))

  @fs = {
    createReadStream: (filename, options) ->
      console.log "createReadStream", filename, options

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
  }

  options = configFunc(@)

  routes = options.routes || {}

  findHandler = (filename) ->
    for route, handler of routes
      if minimatch(filename, route)
        console.log "route matched", route
        return handler

    return null

  return

grump = new Grump ".", (grump) ->
  routes:
    "**/*.js?bundle": BrowserifyHandler(grump)
    "*.js": CoffeeHandler(grump)
    "**": StaticHandler()

logread = (err, data) ->
  if data and data.substring
    data = data.substring(0,200) + "..."

  console.log "logread: err =", err, "data =", data.toString()

# fs.readFile("grumpfz.coffee", encoding: "utf8", logread)
grump.fs.readFile("src/hello.js?bundle", encoding: "utf8", logread)
