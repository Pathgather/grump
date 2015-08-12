Grump = require("./grump")
handlers = require("./handlers")
angularTemplates = require('gulp-angular-templates')
prettyHrtime = require('pretty-hrtime')
colors = require('colors')

grump = new Grump
  root: "./data"
  routes:
    "**/templates.js": handlers.GulpHandler
      files: ["data/hello.html"]
      transform: ->
        angularTemplates
          basePath: "/"
          module: "Pathgather"
    "**/*.js?bundle": handlers.BrowserifyHandler(grump)
    "**/*.js": handlers.AnyHandler(handlers.CoffeeHandler(), handlers.StaticHandler())
    "**/*.html": handlers.HamlHandler()
    "**": handlers.StaticHandler()

logRead = (err, src) ->
  if err
    logError(err)
  else
    console.log "src", src.toString().substring(0,100).gray

asyncBench = (message = "", fn) ->
  start = process.hrtime()
  return ->
    done = process.hrtime(start)
    fn(arguments...)
    console.log message, "time", prettyHrtime(done).white

syncBench = (message = "", fn) ->
  start = process.hrtime()
  result = fn()
  done = process.hrtime(start)
  console.log message, "time", prettyHrtime(done).white
  return result

logError = (error) ->
  if error.stack
    console.log "error".red, error.stack
  else
    console.log "error".red, error.toString().substring(0,100)

# grump.fs.readFile "src/hello.js?bundle", encoding: "utf8", (err, src) ->
#   if err
#     logError(err)
#   else
#     console.log "src length", src.length

#   grump.fs.readFile("src/hello.js?bundle", encoding: "utf8", asyncBench("try 2x", logRead))

# for i in [0...10]
#   grump.fs.readFile "src/hello.html", encoding: "utf8", ->

# setTimeout ->
#     grump.fs.readFile "src/hello.html", encoding: "utf8", ->
#   , 2000
grump.fs.readFile("data/hello.js?bundle", logRead)
# grump.fs.readFile("data/templates.js", logRead)
# fn = -> grump.fs.readFile("src/templates.js", asyncBench("fetcheroo", ->))
# setInterval(fn, 1000)

# grump.fs.readFile "src/templates.js", ->
#   logRead(arguments...)
#   console.log grump.cache
