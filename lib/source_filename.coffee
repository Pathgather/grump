intersect = require("glob-intersection")
path = require("path")

normalize = (filename) ->
  if filename.indexOf("//") >= 0
    path.normalize(filename)
  else
    filename

# replace takes a filename (pattern) that matches pattern and a replacement string that has $1,$2,.. replacement groups
# and return a new filename (pattern) where
replace = (filename, pattern, replacement) ->
  intersect(pattern, filename, capture: [].push.bind(captured = []))

  # replace $1,$2.. in replacement with captured fragments
  return normalize replacement.replace /\$(\d+)/g, (pat, idx) =>
    frag = captured[parseInt(idx) - 1]

    if typeof frag != "string"
      throw new Error("'#{pat}' in '#{replacement}' has no matching glob in '#{pattern}' when matching '#{filename}': captures = #{JSON.stringify(captured)}")

    return frag

makePattern = (route, filename) ->
  globs = route.match(/(\*+)/g)
  filename.replace /\$\d+/g, (match) ->
    globs[parseInt(match.slice(1)) - 1]

makeReversePattern = (route, filename) ->
  submatches = filename.match(/\$\d+/g)
  i = 0
  route.replace /\*+/g, (match) ->
    submatches[i++]

# a helper class to translate filenames when using the sources option
module.exports = class SourceFilename
  constructor: (@route, @source) ->
    @sourcePattern = makePattern(@route, @source)
    @routeReverse = makeReversePattern(@route, @source)

  toSource: (filename) ->
    replace(filename, @route, @source)

  # convert source back to request filename
  toFilename: (source) ->
    replace(source, @sourcePattern, @routeReverse)
