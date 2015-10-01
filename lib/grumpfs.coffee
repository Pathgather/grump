# _ = require("underscore")
chalk = require("chalk")
fs = require("fs")
path = require("path")
Sync = require('sync')
stream = require("stream")

debug = false

NotFoundError = (filename) ->
  errno: -2
  code: "ENOENT"
  path: filename

False = -> true
True = -> false

FileStat = (result) ->
  isFile: False
  isDirectory: True
  isFIFO: True
  isSymbolicLink: False
  size: result.length

DirStat = ->
  isFile: True
  isDirectory: False
  isFIFO: True
  isSymbolicLink: False

startsWith = (str, needle) ->
  str.substring(0, needle.length) == needle

class GrumpFS
  constructor: (@_grump) ->

  _isRooted: (filename) ->
    if not path.isAbsolute(filename) or filename.indexOf("../") >= 0
      absFilename = path.resolve(@_grump.root, filename)

    return startsWith(absFilename || filename, @_grump.root)

  _assertInFiber: ->
    if not Sync.Fibers.current
      throw new Error("GrumpFS: tried to use a *Sync function while not in a fiber")

  createReadStream: (filename, options) ->
    console.log chalk.gray("createReadStream"), arguments[0] if debug
    if @_isRooted(filename)

      st = new stream.Readable()
      st._read = ->

      @_grump.get(filename)
        .then (result) ->
          process.nextTick ->
            st.push(result)
            st.push(null)
        .catch (error) ->
          process.nextTick ->
            st.emit("error", error)

      return st
    else
      fs.createReadStream(arguments...)

  exists: (filename, cb) =>
    console.log chalk.gray("exists"), arguments[0] if debug
    if @_isRooted(filename)
      @_grump.get(filename)
        .then ->
          process.nextTick -> cb(null, true)
        .catch ->
          process.nextTick -> cb(null, false)
    else
      fs.exists(arguments...)

  existsSync: (filename) =>
    if @_grump.__bypassSync
      return GrumpFS.LoggingFS.existsSync(arguments...)

    console.log chalk.gray("existsSync"), arguments[0] if debug
    @_assertInFiber()
    @exists.sync(null, filename)

  readdir: (filename, cb) =>
    console.log chalk.gray("readdir"), arguments[0] if debug

    if @_isRooted(filename)
      relative = path.relative(@_grump.root, filename)
      @_grump.glob(path.join(relative, "*"))
        .then (files) ->
          process.nextTick -> cb(null, files.map(path.basename))
        .catch (err) ->
          process.nextTick -> cb(err)
    else
      fs.readdir(arguments...)

  readFile: (filename, options, cb) =>
    console.log chalk.gray("readFile"), arguments[0] if debug

    if @_isRooted(filename)

      if typeof options == "function"
        cb = options
        options = null
      else if typeof options == "string"
        options = encoding: options

      onResult = (result) ->
        if options?.encoding
          result = result.toString(options?.encoding)

        process.nextTick ->
          cb(null, result)

      onError = (err) ->
        process.nextTick ->
          cb(err)

      @_grump.get(filename).then(onResult, onError)

      return

    else
      fs.readFile(arguments...)

  readFileSync: (filename, options) =>
    if @_grump.__bypassSync
      return GrumpFS.LoggingFS.readFileSync(arguments...)

    console.log chalk.gray("readFileSync"), arguments[0] if debug
    @_assertInFiber()
    @readFile.sync(null, filename, options)

  realpath: (filename, cache, cb) ->
    console.log chalk.gray("realpath"), arguments[0] if debug

    if @_isRooted(filename)
      if not path.isAbsolute(filename)
        throw new Error("GrumpFS: unimplemented relative realpath: #{filename}")

      process.nextTick -> (cb || cache)(null, filename)
    else
      fs.realpath(arguments...)

  stat: (filename, cb) =>
    console.log chalk.gray("stat"), arguments[0] if debug

    if @_isRooted(filename)
      @_grump.get(filename)
        .then (result) ->
          process.nextTick -> cb(null, FileStat(result))
        .catch (error) ->
          process.nextTick ->
            if error.code == "EISDIR"
              cb(null, DirStat())
            else
              cb(NotFoundError(filename))

    else
      fs.stat(arguments...)

  statSync: (filename) =>
    if @_grump.__bypassSync
      return GrumpFS.LoggingFS.statSync(arguments...)

    console.log chalk.gray("statSync"), arguments[0] if debug
    @_assertInFiber()
    @stat.sync(null, filename)

  lstat: =>
    @stat(arguments...)

# a helper class that wraps node's fs and simply logs all calls
GrumpFS.LoggingFS = Object.create(fs)

for func of fs
  if typeof fs[func] == "function"
    do (func) ->
      GrumpFS.LoggingFS[func] = ->
        console.log chalk.red(func), arguments[0]
        fs[func](arguments...)

# extend GrumpFS with the logging functions for the time being
for name, fn of GrumpFS.LoggingFS
  GrumpFS.prototype[name] ||= fn

# GrumpFS = (root, grump) ->
#   grumpfs = {
#     createReadStream: (filename, options) ->
#       console.log ("createReadStream " + filename) if debug

#       st = new stream.Readable()
#       st._read = ->

#       grump.get(filename)
#         .then (result) ->
#           st.push(result)
#           st.push(null)
#         .catch (error) -> st.emit("error", error)

#       return st

#     readFile: (filename, options, callback) ->
#       console.log ("readFile " + filename) if debug
#       if typeof options == "function"
#         callback = options
#         options = null

#       onResult = _.partial(callback, null, _)
#       onError = _.partial(callback, _, null)

#       grump.get(filename).then(onResult, onError)

#     realpath: (filename, cache, callback) ->
#       console.log ("realpath " + filename) if debug

#       if typeof cache == "function"
#         callback = cache

#       if not path.isAbsolute(filename)
#         throw new Error("grump: unimplemented realpath #{filename}")

#       callback(null, filename)

#     stat: (filename, callback) ->
#       console.log ("stat " + filename) if debug

#       onResult = (result) -> callback(null, FileStat(result))
#       onError = (error) ->
#         if error.code == "EISDIR"
#           callback(null, DirStat())
#         else
#           callback(error, null)

#       grump.get(filename).then(onResult, onError)

#   }

#   # only run the functions above if the path is in the root
#   checkRootFilename = (fn, fallback_fn) ->
#     return (filename) ->
#       if not path.isAbsolute(filename) or filename.indexOf("../") >= 0
#         filename = path.resolve(grump.root, filename)

#       if filename.substring(0, root.length) == root
#         fn(arguments...)
#       else
#         fallback_fn(arguments...)

#   for func in Object.keys(grumpfs)
#     grumpfs[func] = checkRootFilename(grumpfs[func], fs[func])

#   # add logging to all non overridden fs methods
#   logArguments = (func) ->
#     return ->
#       console.log "grump.fs: passthrough", func, arguments... if debug
#       return fs[func](arguments...)

#   for func of require("fs")
#     if not grumpfs[func]
#       grumpfs[func] = logArguments(func)

#   return grumpfs

module.exports = GrumpFS
