chalk = require("chalk")
prettyHrtime = require('pretty-hrtime')

logRead = (err, src) ->
  if err
    logError(err)
  else
    console.log "src", src.toString().substring(0,100)

asyncBench = (message = "", fn) ->
  start = process.hrtime()
  return ->
    done = process.hrtime(start)
    fn(arguments...)
    console.log message, "time", prettyHrtime(done)

syncBench = (message = "", fn) ->
  start = process.hrtime()
  result = fn()
  done = process.hrtime(start)
  console.log message, "time", prettyHrtime(done)
  return result

logError = (error) ->
  console.log chalk.red("ERROR"), (error.stack || error).toString()

# convert a promise to a sync call using node-sync. must be called inside a Fiber
syncPromise = (maybePromise) ->
  handle = (cb) ->
    ok = (result) ->
      process.nextTick ->
        cb(null, result)

    fail = (err) ->
      process.nextTick ->
        cb(err)

    Promise.resolve(maybePromise).then(ok, fail)

  handle.sync(null)

module.exports = {logRead, logError, syncBench, syncPromise, asyncBench}
