_         = require("underscore")
chalk     = require("chalk")
glob      = require("glob")
intersect = require("glob-intersection")
minimatch = require("minimatch")
path      = require("path")

debug = false

glob_helper = (pattern, routes, visited_patterns) ->
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
      console.log chalk.green("glob-intersect(#{route}): #{intersected_pattern}") if debug

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

        if handler._filenamePattern
          console.log "this has filename pattern", handler._filenamePattern, handler._filenamePatternRegexes, handler._reverseFilenames if debug

          do (handler) =>
            files.push glob_helper(handler._filenamePattern, routes, visited_patterns).then (files) ->
              newFiles = []

              for file in files
                for regex in handler._filenamePatternRegexes
                  if regex.test(file)
                    for replacement in handler._reverseFilenames
                      newFiles.push(file.replace(regex, replacement))
                    break

              return newFiles

  console.log require("util").inspect({files}, false, null, true) if debug

  Promise.all(files)
    .then(_.flatten)
    .then (files) ->
      _.uniq(files.filter(matcher))

module.exports = (pattern) ->
  glob_helper.call(@, path.join(@root, pattern), @routes, {})
