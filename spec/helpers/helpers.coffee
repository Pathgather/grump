assertIsPromise = (promise) ->
  if not (typeof promise?.then == "function")
    throw new Error("Expected argument to be a promise, but was #{jasmine.pp(promise)}")

assertIsDone = (done) ->
  if not (typeof done == "function" and typeof done.fail == "function")
    throw new Error("Expected argument to be a done method, but was #{jasmine.pp(done)}")

isStandardError = (err) ->
  for type in [ReferenceError, SyntaxError, TypeError]
    if err instanceof type
      return true

  return false

promiseMatchers =
  toResolve: ->
    compare: (promise, done, fn) ->

      assertIsPromise(promise)
      assertIsDone(done)

      toResolve = (value) ->
        process.nextTick ->
          fn(value) if fn
          done()

      promise.then toResolve, (err) ->
        if isStandardError(err)
          done.fail(err)
        else
          done.fail("Expected promise to resolve with value, but it rejected with #{jasmine.pp(err)}")

      pass: true

  toReject: (util) ->
    compare: (promise, done, fn) ->

      assertIsPromise(promise)
      assertIsDone(done)

      toReject = (value) ->
        done.fail("Expected promise to reject, but it resolved with #{jasmine.pp(value)}")

      promise.then toReject, (err) ->
        process.nextTick ->
          fn(err) if fn
          done()

      pass: true

  toResolveWith: (util) ->
    compare: (promise, expected, done) ->

      toResolveWith = (value) ->
        if util.equals(value, expected)
          done()
        else
          done.fail("Expected promise to resolve with #{jasmine.pp(expected)}, but it resolved with #{jasmine.pp(value)}")

      promiseMatchers.toResolve().compare(promise, done, toResolveWith)

  toRejectWith: (util) ->
    compare: (promise, expected, done) ->

      toRejectWith = (value) ->
        if util.equals(value, expected)
          done()
        else
          done.fail("Expected promise to reject with #{jasmine.pp(expected)}, but it rejected with #{jasmine.pp(value)}")

      promiseMatchers.toReject().compare(promise, done, toRejectWith)

beforeEach ->
  jasmine.addMatchers(promiseMatchers)
  jasmine.addMatchers
    toBeEmpty: ->
      compare: (actual, expected) ->
        if typeof actual == "object" and actual != null
          pass: Object.keys(actual).length == 0
        else
          pass: false
          message: "Expected #{actual} to be an object"
