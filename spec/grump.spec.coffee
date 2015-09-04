path       = require("path")
proxyquire = require("proxyquire")

describe "Grump", ->
  jasmine.DEFAULT_TIMEOUT_INTERVAL = 50

  Grump   = null
  grump   = null
  options = null
  handler = null

  beforeEach ->
    Grump = require("../lib/grump")

    handler = jasmine.createSpy("handler").and.callFake ({filename, grump}) ->
      switch path.basename(filename)
        when "hello"
          "contents"
        when "hello_error"
          Promise.reject(message: "my error")
        when "hello_error_as_dep"
          grump.get("hello_error")
        when "hello_as_dep"
          grump.get("hello").then (result) ->
            "dep: #{result}"
        when "hello_as_dep_as_dep"
          grump.get("hello_as_dep").then (result) ->
            "dep: #{result}"

    options =
      root: "."
      routes:
        "**": handler

    grump = new Grump(options)

  it "should be a function", ->
    expect(typeof Grump).toBe("function")

  it "should return grump instance", ->
    expect(Grump(options)).toEqual(jasmine.any(Grump))

  it "with new should return grump instance", ->
    expect(new Grump(options)).toEqual(jasmine.any(Grump))

  it "should initialize without any options", ->
    expect(-> new Grump()).not.toThrow()

  it "should assume that all patterns start with the root path", (done) ->
    delete options.routes["**"]
    options.routes["*"] = handler
    grump = new Grump(options)
    console.log grump.routes
    grump.get("hello")
      .then ->
        expect(handler).toHaveBeenCalled()
        done()
      .catch(fail)

  it "should accept handler as an object", (done) ->
    options.routes["**"] = {handler}
    new Grump(options).get("hello").then(done, fail)

  describe "tryStatic", ->
    fakeFS = null

    beforeEach ->
      fakeFS =
        readFile: jasmine.createSpy("readFile").and.callFake ->
          arguments[2](new Error("couldn't be read"))

      Grump = proxyquire("../lib/grump", fs: fakeFS)

    describe "when 'true'", ->
      beforeEach ->
        options.routes["**"] =
          handler: handler
          tryStatic: true

        grump = new Grump(options)

      it "when true should try to read the file", (done) ->
        grump.get("hello")
          .then ->
            expect(fakeFS.readFile).toHaveBeenCalledWith(
              path.resolve("hello"),
              jasmine.any(Object),
              jasmine.any(Function))
            expect(handler).toHaveBeenCalled()
            done()
          .catch(fail)

      it "when true should not call handler if the read succeeds", (done) ->
        fakeFS.readFile.and.callFake ->
          arguments[2](null, "some content")

        grump.get("hello")
          .then ->
            expect(handler).not.toHaveBeenCalled()
            done()
          .catch(fail)

      it "should add a mtime function to the cache_entry", (done) ->
        fakeFS.readFile.and.callFake ->
          arguments[2](null, "some content")

        grump.get("hello")
          .then ->
            entry = grump.cache.get(path.resolve("hello"))
            expect(entry).toBeDefined()
            done()
          .catch(fail)

    describe "when 'after'", ->
      beforeEach ->
        options.routes["**"] =
          handler: handler
          tryStatic: "after"

        grump = new Grump(options)

      it "should not try to read file if the handler succeeds", (done) ->
        grump.get("hello")
          .then ->
            expect(fakeFS.readFile).not.toHaveBeenCalled()
            done()
          .catch(fail)

      it "should try to read file if the handler fails", (done) ->
        handler.and.callFake -> throw "problem"
        fakeFS.readFile.and.callFake ->  arguments[2](null, "some static content")
        grump.get("hello")
          .then (result) ->
            expect(fakeFS.readFile).toHaveBeenCalled()
            expect(result).toBe("some static content")
            done()
          .catch(fail)

      it "should return the handler error if file read fails", (done) ->
        problem = new Error("problem")
        handler.and.callFake -> throw problem
        fakeFS.readFile.and.callFake ->  arguments[2](new Error("no file or something"))
        grump.get("hello")
          .then fail, (error) ->
            expect(error).toBe(problem)
            done()

  describe "get()", ->
    beforeEach ->
      grump = new Grump(options)

    it "should call the handler", (done) ->
      grump.get("hello")
        .then (result) ->
          expect(handler).toHaveBeenCalledWith({filename: path.resolve("hello"), grump: jasmine.any(Grump)})
          done()
        .catch(fail)

    it "should return the contents", (done) ->
      grump.get("hello")
        .then (result) ->
          expect(result).toBe("contents")
          done()

    it "should cache the handler return value", (done) ->
      grump.get("hello").then ->
        grump.get("hello")
          .then ->
            expect(handler.calls.count()).toBe(1)
            done()

    it "should reject when there's an error", (done) ->
      grump.get("hello_error")
        .catch (error) ->
          expect(error).toEqual(jasmine.objectContaining(message: "my error"))
          done()

    it "should cache the handler error", (done) ->
      grump.get("hello_error").catch ->
        process.nextTick ->
          grump.get("hello_error")
            .catch ->
              expect(handler.calls.count()).toBe(1)
              done()

    it "should return same promise if a request is pending", ->
      promise  = grump.get("hello")
      promise2 = grump.get("hello")
      expect(promise).toBe(promise2)

    it "should decorate the error with the filename", (done) ->
      grump.get("hello_error_as_dep")
        .then(fail)
        .catch (err) ->
          file = err._grump_filename
          expect(file).toBeDefined()
          expect(path.basename(file)).toBe("hello_error")
          done()
