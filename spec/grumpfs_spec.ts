import {Grump} from "../grump"
import {GrumpFS} from "../grumpfs"

describe("GrumpFS", () => {
  const error = new Error("error")

  let grump: Grump
  let fs: GrumpFS

  beforeEach(() => {
    grump = new Grump({
      handlers: {
        "file": {
          handler() { return "File contents" }
        },
        "buffer": {
          handler() { return new Buffer("File contents") }
        },
        "error": {
          handler() { throw error; return "naw" }
        }
      }
    })

    fs = grump.fs
  })

  describe("readFile", () => {
    it("should call handler", (done) => {
      fs.readFile("file", (error, data) => {
        expect(error).toBe(null)
        expect(data instanceof Buffer).toBe(true)
        expect(data.toString()).toBe("File contents")
        done()
      })
    })

    it("should call handler", (done) => {
      fs.readFile("file", "utf-8", (error, data) => {
        expect(error).toBe(null)
        expect(data).toBe("File contents")
        done()
      })
    })

    it("should call handler", (done) => {
      fs.readFile("file", { encoding: "utf-8" }, (error, data) => {
        expect(error).toBe(null)
        expect(data).toBe("File contents")
        done()
      })
    })

    it("should call handler", (done) => {
      fs.readFile("buffer", (error, data) => {
        expect(error).toBe(null)
        expect(data instanceof Buffer).toBe(true)
        expect(data.toString()).toBe("File contents")
        done()
      })
    })

    it("should call handler", (done) => {
      fs.readFile("buffer", "utf-8", (error, data) => {
        expect(error).toBe(null)
        expect(data).toBe("File contents")
        done()
      })
    })

    it("should call handler", (done) => {
      fs.readFile("buffer", { encoding: "utf-8" }, (error, data) => {
        expect(error).toBe(null)
        expect(data).toBe("File contents")
        done()
      })
    })
  })

  describe("readFileSync", () => {
    it("should call handler", () => {
      let data = fs.readFileSync("file")
      expect(data instanceof Buffer).toBe(true)
      expect(data.toString()).toBe("File contents")
    })

    it("should call handler", () => {
      let data = fs.readFileSync("file", "utf-8")
      expect(data).toBe("File contents")
    })

    it("should call handler", () => {
      let data = fs.readFileSync("file", { encoding: "utf-8" })
      expect(data).toBe("File contents")
    })

    it("should call handler", () => {
      let data = fs.readFileSync("buffer")
      expect(data instanceof Buffer).toBe(true)
      expect(data.toString()).toBe("File contents")
    })

    it("should call handler", () => {
      let data = fs.readFileSync("buffer", "utf-8")
      expect(data).toBe("File contents")
    })

    it("should call handler", () => {
      let data = fs.readFileSync("buffer", { encoding: "utf-8" })
      expect(data).toBe("File contents")
    })
  })
})
