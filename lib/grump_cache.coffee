_ = require("underscore")

module.exports = class GrumpCache
  constructor: -> @_cache = {}
  get: (key) -> @_cache[key]
  init: (key) -> @_cache[key] = {id: key, deps: [], result: null, rejected: null}

  # an entry is current (not stale) if:
  # a) all deps are in cache and current
  # b) it has an at prop AND mtime prop and mtime() is less than at
  isCurrent: (key, expire = true) =>
    entry = @get(key)
    return false if not entry

    deps_current = _.map(entry.deps, @isCurrent)
    return false if not _.every(deps_current)

    if entry.mtime
      mtime = entry.mtime(key)

      if not entry.at?
        throw new Error("GrumpCache: possibly pending file tested for isCurrent: #{key}")

      if mtime? and entry.at > mtime
        return true
      else
        if expire
          @_cache[key] = undefined
        return false
    else
      return true
