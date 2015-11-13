http  = require("http")
Grump = require("../lib/grump")
path  = require("path")

# use a random port in the upper 2^16 of the available range
random_port = Math.floor(Math.random() * 2**15) + 2**15

read_all = (res, callback) ->
  bufs = []
  res.on "data", (chunk) -> bufs.push(chunk)
  res.on "end", ->
    callback(Buffer.concat(bufs))

describe "Grump#serve", ->

  beforeEach ->
    jasmine.DEFAULT_TIMEOUT_INTERVAL = 200
    @grump = new Grump
      routes:
        "app.js": -> "some javascript"
        "style.css": -> "styles"
        "index.html": -> "index"
        "hello": -> new Buffer("binary data here!")
        "throws_error": -> throw new Error("big problem")
        "throws_in_sub": ({grump}) -> grump.get("throws_error")

    @server = @grump.serve(port: random_port)

    spyOn(console, "log").and.callFake ->
    spyOn(process.stdout, "write").and.callFake ->

  afterEach (done) ->
    @server.close(done)

  it "should call grunt with the filename", (done) ->
    http.get "http://localhost:#{random_port}/hello", (res) ->
      data = []
      expect(res.statusCode).toBe(200)
      read_all res, (buf) ->
        expect(buf.toString()).toBe("binary data here!")
        done()

  it "should return 404 for unhandled requests", (done) ->
    http.get "http://localhost:#{random_port}/does_not_exist", (res) ->
      expect(res.statusCode).toBe(404)
      done()

  it "should return 500 for errored requests", (done) ->
    http.get "http://localhost:#{random_port}/throws_error", (res) ->
      expect(res.statusCode).toBe(500)
      read_all res, (buf) ->
        expect(buf.toString()).toMatch(/big problem/)
        done()

  it "should return the name of the failed dep", (done) ->
    http.get "http://localhost:#{random_port}/throws_in_sub", (res) ->
      expect(res.statusCode).toBe(500)
      read_all res, (buf) ->
        expect(buf.toString()).toMatch(path.resolve("/throws_error"))
        expect(buf.toString()).toMatch("throws_error")
        done()

  it "should dump cache as json when called at __debug", (done) ->
    @grump.get("hello").then ->
      http.get "http://localhost:#{random_port}/__debug", (res) ->
        expect(res.statusCode).toBe(200)
        read_all res, (buf) ->
          # check that we return a valid JSON
          expect(-> JSON.parse(buf.toString())).not.toThrow()
          done()

  it "should request index.html when getting /", (done) ->
    http.get "http://localhost:#{random_port}/", (res) ->
      read_all res, (buf) ->
        expect(res.statusCode).toBe(200)
        expect(buf.toString()).toBe("index")
        done()

  describe "content-types", ->
    types = {
      "__debug": "application/json"
      "app.js": "application/javascript"
      "index.html": "application/html"
      "style.css": "text/css"
      "throws_error": "text/plain"
    }

    for filename of types
      do (filename) ->
        it "should be '#{types[filename]}' for '#{filename}'", (done) ->
          http.get "http://localhost:#{random_port}/#{filename}", (res) ->
            expect(res.headers['content-type']).toBe(types[filename])
            done()
