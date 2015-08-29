# _ = require("underscore")
fs = require("fs")
path = require("path")
Sync = require('sync')
# stream = require("stream")
# colors = require('colors')

# NotFoundError = (filename) ->
#   errno: -2
#   code: "ENOENT"
#   path: filename

# ReturnTrue = -> true
# ReturnFalse = -> false

# FileStat = (result) ->
#   isFile: ReturnTrue
#   isDirectory: ReturnFalse
#   isFIFO: ReturnFalse
#   size: result.length

# DirStat = ->
#   isFile: ReturnFalse
#   isDirectory: ReturnTrue
#   isFIFO: ReturnFalse

startsWith = (str, needle) ->
  str.substring(0, needle.length) == needle

class GrumpFS
  constructor: (@_grump) ->

  _grumpGet: (filename, cb) ->
    onResult = (result) -> cb(null, result)

    @_grump.get(filename)
      .then(onResult, cb)

    return

  _isRooted: (filename) ->
    if not path.isAbsolute(filename) or filename.indexOf("../") >= 0
      absFilename = path.resolve(@_grump.root, filename)

    return startsWith(absFilename || filename, @_grump.root)

  _assertInFiber: ->
    if not Sync.Fibers.current
      throw new Error("GrumpFS: tried to use a *Sync function while not in a fiber")

    console.log "GrumpFS#_assertInFiber: running in a fiber id = ".cyan, Sync.Fibers.current.id

  exists: (filename, cb) =>
    if @_isRooted(filename)
      @_grump.get(filename)
        .then ->
          process.nextTick -> cb(null, true)
        .catch ->
          process.nextTick -> cb(null, false)
    else
      fs.exists(arguments...)

  existsSync: (filename) =>
    @_assertInFiber()
    @exists.sync(null, filename)

  readFile: (filename, cb) =>
    if @_isRooted(filename)
      @_grumpGet(filename, cb)
    else
      fs.readFile(arguments...)

  readFileSync: (filename) =>
    @_assertInFiber()
    @readFile.sync(null, filename)

# a helper class that wraps node's fs and simply logs all calls
GrumpFS.LoggingFS = Object.create(fs)

for func of fs
  if typeof fs[func] == "function"
    do (func) ->
      GrumpFS.LoggingFS[func] = ->
        console.log func.green, arguments[0]
        fs[func](arguments...)

# extend GrumpFS with the logging functions for the time being
for name, fn of GrumpFS.LoggingFS
  GrumpFS.prototype[name] ||= fn

# GrumpFS = (root, grump) ->
#   grumpfs = {
#     createReadStream: (filename, options) ->
#       console.log ("createReadStream " + filename).gray

#       st = new stream.Readable()
#       st._read = ->

#       grump.get(filename)
#         .then (result) ->
#           st.push(result)
#           st.push(null)
#         .catch (error) -> st.emit("error", error)

#       return st

#     readFile: (filename, options, callback) ->
#       console.log ("readFile " + filename).gray
#       if typeof options == "function"
#         callback = options
#         options = null

#       onResult = _.partial(callback, null, _)
#       onError = _.partial(callback, _, null)

#       grump.get(filename).then(onResult, onError)

#     realpath: (filename, cache, callback) ->
#       console.log ("realpath " + filename).gray

#       if typeof cache == "function"
#         callback = cache

#       if not path.isAbsolute(filename)
#         throw new Error("grump: unimplemented realpath #{filename}")

#       callback(null, filename)

#     stat: (filename, callback) ->
#       console.log ("stat " + filename).gray

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
#       console.log "grump.fs: passthrough".gray, func.gray, arguments...
#       return fs[func](arguments...)

#   for func of require("fs")
#     if not grumpfs[func]
#       grumpfs[func] = logArguments(func)

#   return grumpfs

module.exports = GrumpFS
