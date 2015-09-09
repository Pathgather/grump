chalk     = require("chalk")
detective = require("detective")
fs        = require("fs")
Module    = require("module")
Sync      = require("sync")

dep_cache = {}

usesFS = (id) ->
  'fs' in detective(fs.readFileSync(id))

# populate the dep cache by loading the module, parsing it and all of
# it's children to see if there are any require('fs') in them. if so,
# those are the deps we want to keep track of and re-load every time.
# return: true if id or any of it's children contain a require('fs')
usesRequireFS = (id, module) ->
  if dep_cache[id]
    return dep_cache[id].usesFS || dep_cache[id].length > 0

  module.require(id)

  dep_cache[id] = []
  dep_cache[id].usesFS = usesFS(id)

  for child in require.cache[id].children
    if usesRequireFS(child.id, module)
      dep_cache[id].push(child.id)

  return dep_cache[id].usesFS || dep_cache[id].length > 0

evictFromCache = (id) ->
  if dep_cache[id]
    for child_id in dep_cache[id]
      evictFromCache(child_id)

    delete require.cache[id]

module.exports = (name, module) ->

  if not module
    throw new Error("Grump.require: required module argument missing")

  # find the id of the require relative to the module
  # there is no module.require.resolve, so we resort to this hackery.
  id = Module._resolveFilename(name, module)

  if require.cache[id] and not dep_cache[id]
    throw new Error("Grump.require: #{id} already in cache!")

  # check if this or any of it's dependencies use require("fs")
  # if no, we can just return the entry from require.cache
  if not usesRequireFS(id, module)
    return require.cache[id].exports

  evictFromCache(id)

  require.cache.fs =
    id: "fs"
    exports: @fs

  # any *Sync calls during the require will wreak havoc on the little
  # prison we're building since the execution thread will be paused and
  # other code will run while the require.cache.fs is in effect.
  # the solution is to
  @_bypassSync(true)

  exports = module.require(name)

  delete require.cache.fs
  @_bypassSync(false)

  return exports
