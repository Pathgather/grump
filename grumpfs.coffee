_ = require("underscore")
fs = require("fs")
path = require("path")
stream = require("stream")
colors = require('colors')

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
      console.log "grump.fs: passthrough".gray, func.gray, arguments...
      return fs[func](arguments...)

  for func of require("fs")
    if not grumpfs[func]
      grumpfs[func] = logArguments(func)

  return grumpfs

module.exports = GrumpFS
