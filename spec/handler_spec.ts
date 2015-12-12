import {Grump} from "../grump"

// Create a new instance of Grump with a single handler
let setup = function(handler: Handler): Grump {
  return new Grump({
    handlers: {
      "*": { handler }
    }
  })
}

// Return a Callback function that asserts on error and content and calls done when done
let assert = function(err: Error, content: Content, done: Function): ContentCallback {
  return function(_err, _content) {
    expect(_err).toBe(err)
    expect(_content).toBe(content)
    done()
  }
}

describe("Grump handlers", () => {
  let error = new Error("Error")

  let handlers = [
    ctx => "Content",
    ctx => {
      throw error
      return "Not it."
    },
    ctx => Promise.resolve("Content"),
    ctx => Promise.reject(error)
  ]

  let results = [
    [null, "Content"],
    [error, undefined],
    [null, "Content"],
    [error, undefined]
  ]

  for (var i = handlers.length - 1; i >= 0; i--) {
    (function(handler, result){
      it("should resolve correctly using Grump#get", (done) => {
        setup(handler).get("file", (error, content) => {
          expect(error).toBe(result[0])
          expect(content).toBe(result[1])
          done()
        })
      })
    })(handlers[i], results[i])
  }

  for (var i = handlers.length - 1; i >= 0; i--) {
    (function(handler, result){
      it("should resolve correctly using Grump#get as a promise", (done) => {
        setup(handler).get("file").then(content => {
          expect(content).toBe(result[1])
          done()
        }, error => {
          expect(error).toBe(result[0])
          done()
        })
      })
    })(handlers[i], results[i])
  }

  for (var i = handlers.length - 1; i >= 0; i--) {
    (function(handler, result){
      it("should resolve correctly using Grump#getSync", () => {
        var error = null
        try {
          var content = setup(handler).getSync("file")
        } catch (err) {
          var error = err
        }

        expect(error).toBe(result[0])
        expect(content).toBe(result[1])
      })
    })(handlers[i], results[i])
  }
})
