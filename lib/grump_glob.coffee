_         = require("underscore")
chalk     = require("chalk")
glob      = require("glob")
intersect = require("glob-intersection")
minimatch = require("minimatch")
path      = require("path")

glob_helper = (pattern, routes, visited_patterns, debug) ->
  console.log chalk.yellow("running glob for #{pattern}"), {visited_patterns} if debug

  matcher = minimatch.filter(pattern)
  files = []

  if visited_patterns[pattern]
    return Promise.resolve(files)
  else
    visited_patterns[pattern] = true

  for route, handler of routes

    # static pattern matching is fast enough, so just add these to the result list
    if route.indexOf("*") == -1
      files.push(handler._expandedRoute)
    else

      intersected_pattern = intersect(pattern, route)
      console.log chalk[intersected_pattern && "green" || "gray"]("glob-intersect(#{route}): #{intersected_pattern}") if debug

      if intersected_pattern == false
        continue

      if handler.glob
        console.log "running handler.glob" if debug
        files.push(handler.glob(intersected_pattern))
      else
        if handler.tryStatic
          console.log "running fs.glob" if debug
          files.push new Promise (resolve, reject) ->
            glob intersected_pattern, (err, files) ->
              if err
                reject(err)
              else
                resolve(files)

        if handler.sources
          console.log "has sources option", handler.sources if debug

          do (handler) ->
            # do a recursive glob for sources that can generate filenames matching intersected_pattern
            files.push glob_helper(handler.sources.toSource(intersected_pattern), routes, visited_patterns, debug).then (files) ->
              return _.flatten((minimatch.braceExpand(handler.sources.toFilename(file)) for file in files))

  console.log require("util").inspect({files}, false, null, true) if debug

  Promise.all(files)
    .then(_.flatten)
    .then (files) ->
      _.uniq(files.filter(matcher))

module.exports = (pattern) ->
  glob_helper.call(@, path.join(@root, pattern), @routes, {}, @debug)
