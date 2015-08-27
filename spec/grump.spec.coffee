path  = require("path")
Grump = require("../lib/grump")

describe "Grump", ->
  jasmine.DEFAULT_TIMEOUT_INTERVAL = 50

  grump = null
  options = null
  handler = null

  beforeEach ->
    handler = jasmine.createSpy("handler").and.callFake ({filename, grump}) ->
      switch path.basename(filename)
        when "hello"
          "contents"
        when "hello_error"
          Promise.reject("my error")
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
          expect(error).toBe("my error")
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

    describe "deps", ->
      getEntry = (name) ->
        grump.cache.get(path.resolve(name))

      beforeEach ->
        expect(grump.cache._cache).toBeEmpty()

      it "should contain an entry after a get", (done) ->
        grump.get("hello").then (result) =>
          expect(grump.cache._cache).not.toBeEmpty()
          entry = getEntry("hello")
          expect(entry.result).toBe(result)
          expect(entry.deps).toEqual([])
          done()

      it "should contain an entry with deps after a nested get", (done) ->
        grump.get("hello_as_dep_as_dep")
          .then (result) ->
            entry = getEntry("hello_as_dep_as_dep")
            expect(entry.result).toBe(result)
            expect(entry.result).toBe("dep: dep: contents")
            expect(entry.deps.length).toBe(1)
            entry2 = getEntry(entry.deps[0])
            expect(entry2.result).toBe("dep: contents")
            expect(entry2.deps.length).toBe(1)
            entry3 = getEntry(entry2.deps[0])
            expect(entry3.result).toBe("contents")
            expect(entry3.deps.length).toBe(0)
            done()
          .catch(fail)
