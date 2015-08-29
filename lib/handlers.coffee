_       = require("underscore")
fs      = require("fs")
path    = require("path")
concat  = require('concat-stream')
coffee  = require("coffee-script")
through = require('through2')
util    = require("./util")
Sync    = require("sync")

# run all handlers until one of them resolves to a value
AnyHandler = (handlers...) ->
  return ({file, grump}) ->
    idx = 0

    catchHandler = (error) ->
      if handlers[idx]
        result = handlers[idx]({file, grump})
        Promise.resolve(result)
          .catch (error) ->
            idx += 1
            catchHandler(error)

      else
        Promise.reject(error)

    catchHandler()

CoffeeHandler = (options = {}) ->
  return ({file, grump}) ->
    file = file.replace(/\.js$/, ".coffee")
    grump.get(file).then (source) ->
      coffee.compile(source, options)

GulpHandler = (options = {}) ->
  File = require("vinyl")
  stream = require("stream")

  if typeof options.transform != "function"
    throw new Error("GulpHandler: transform option to be a function that returns a transform stream")

  return (ctx) ->
    new Promise (resolve, reject) ->
      Sync ->
        try
          if typeof options.files == "function"
            files = util.syncPromise(options.files(ctx))
          else if _.isArray(options.files)
            files = options.files
          else
            throw new Error("GulpHandler: missing files option")

          transform = util.syncPromise(options.transform(ctx))
          transform.on("error", reject)

          pipe_in = new stream.Readable(objectMode: true)
          pipe_in._read = ->

          pipe_in
            .pipe(transform)
            .pipe concat (files) ->
              # join all vinyl files together to resolve the promise
              buffers = files.map (file) -> file.contents
              resolve(Buffer.concat(buffers).toString())

          for filename in files
            result = ctx.grump.getSync(filename)

            file = new File
              base: options.base
              path: filename
              contents: new Buffer(result)

            pipe_in.push(file)

          # we're done
          pipe_in.push(null)

        catch err
          reject(err)


HamlHandler = (options = {}) ->
  hamlc = require('haml-coffee')
  return ({filename, grump}) ->
    htmlfile = filename.replace(".html", ".haml")
    grump.get(htmlfile)
      .then (source) ->
        hamlc.render(source)

StaticHandler = ->
  fn = ({filename}) ->
    new Promise (resolve, reject) ->
      fs.readFile filename, {encoding: "utf8"}, (err, result) ->
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

  return ({filename, grump}) ->

    initBrowserify(grump)

    console.log "bundle requested for", filename
    count += 1
    filename = filename.replace(/\?bundle$/, "")

    options.cache = cache
    options.fileCache = fileCache
    options.packageCache = packageCache

    bundle = browserify([], _.extend(options, basedir: path.dirname(filename)))

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
        .add(filename)
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
