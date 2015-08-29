Grump       = require("../lib/grump")
GulpHandler = Grump.GulpHandler
stream      = require("stream")
path        = require("path")

describe "GulpHandler", ->
  jasmine.DEFAULT_TIMEOUT_INTERVAL = 50

  it "should be a function", ->
    expect(typeof GulpHandler).toBe("function")

  it "should expect transform option", ->
    expect(GulpHandler).toThrowError(/transform/)

  describe "with valid opts", ->
    beforeEach ->
      @transform    = jasmine.createSpy("transform").and.callFake -> new stream.PassThrough(objectMode: true)
      @files        = jasmine.createSpy("files").and.returnValue(["A", "B", "C"])
      @handler      = jasmine.createSpy("handler").and.callFake ({filename}) -> "(" + path.basename(filename) + ".contents)"
      @gulp_handler = GulpHandler(transform: @transform, files: @files, base: "base_dir")
      @grump        = new Grump
        routes:
          "**/gulp": @gulp_handler
          "**": @handler

    it "should return a function", ->
      expect(typeof @gulp_handler).toBe("function")

    it "should resolve", (done) ->
      @grump.get("gulp").then(done, fail)

    it "should concat all contents from files", (done) ->
      @grump.get("gulp")
        .then (result) =>
          expect(result).toBe("(A.contents)(B.contents)(C.contents)")
          done()
        .catch(fail)

    it "should call files() and transform()", (done) ->
      ctx = jasmine.objectContaining
        grump: jasmine.any(Grump)
        filename: path.resolve("gulp")

      @grump.get("gulp")
        .then (result) =>
          expect(@files).toHaveBeenCalledWith(ctx)
          expect(@transform).toHaveBeenCalledWith(ctx)
          done()
        .catch(fail)

    it "should set base on Vinyl files passed to transform", (done) ->
      tr = new stream.PassThrough(objectMode: true)
      spyOn(tr, "push").and.callThrough()
      @transform.and.returnValue(tr)

      @grump.get("gulp")
        .then ->
          expect(tr.push).toHaveBeenCalled()
          calls = tr.push.calls.allArgs()

          expect(calls.length).toBe(4)
          expect(calls.pop()).toEqual([null]) # last call is a null to signal the end of the stream

          for call in calls
            expect(call[0].base).toBe("base_dir")

          done()
        .catch(fail)

    it "should accept a promise from files() and transform()", (done) ->
      @transform.and.callFake -> Promise.resolve(new stream.PassThrough(objectMode: true))
      @files.and.callFake -> Promise.resolve(["A", "B", "C"])
      @grump.get("gulp").then(done, fail)

    it "should reject with the first error on the transform", (done) ->
      i = 0
      @transform.and.callFake ->
        tr = new stream.PassThrough(objectMode: true)
        tr.push = -> tr.emit("error", {CODE: "trouble in paradise", i: ++i})
        tr

      @grump.get("gulp")
        .then(fail)
        .catch (err) ->
          expect(err).toEqual({CODE: "trouble in paradise", i: 1})
          done()
