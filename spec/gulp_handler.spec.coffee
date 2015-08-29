Grump = require("../lib/grump")
GulpHandler = Grump.GulpHandler

describe "GulpHandler", ->
  jasmine.DEFAULT_TIMEOUT_INTERVAL = 50

  it "should be a function", ->
    expect(typeof GulpHandler).toBe("function")

  it "should expect transform option", ->
    expect(GulpHandler).toThrowError(/transform/)

  describe "with valid opts", ->
    transform = null
    handler   = null
    files     = null
    grump     = null

    beforeEach ->
      transform = jasmine.createSpy("transform")
      files     = jasmine.createSpy("files")
      @handler  = GulpHandler({transform, files})
      grump     = new Grump
        "**": @handler

    it "should return a function", ->
      expect(typeof @handler).toBe("function")
