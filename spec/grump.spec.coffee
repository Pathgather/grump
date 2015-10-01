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

  describe "should assume that all patterns start with the root path", ->
    afterEach (done) ->
      delete options.routes["**"]
      grump = new Grump(options)
      grump.get("hello")
        .then ->
          expect(handler).toHaveBeenCalled()
          done()
        .catch(fail)

    it "when starting with name", ->
      options.routes["hello"] = handler

    it "when starting with *", ->
      options.routes["*"] = handler

    it "when starting with /", ->
      options.routes["/*"] = handler

  it "should accept handler as an object", (done) ->
    options.routes["**"] = {handler}
    new Grump(options).get("hello").then(done, fail)

  describe "with debug option", ->
    beforeEach ->
      spyOn(console, "log").and.callThrough()
      options.debug = true
      grump = new Grump(options)

    it "should log calls to get", (done) ->
      grump.get("hello").then ->
        expect(console.log).toHaveBeenCalled()
        done()

    it "should log calls to GrumpFS", (done) ->
      # try to read a file that's not in the grump root so we just
      # generate a log from grumpfs and not grump itself
      grump.fs.readFile "../../hello", ->
        expect(console.log).toHaveBeenCalled()
        done()

    it "should log calls to glob", (done) ->
      grump.glob("hel*").then ->
        expect(console.log).toHaveBeenCalled()
        done()

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

    describe "when used with tryStatic", ->
      beforeEach ->
        options.routes =
          "*.js":
            tryStatic: true
            filename: "$1.coffee"
            handler: handler

        grump = new Grump(options)

      it "should try filename with original filename", (done) ->
        expect(grump.get("hello.js")).toResolve done, ->
          expect(fakeFS.readFile).toHaveBeenCalledWith(path.resolve("hello.js"),
            jasmine.any(Object),
            jasmine.any(Function))
          expect(handler).toHaveBeenCalledWith(jasmine.objectContaining(filename: path.resolve("hello.coffee")))

  describe "filename", ->

    handledFilename = null

    routes =
      "/lib/*.{coffee,js}": "lib/$1.js?compile"
      "/*.bundle.js": "src/$1/index.js"
      "*.coffee": "$1.js"
      "src/**": "scripts/$1"
      "static/**/*.png": "$1/$2"

    tests =
      "lib/hello.js": "lib/hello.js?compile"
      "lib/hello.coffee": "lib/hello.js?compile"
      "hello.coffee": "hello.js"
      "grump.bundle.js": "src/grump/index.js"
      "src/hello": "scripts/hello"
      "src/hello/world": "scripts/hello/world"
      # "/static/womp.png": "/womp.png"
      "static/main/index.png": "main/index"
      "static/.tmp/hello.png": ".tmp/hello"

    beforeEach ->
      handledFilename = null
      handler = jasmine.createSpy("handler").and.callFake (ctx) ->
        handledFilename = ctx.filename

      options =
        minimatch: dot: true
        routes: {}

      for route, filename of routes
        options.routes[route] = {filename, handler}

      root = process.cwd()
      grump = new Grump(options)

    for reqFilename, expectedFilename of tests
      do (reqFilename, expectedFilename) ->
        it "should handle #{reqFilename}", (done) ->
          grump.get(reqFilename)
            .then ->
              expect(handledFilename).toBe(path.resolve(expectedFilename))
              done()
            .catch(fail)

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

  describe "dep()", ->
    it "should create an entry and it should just kind of work with the rest of Grump"

  describe "glob()", ->
    pathResolve = (files...) ->
      for file in files
        path.resolve(file)

    it "should match static filename patterns", (done) ->
      grump = new Grump
        routes:
          "images/hello.png": handler
          "hello.{js,coffee}": handler

      expect(grump.glob("**")).toResolveWith(pathResolve("images/hello.png", "hello.js", "hello.coffee"), done)

    it "should call glob to get file list", (done) ->
      imgSpy = jasmine.createSpy("image glob").and.callFake -> pathResolve("images/hello.png", "images/bye.bmp")
      scriptSpy = jasmine.createSpy("script glob").and.callFake -> Promise.resolve(pathResolve("scripts/hello.coffee", "scripts/bye.js"))
      grump = new Grump
        routes:
          "images/*":
            glob: imgSpy
            handler: handler
          "scripts/*":
            glob: scriptSpy
            handler: handler

      expect(grump.glob("**/hello.*")).toResolveWith(pathResolve("images/hello.png", "scripts/hello.coffee"), done)
      expect(imgSpy).toHaveBeenCalledWith(pathResolve("images/hello.*")...)
      expect(scriptSpy).toHaveBeenCalledWith(pathResolve("scripts/hello.*")...)

    it "should use filename to transform matches recursively", (done) ->
      grump = new Grump
        routes:
          "src/{a,b,c}.coffee": handler
          "app/*.{bundle,bundlez}":
            filename: "src/$1.coffee"
            handler: handler
          "*.js":
            filename: "app/$1.bundle"
            handler: handler

      expect(grump.glob("*.js")).toResolveWith(pathResolve("a.js", "b.js", "c.js"), done)

    xit "should blow up when filenames would cause infinite recursion", (done) ->
      grump = new Grump
        routes:
          "hello.coffee":
            handler: handler
          "*.coffee":
            filename: "$1.js"
            handler: handler
          "*.js":
            filename: "$1.coffee"
            handler: handler

      expect(grump.glob("*")).toReject done, (err) ->
        expect(err).toEqual(jasmine.any(Error))
        expect(err.message).toMatch(/filename patterns generated new files more than/)

    xit "should recursively intersect the glob when matching handler filenames", (done) ->
      grump = new Grump
        routes:
          "src/files/{a,b}.coffee": handler
          "**/*.js":
            filename: "$1/$2.coffee"
            handler: handler

      spyOn(grump, "glob").and.callThrough()

      expect(grump.glob("src/files/*.js")).toResolveWith(pathResolve("src/files/a.js", "src/files/b.js"), done)
      expect(grump.glob).toHaveBeenCalledWith(pathResolve("src/files/*.coffee")[0], jasmine.Any(Object))

    it "should use glob for tryStatic handlers", (done) ->
      glob = jasmine.createSpy("glob").and.callFake (pat, cb) ->
        cb(null, pathResolve('hello.coffee', 'bye.coffee'))

      Grump = proxyquire("../lib/grump", "./grump_glob": proxyquire("../lib/grump_glob", {glob}))
      grump = new Grump
        routes:
          "*.coffee": Grump.StaticHandler()
          "*.js":
            filename: "$1.coffee"
            handler: handler

      expect(grump.glob("*.js")).toResolve done, (files) ->
        expect(glob).toHaveBeenCalledWith(pathResolve("*.coffee")[0], jasmine.any(Function))
        expect(files).toEqual(pathResolve("hello.js", "bye.js"))
