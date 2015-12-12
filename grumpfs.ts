"use strict"

import {Grump} from "./grump"
import * as fs from "fs"

// GrumpFS is a drop in replacement for Node's fs that uses Grump to get file contents
// for all files that are within Grump root.
export class GrumpFS {
  _grump: Grump

  constructor(grump: Grump) {
    this._grump = grump
  }

  readFile: typeof fs.readFile
  readFileSync: typeof fs.readFileSync
}

function ErrnoException(message: string, code: string, path: string): NodeJS.ErrnoException {
  let error: NodeJS.ErrnoException = new Error(message)
  error.code = code
  error.path = path
  error.syscall = "open"
  return error
}

// If given an encoding, return data in the string form, otherwise return Buffer
function encode(data: string | Buffer): Buffer
function encode(data: string | Buffer, encoding: string): string
function encode(data: string | Buffer, encoding?: string): any {
  if (encoding) {
    if (typeof data === "string") {
      // Just kind of assume the encoding is the correct one
      return data
    } else {
      return data.toString(encoding)
    }
  } else {
    if (typeof data === "string") {
      return new Buffer(data)
    } else {
      return data
    }
  }
}

let methods = {
  readFile(filename: string, opts_or_encoding_or_callback: any, callback?: (err: NodeJS.ErrnoException, data: string | Buffer) => void) {
    let encoding

    if (typeof opts_or_encoding_or_callback === "string") {
      encoding = opts_or_encoding_or_callback
    } else if (typeof opts_or_encoding_or_callback === "object") {
      encoding = opts_or_encoding_or_callback.encoding
    } else if (typeof opts_or_encoding_or_callback === "function") {
      callback = opts_or_encoding_or_callback
    }

    this._grump.get(filename, (error, result) => {
      if (error) {
        callback(ErrnoException(error.message || error, "ENOENT", filename), undefined)
      } else {
        callback(null, encode(result, encoding))
      }
    })
  },

  readFileSync(filename: string, opts_or_encoding: string | {encoding: string} ): string | Buffer {
    let encoding

    if (typeof opts_or_encoding === "object")
      encoding = opts_or_encoding.encoding
    else if (typeof opts_or_encoding === "string")
      encoding = opts_or_encoding

    try {
      var result = this._grump.getSync(filename)
    } catch (error) {
      throw ErrnoException(error.message, "ENOENT", filename)
    }

    return encode(result, encoding)
  }
}

for (let method_name in methods) {
  GrumpFS.prototype[method_name] = methods[method_name]
}
