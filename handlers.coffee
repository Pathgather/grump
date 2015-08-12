_ = require("underscore")
fs = require("fs")
path = require("path")
concat = require('concat-stream')
coffee = require("coffee-script")
through = require('through2')

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
    require.cache["fs"] = { id: "fs", exports: grump.fs }
    browserify = require("browserify")
    delete require.cache.fs

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

    bundle = browserify([], _.extend(options, basedir: path.dirname(targetFile)))

    new Promise (resolve, reject) ->

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

          if count == 2

            console.log "cache", cache
            console.log "fileCache", fileCache
            console.log "packageCache", packageCache

          if err
            reject(err)
          else
            resolve(body.toString())

module.exports = {AnyHandler, CoffeeHandler, GulpHandler, HamlHandler, StaticHandler, BrowserifyHandler}
