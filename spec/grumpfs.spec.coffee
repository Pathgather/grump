Sync       = require("sync")

inSync = (fail, fn) ->
  Sync ->
    try
      fn()
    catch error
      fail(error)

files =
  "hello": -> Promise.resolve("contents")
  "hello_error": -> Promise.reject("my error")
  "../hello": (cb) -> cb(null, "contents")
  "../hello_error": (cb) -> cb("my error")

describe "Grump.fs", ->
  proxyquire = require("proxyquire")
  path       = require("path")

  jasmine.DEFAULT_TIMEOUT_INTERVAL = 50

  fs = null
  fakefs = null
  grump = null

  beforeEach ->
    fakefs =
      readFile: jasmine.createSpy("readFile").and.callFake (filename, cb) -> files[filename](cb)

    grump =
      root: path.resolve()
      get: jasmine.createSpy("get").and.callFake (filename) -> files[filename]()

    GrumpFS = proxyquire("../lib/grumpfs", "fs": fakefs)
    fs = new GrumpFS(grump)

  describe "readFile", ->
    afterEach ->
      expect(@ret).toBeUndefined()

    it "should call handler", (done) ->
      @ret = fs.readFile "hello", (err, file) ->
        expect(grump.get).toHaveBeenCalledWith("hello")
        done()

    it "should call handler with error", (done) ->
      @ret = fs.readFile "hello_error", (err, file) ->
        expect(err).toBe("my error")
        done()

    describe "with filename outside root", ->
      it "should not call handler", (done) ->
        @ret = fs.readFile "../hello", (err, file) ->
          expect(grump.get).not.toHaveBeenCalled()
          done()

      it "should call fs.readFile", (done) ->
        @ret = fs.readFile "../hello", (err, file) ->
          expect(fakefs.readFile).toHaveBeenCalledWith("../hello", jasmine.any(Function))
          done()

      it "should call fs.readFile and return contents", (done) ->
        @ret = fs.readFile "../hello", (err, file) ->
          expect(file).toBe("contents")
          expect(err).toBeFalsy()
          done()

      it "should call handler with an error", (done) ->
        @ret = fs.readFile "../hello_error", (err, file) ->
          expect(err).toBe("my error")
          expect(file).toBeFalsy()
          done()

    pending "should re-throw errors from the callback", ->

  describe "readFileSync", ->
    it "should throw an error when called outside Sync()", ->
      fn = -> fs.readFileSync("hello")
      expect(fn).toThrowError(/no fiber/)

    it "should return contents", (done) ->
      inSync fail, ->
        expect(fs.readFileSync("hello")).toBe("contents")
        done()

    it "should throw an error", (done) ->
      inSync fail, ->
        fn = -> fs.readFileSync("hello_error")
        expect(fn).toThrow()
        done()

    describe "with filename outside root", ->
      it "should return contents", (done) ->
        inSync fail, ->
          expect(fs.readFileSync("../hello")).toBe("contents")
          done()

      it "should throw an error", (done) ->
        inSync fail, ->
          fn = -> fs.readFileSync("../hello_error")
          expect(fn).toThrow()
          done()