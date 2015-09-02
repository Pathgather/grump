_     = require("underscore")
path  = require("path")
Grump = require("../lib/grump")
chalk = require("chalk")

describe "Grump", ->
  jasmine.DEFAULT_TIMEOUT_INTERVAL = 50

  getEntry = null

  beforeEach ->
    @handler = jasmine.createSpy("handler").and.callFake ({filename, grump}) ->
      switch path.basename(filename)
        when "hello"
          "contents"
        when "hello_as_dep"
          grump.get("hello").then (result) ->
            "dep: #{result}"
        when "hello_as_dep2"
          grump.get("hello").then (result) ->
            "dep2: #{result}"
        when "hello_as_dep_as_dep"
          grump.get("hello_as_dep").then (result) ->
            "dep: #{result}"

    @grump = new Grump
      root: "."
      routes:
        "**": @handler

    getEntry = (name) =>
      @grump.cache.get(path.resolve(name))

    expect(@grump.cache._cache).toBeEmpty()

  it "should cache an entry after a get", (done) ->
    @grump.get("hello").then (result) =>
      expect(@grump.cache._cache).not.toBeEmpty()
      entry = getEntry("hello")
      expect(entry.result).toBe(result)
      expect(entry.deps).toEqual({})
      done()

  it "should cache an entry with deps after a nested get", (done) ->
    @grump.get("hello_as_dep_as_dep")
      .then (result) ->
        entry = getEntry("hello_as_dep_as_dep")
        expect(entry.result).toBe(result)
        expect(entry.rejected).toBe(false)
        expect(entry.result).toBe("dep: dep: contents")
        expect(_.keys(entry.deps).length).toBe(1)
        entry2 = getEntry(_.keys(entry.deps)[0])
        expect(entry2.rejected).toBe(false)
        expect(entry2.result).toBe("dep: contents")
        expect(_.keys(entry2.deps).length).toBe(1)
        entry3 = getEntry(_.keys(entry2.deps)[0])
        expect(entry3.rejected).toBe(false)
        expect(entry3.result).toBe("contents")
        expect(_.keys(entry3.deps).length).toBe(0)
        done()
      .catch(fail)

  describe "when handler has an mtime function", ->
    beforeEach (done) ->
      @hello_at = new Date(Date.now() - 100)
      @hello_handler = jasmine.createSpy("hello handler").and.callFake -> "content that expires"
      @hello_handler.mtime = jasmine.createSpy("mtime").and.callFake => @hello_at

      @grump = new Grump
        root: "."
        routes:
          "**/hello": @hello_handler
          "**": @handler

      @expire_listener = jasmine.createSpy("expire listener")
      @grump.cache.on("expired", @expire_listener)

      @grump.get("hello")
        .then (result) =>
          @hello_handler.calls.reset()
          @entry = getEntry("hello")
          done()
        .catch(fail)

    it "cache entry should have the same 'mtime' function attached", ->
      expect(@entry.mtime).toBe(@hello_handler.mtime)

    it "cache entry should have an 'at' timestamp", ->
      expect(@entry.at).toBeDefined()
      expect(@entry.at > @hello_at).toBe(true)

    it "should call the mtime with filename", (done) ->
      @grump.get("hello")
        .then =>
          expect(@entry.mtime).toHaveBeenCalledWith(jasmine.stringMatching(/hello$/))
          done()
        .catch(fail)

    it "should serve the cached result", (done) ->
      @grump.get("hello")
        .then =>
          expect(@hello_handler).not.toHaveBeenCalled()
          done()

    describe "when entry.mtime returns a newer timestamp than entry.at", ->
      beforeEach ->
        @hello_handler.mtime.and.callFake => new Date(@entry.at.getTime() + 100)

      it "should call handler again", (done) ->
        @grump.get("hello")
          .then =>
            expect(@hello_handler).toHaveBeenCalled()
            done()

      it "should emit an 'expired' event on the cache", (done) ->
        @grump.get("hello")
          .then =>
            expect(@expire_listener).toHaveBeenCalled()
            done()

    describe "when entry is a dep of another cache entry", ->
      beforeEach (done) ->
        @grump.get("hello_as_dep")
          .then =>
            @grump.get("hello_as_dep2").then =>
              @handler.calls.reset()
              done()
          .catch(fail)

      it "should call handler when dep is expired", (done) ->
        @hello_handler.mtime.and.returnValue(new Date(@entry.at.getTime()))
        @grump.get("hello_as_dep").then =>
          @grump.get("hello_as_dep2")
            .then =>
              # both hello_as_dep entries should be expired due to the common dep being expired
              expect(@handler).toHaveBeenCalledWith(jasmine.objectContaining(filename: path.resolve("hello_as_dep"), grump: jasmine.any(Grump)))
              expect(@handler).toHaveBeenCalledWith(jasmine.objectContaining(filename: path.resolve("hello_as_dep2"), grump: jasmine.any(Grump)))
              done()
            .catch(fail)
