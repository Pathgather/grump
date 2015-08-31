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
  return ({filename, grump}) ->
    idx = 0

    catchHandler = (error) ->
      if handlers[idx]
        result = handlers[idx]({filename, grump})
        Promise.resolve(result)
          .catch (error) ->
            idx += 1
            catchHandler(error)

      else
        Promise.reject(error)

    catchHandler()

CoffeeHandler = (options = {}) ->
  return ({filename, grump}) ->
    filename = filename.replace(/\.js(\?.*)?$/, ".coffee")
    grump.get(filename).then (source) ->
      coffee.compile(source, _.extend({}, options, {filename}))

GulpHandler = (options = {}) ->
  File = require("vinyl")
  stream = require("stream")

  if typeof options.transform != "function"
    throw new Error("GulpHandler: transform option to be a function that returns a transform stream")

  return (ctx) ->
    new Promise (resolve, reject) ->
      try
        if typeof options.files == "function"
          files = util.syncPromise(options.files(ctx))
        else if _.isArray(options.files)
          files = options.files
        else
          files = [ctx.filename]

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
        try
          hamlc.render(source)
        catch err
          if typeof err == "string"
            err = new Error(err)

          Promise.reject(err)

StaticHandler = ->
  fn = ({filename}) ->
    new Promise (resolve, reject) ->
      fs.readFile filename, {encoding: "utf8"}, (err, result) ->
        err && reject(err) || resolve(result)

  fn.mtime = (file) ->
    try fs.statSync(file).mtime

  return fn

BrowserifyHandler = (options = {}) ->
  options = _.extend {}, options,
    cache: {} # shared between all bundles
    fileCache: {}
    packageCache: {}

  expired = (key, entry) ->
    console.log "expired".red, key
    delete options.cache[key]

  return (ctx) ->
    if expired not in ctx.grump.cache.listeners("expired")
      ctx.grump.cache.on("expired", expired)

    new Promise (resolve, reject) ->

      if typeof options.files == "function"
        files = util.syncPromise(options.files(ctx))
      else if _.isArray(options.files)
        files = options.files
      else
        files = [ctx.filename]

      browserify = ctx.grump.require("browserify", module)
      bundle = browserify([], options)

      bundle.pipeline.get("deps").push through.obj (row, enc, next) ->
        file = row.expose && bundle._expose[row.id] || row.file
        options.cache[file] =
            source: row.source,
            deps: _.extend({}, row.deps)

        this.push(row)
        ctx.grump.dep(file) # save the dependency in grump
        next()

      bundle
        .add(files)
        .bundle (err, body) ->
          if err
            # try to extract the actual error from grump cache
            if match = err.message?.match(/Cannot find module '(.*?)' from '(.*?)'/)
              file = path.resolve(match[2], match[1])
              for ext in ["", "/", ".js", ".json", ".coffee", "/"]
                if entry = ctx.grump.cache.get(file + ext)
                  if entry.rejected and entry.result?.code != "ENOENT"
                    err.message += "\n\n" + (entry.result.stack || entry.result.message || entry.result)
                    break

          err && reject(err) || resolve(body)

module.exports = {AnyHandler, CoffeeHandler, GulpHandler, HamlHandler, StaticHandler, BrowserifyHandler}
