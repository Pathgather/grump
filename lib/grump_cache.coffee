_      = require("underscore")
chalk  = require("chalk")
events = require("events")

debug = false

module.exports = class GrumpCache extends events.EventEmitter
  constructor: ->
    super
    @_cache = {}
  get: (key) -> @_cache[key]
  init: (key) -> @_cache[key] = {id: key, deps: {}, result: null, rejected: null}

  _expire: (key, entry) ->
    delete @_cache[key]
    @emit("expired", key, entry)
    console.log chalk.cyan("expired"), key if debug
    return false

  # an entry is current (not stale) if:
  # a) all deps are in cache and current
  # b) it is older than it's parent
  # c) it has an at prop AND mtime prop and mtime() is less than at
  current: (key, parent_at = null) =>
    entry = @get(key)
    return false if not entry

    if parent_at and entry.at > parent_at
      return false # expire the parent, not this entry

    deps_current = _.map _.keys(entry.deps), (dep) =>
      @current(dep, entry.at)

    if not _.every(deps_current)
      return @_expire(key, entry)

    if entry.mtime
      mtime = entry.mtime(key)

      if not entry.at?
        throw new Error("GrumpCache: possibly pending file tested for current: #{key}")

      if mtime? and entry.at >= mtime
        return true
      else if not mtime? and entry._static_error
        return true
      else
        return @_expire(key, entry)
    else
      return true
