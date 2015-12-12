"use strict"

let deasync: (Function) => Function = require("deasync")

import * as fs from "fs"
import mm = require("micromatch")

import {GrumpFS} from "./grumpfs"

if (typeof Promise === "undefined")
  require('es6-promise').polyfill()

export class Grump {
  handlers: Handlers

  // Root of the Grump filesystem. Only paths starting with it will be processed
  root: string

  _fs: GrumpFS

  constructor(config: Config) {
    this.handlers = config.handlers
    this.root = fs.realpathSync(config.root || ".")
  }

  // Lazily initialize and return a new GrumpFS instance
  get fs() {
    if (!this.hasOwnProperty("_fs")) {
      this._fs = new GrumpFS(this)
    }
    return this._fs
  }

  get(filename: string): Promise<Content>
  get(filename: string, callback: ContentCallback)
  get(filename: string, _callback?: ContentCallback) {
    let callback = _callback

    process.nextTick(() => {
      let pattern = findMatchingPattern(filename, this.handlers)
      if (pattern) {
        try {
          var ret = this.handlers[pattern].handler({ filename })
        } catch (error) {
          return callback(error, undefined)
        }

        Promise.resolve(ret as Promise<Content>).then(content => {
          callback(null, content)
        }, error => {
          callback(error, undefined)
        }).catch(throwOnNext)


      } else {
        callback(new Error(`No handler matched: ${filename}`), null)
      }
    })

    // If a callback is not given, we return a promise that resolves/reject with
    // the value and update the callback local to make sure the code above runs ok.
    if (typeof callback === "undefined") {
      return new Promise((resolve, reject) => {
        callback = function(error, content) {
          if (error) {
            reject(error)
          } else {
            resolve(content)
          }
        }
      })
    }
  }

  // Synchronously return the file contents
  getSync(filename: string): Content {
    return deasync(this.get.bind(this))(filename)
  }
}

function findMatchingPattern(filename: string, handlers: Handlers): string {
  for (let pattern in handlers) {
    if (mm.isMatch(filename, pattern)) {
      return pattern
    }
  }
}

// Throw the argument on the next tick
function throwOnNext(error: any) {
  process.nextTick(function(){
    throw error
  })
}
