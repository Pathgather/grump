fdescribe "Grump.fs", ->

  FS = ->
    realpathSync: -> arguments[0]

  fs = new FS()

  proxyquire = require("proxyquire")
  Grump = proxyquire("../lib/grump", fs: fs)

  beforeEach ->
    fs[prop] = val for prop, val of new FS()
    @fn = jasmine.createSpy("handler")
    @grump = new Grump
      root: "."
      routes:
        "**": @fn

  it "should be defined", ->
    expect(@grump.fs).toBeDefined()

  describe "readFile", ->
    it "should call handler", (done) ->
      @grump.fs.readFile "hello", (err, file) =>
        expect(@fn).toHaveBeenCalledWith(jasmine.stringMatching(/.*hello/), jasmine.any(Grump))
        done()

    it "should not call handler when file is not within the root", (done) ->
      @grump.fs.readFile "../hello", (err, file) =>
        expect(@fn).not.toHaveBeenCalled()
        done()
