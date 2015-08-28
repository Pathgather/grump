detective = require("detective")
fs        = require("fs")
Module    = require("module")

dep_cache = {}

usesFS = (id) ->
  'fs' in detective(fs.readFileSync(id))

# populate the dep cache by loading the module, parsing it and all of
# it's children to see if there are any require('fs') in them. if so,
# those are the deps we want to keep track of and re-load every time.
# return: true if id or any of it's children contain a require('fs')
usesRequireFS = (id) ->
  if dep_cache[id]
    return dep_cache[id].usesFS || dep_cache[id].length > 0

  require(id)

  dep_cache[id] = []
  dep_cache[id].usesFS = usesFS(id)

  for child in require.cache[id].children
    if usesRequireFS(child.id)
      dep_cache[id].push(child.id)

  return dep_cache[id].usesFS || dep_cache[id].length > 0

evictFromCache = (id) ->
  if dep_cache[id]
    for child_id in dep_cache[id]
      evictFromCache(child_id)

    delete require.cache[id]

module.exports = (name, module) ->

  if not module
    throw new Error("Grump#require: required module argument missing")

  # find the id of the require relative to the module
  # there is no module.require.resolve, so we resort to this hackery.
  id = Module._resolveFilename(name, module)

  # check if this or any of it's dependencies use require("fs")
  # if no, we can just return the entry from require.cache
  if not usesRequireFS(id)
    return require.cache[id].exports

  evictFromCache(id)

  require.cache.fs =
    id: "fs"
    exports: @fs()

  ret = module.require(name)
  delete require.cache.fs
  return ret
