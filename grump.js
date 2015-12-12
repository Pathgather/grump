"use strict";
var deasync = require("deasync");
var fs = require("fs");
var mm = require("micromatch");
var grumpfs_1 = require("./grumpfs");
if (typeof Promise === "undefined")
    require('es6-promise').polyfill();
var Grump = (function () {
    function Grump(config) {
        this.handlers = config.handlers;
        this.root = fs.realpathSync(config.root || ".");
    }
    Object.defineProperty(Grump.prototype, "fs", {
        // Lazily initialize and return a new GrumpFS instance
        get: function () {
            if (!this.hasOwnProperty("_fs")) {
                this._fs = new grumpfs_1.GrumpFS(this);
            }
            return this._fs;
        },
        enumerable: true,
        configurable: true
    });
    Grump.prototype.get = function (filename, _callback) {
        var _this = this;
        var callback = _callback;
        process.nextTick(function () {
            var pattern = findMatchingPattern(filename, _this.handlers);
            if (pattern) {
                try {
                    var ret = _this.handlers[pattern].handler({ filename: filename });
                }
                catch (error) {
                    return callback(error, undefined);
                }
                Promise.resolve(ret).then(function (content) {
                    callback(null, content);
                }, function (error) {
                    callback(error, undefined);
                }).catch(throwOnNext);
            }
            else {
                callback(new Error("No handler matched: " + filename), null);
            }
        });
        // If a callback is not given, we return a promise that resolves/reject with
        // the value and update the callback local to make sure the code above runs ok.
        if (typeof callback === "undefined") {
            return new Promise(function (resolve, reject) {
                callback = function (error, content) {
                    if (error) {
                        reject(error);
                    }
                    else {
                        resolve(content);
                    }
                };
            });
        }
    };
    // Synchronously return the file contents
    Grump.prototype.getSync = function (filename) {
        return deasync(this.get.bind(this))(filename);
    };
    return Grump;
})();
exports.Grump = Grump;
function findMatchingPattern(filename, handlers) {
    for (var pattern in handlers) {
        if (mm.isMatch(filename, pattern)) {
            return pattern;
        }
    }
}
// Throw the argument on the next tick
function throwOnNext(error) {
    process.nextTick(function () {
        throw error;
    });
}
//# sourceMappingURL=grump.js.map