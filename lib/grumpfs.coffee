# _ = require("underscore")
chalk = require("chalk")
fs = require("fs")
path = require("path")
Sync = require('sync')
stream = require("stream")

NotFoundError = (filename) ->
  errno: -2
  code: "ENOENT"
  path: filename

False = -> false
True = -> true

FileStat = (result) ->
  isFile: True
  isDirectory: False
  isFIFO: False
  isSymbolicLink: False
  size: result.length

DirStat = ->
  isFile: False
  isDirectory: True
  isFIFO: False
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

  createReadStream: (filename, options) =>
    console.log chalk.gray("createReadStream"), arguments[0] if @_grump.debug
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
    console.log chalk.gray("exists"), arguments[0] if @_grump.debug
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

    console.log chalk.gray("existsSync"), arguments[0] if @_grump.debug
    @_assertInFiber()
    @exists.sync(null, filename)

  readdir: (filename, cb) =>
    console.log chalk.gray("readdir"), arguments[0] if @_grump.debug

    if @_isRooted(filename)
      relative = path.relative(@_grump.root, filename)
      @_grump.glob(path.join(relative, "*"))
        .then (files) ->
          process.nextTick -> cb(null, files.map( (file) -> path.basename(file)))
        .catch (err) ->
          process.nextTick -> cb(err)
    else
      fs.readdir(arguments...)

  readFile: (filename, options, cb) =>
    console.log chalk.gray("readFile"), arguments[0] if @_grump.debug

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

    console.log chalk.gray("readFileSync"), arguments[0] if @_grump.debug
    @_assertInFiber()
    @readFile.sync(null, filename, options)

  readlink: (filename, cb) =>
    console.log chalk.gray("readlink"), arguments[0] if @_grump.debug

    if @_isRooted(filename)
      onResult = (result) ->
        process.nextTick -> cb(errno: -22, code: "EINVAL", syscall: "readlink", path: filename)
      onError = (error) ->
        process.nextTick -> cb(error)

      @_grump.get(filename).then(onResult, onError)
    else
      fs.readlink(arguments...)

  realpath: (filename, cache, cb) =>
    console.log chalk.gray("realpath"), arguments[0] if @_grump.debug

    if @_isRooted(filename)
      if not path.isAbsolute(filename)
        throw new Error("GrumpFS: unimplemented relative realpath: #{filename}")

      process.nextTick -> (cb || cache)(null, filename)
    else
      fs.realpath(arguments...)

  stat: (filename, cb) =>
    console.log chalk.gray("stat"), arguments[0] if @_grump.debug

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

      return
    else
      fs.stat(arguments...)

  statSync: (filename) =>
    if @_grump.__bypassSync
      return GrumpFS.LoggingFS.statSync(arguments...)

    console.log chalk.gray("statSync"), arguments[0] if @_grump.debug
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

module.exports = GrumpFS
