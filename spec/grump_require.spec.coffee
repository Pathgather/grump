fs = require("fs")

describe "Grump#require", ->
  jasmine.DEFAULT_TIMEOUT_INTERVAL = 50

  Grump   = null
  GrumpFS = null
  grump   = null

  beforeAll ->
    # store current state of require.cache so we can reset it after every spec run
    # this is to ensure that all spec runs are independent and nothing is cached
    @prev_req_ids = {}
    @prev_req_ids[id] = true for id of require.cache

    # we also want to reload Grump#require and Grump since there's some global state there
    for dep in ["../lib/grump_require", "../lib/grumpfs", "../lib/grump"]
      id = require.resolve(dep)
      delete @prev_req_ids[id]

  afterEach ->
    # restore require.cache to what is was before
    for id of require.cache
      if not @prev_req_ids[id]
        delete require.cache[id]

  beforeEach ->
    Grump   = require("../lib/grump")
    GrumpFS = require("../lib/grumpfs")
    grump   = new Grump()

  it "should be a function", ->
    expect(typeof grump.require).toBe("function")

  it "should throw if not given two arguments", ->
    expect(-> grump.require("underscore")).toThrowError(/required/)

  it "should return an exported object", ->
    expect(typeof grump.require("underscore", module)).toBe("function")

  it "should return the same object as local require", ->
    hello  = require("./support/hello.json")
    hello2 = grump.require("./support/hello.json", module)

    expect(hello).toEqual(hello2)

  it "should handle already cached shared dependencies", ->
    hello_dep = require("./support/hello_dep")
    hello = grump.require("./support/hello.js", module)
    expect(hello.dep).not.toBe(hello_dep)

  it "should require files with nonstandard extensions", ->
    hello = grump.require("./support/i_like", module)
    expect(hello.message).toBe("hello")

  it "should handle files with requires that will fail at runtime", ->
    value = grump.require("./support/failed_require", module)
    expect(value).toBe("s'all good")

  xit "should handle requires with static expressions", ->
    hello_dep = grump.require("./support/static_exp", module)
    expect(hello_dep.fs).toBe(grump.fs)

  it "should return GrumpFS from require('fs') inside required files", ->
    hello = grump.require("./support/hello.js", module)
    expect(hello.dep.fs instanceof GrumpFS).toBe(true)
    expect(hello.dep.fs._grump).toBe(grump)

  it "should bind separate GrumpFS instances", ->
    hello  = grump.require("./support/hello.js", module)
    hello2 = new Grump().require("./support/hello.js", module)

    expect(hello.dep.fs._grump).not.toBe(hello2.dep.fs._grump)

  it "shouldn't reload dependencies that don't require('fs')", ->
    hello  = grump.require("./support/hello.js", module)
    hello2 = new Grump().require("./support/hello.js", module)

    expect(hello.dep.Hello).toBe(hello2.dep.Hello)

  it "should route all fs calls to grump.get", (done) ->
    handler = jasmine.createSpy("handler").and.returnValue("content")
    grump = new Grump
      routes:
        "**": handler

    hello = grump.require("./support/hello", module)
    hello.dep.reverse "my_file", (err, result) ->
      expect(err).toBe(null)
      expect(handler).toHaveBeenCalled()
      expect(result).toBe("tnetnoc")
      done()

  describe "when requiring a file that does Sync calls", ->
    it "should bypass grump", ->
      src = null
      handler = jasmine.createSpy("handler").and.returnValue("content")
      grump = new Grump
        routes:
          "**": handler

      fn = -> src = grump.require("./support/with_sync_call", module)
      expect(fn).not.toThrow()
      expect(src).toEqual(fs.readFileSync("./spec/support/with_sync_call.js"))
