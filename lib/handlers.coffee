_       = require("underscore")
chalk   = require("chalk")
fs      = require("fs")
path    = require("path")
concat  = require('concat-stream')
coffee  = require("coffee-script")
through = require('through2')
util    = require("./util")
Sync    = require("sync")

CoffeeHandler = (options = {}) ->
  return ({filename, grump}) ->
    filename = filename.replace(/\.js(\?.*)?$/, ".coffee")
    grump.get(filename).then (source) ->
      coffee.compile(source.toString(), _.extend({}, options, {filename}))

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
          hamlc.render(source.toString())
        catch err
          if typeof err == "string"
            err = new Error(err)

          Promise.reject(err)

StaticHandler = ->
  tryStatic: true
  handler: (ctx) ->
    # we only run if tryStatic fails above, which means there's no file
    err = new Error("ENOENT, no such file or directory '#{ctx.filename}'")
    _.extend err,
      code: "ENOENT"
      errno: -2
      path: ctx.filename
    throw err

BrowserifyHandler = (options = {}) ->
  options = _.extend {}, options,
    cache: {} # shared between all bundles
    fileCache: {}
    packageCache: {}

  expired = (key, entry) ->
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
        console.log chalk.magenta("bundle.pipeline.deps"), file
        ctx.grump.dep(file) # save the dependency in grump
        next()

      bundle.on "package", (pkg) ->
        file = path.join(pkg.__dirname, 'package.json')
        console.log chalk.magenta("bundle.package"), file
        ctx.grump.dep(file)
        options.packageCache[file] = pkg

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

          if err then reject(err) else resolve(body)

module.exports = {CoffeeHandler, GulpHandler, HamlHandler, StaticHandler, BrowserifyHandler}
