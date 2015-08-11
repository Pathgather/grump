fs = require("fs")

browserify = require("../node-browserify")

myFS = Object.create(fs)

for func in ["readFile", "realpath", "createReadStream"]
  do (func) ->
    myFS[func] = ->
      console.log func, ":", arguments
      return fs[func](arguments...)

b = browserify("src/hello.js", cache: {}, packageCache: {}, fs: myFS)

for evt in ["file", "package", "bundle", "dep"]
  do (evt) ->
    b.on evt, ->
      if evt == "file"
        console.log "::", evt, arguments[0]
      else
        console.log "::", evt

b.bundle().pipe(process.stdout)

# console.log "recorded", b._recorded
