fs = require("fs")
prettyHrtime = require('pretty-hrtime')

_cache = {
  get: (filename) ->
    @[filename]
  save: (filename, src) ->
    @[filename] = src
}

benchFn = (n, fn) ->
  start = process.hrtime()

  N = n
  while n > 0
    fn()
    n -= 1

  total = process.hrtime(start)
  # console.log "total: ", prettyHrtime(total)
  console.log "per n: ", prettyHrtime(((t / N || 0) for t in total))

console.log "readFileSync with encoding"
benchFn 10, ->
  _cache.save(".tmp/scripts/login.app.js", fs.readFileSync(".tmp/scripts/login.app.js", encoding: "utf8"))

console.log "readFileSync"
benchFn 10, ->
  fs.readFileSync(".tmp/scripts/login.app.js")

console.log "statSync"
benchFn 10, ->
  fs.statSync(".tmp/scripts/login.app.js")

console.log "from cache"
benchFn 100000, ->
  _cache.get(".tmp/scripts/login.app.js")
