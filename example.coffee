Grump = require("./grump")
handlers = require("./handlers")
angularTemplates = require('gulp-angular-templates')
util = require("./util")

grump = new Grump
  root: "./data"
  routes:
    "**/templates.js": Grump.GulpHandler
      files: ["data/hello.html"]
      transform: ->
        angularTemplates
          basePath: "/"
          module: "Pathgather"
    "**/*.js?bundle": Grump.BrowserifyHandler(grump)
    "**/*.js": Grump.AnyHandler(Grump.CoffeeHandler(), Grump.StaticHandler())
    "**/*.html": Grump.HamlHandler()
    "**": Grump.StaticHandler()

# grump.fs.readFile "src/hello.js?bundle", encoding: "utf8", (err, src) ->
#   if err
#     logError(err)
#   else
#     console.log "src length", src.length

#   grump.fs.readFile("src/hello.js?bundle", encoding: "utf8", asyncBench("try 2x", util.logRead))

# for i in [0...10]
#   grump.fs.readFile "src/hello.html", encoding: "utf8", ->

# setTimeout ->
#     grump.fs.readFile "src/hello.html", encoding: "utf8", ->
#   , 2000

grump.serve(port: 8080)

# grump.fs.readFile("data/hello.js?bundle", util.logRead)
# grump.fs.readFile("data/templates.js", util.logRead)
# fn = -> grump.fs.readFile("src/templates.js", asyncBench("fetcheroo", ->))
# setInterval(fn, 1000)

# grump.fs.readFile "src/templates.js", ->
#   util.logRead(arguments...)
#   console.log grump.cache