"use strict";
// GrumpFS is a drop in replacement for Node's fs that uses Grump to get file contents
// for all files that are within Grump root.
var GrumpFS = (function () {
    function GrumpFS(grump) {
        this._grump = grump;
    }
    return GrumpFS;
})();
exports.GrumpFS = GrumpFS;
function ErrnoException(message, code, path) {
    var error = new Error(message);
    error.code = code;
    error.path = path;
    error.syscall = "open";
    return error;
}
function encode(data, encoding) {
    if (encoding) {
        if (typeof data === "string") {
            // Just kind of assume the encoding is the correct one
            return data;
        }
        else {
            return data.toString(encoding);
        }
    }
    else {
        if (typeof data === "string") {
            return new Buffer(data);
        }
        else {
            return data;
        }
    }
}
var methods = {
    readFile: function (filename, opts_or_encoding_or_callback, callback) {
        var encoding;
        if (typeof opts_or_encoding_or_callback === "string") {
            encoding = opts_or_encoding_or_callback;
        }
        else if (typeof opts_or_encoding_or_callback === "object") {
            encoding = opts_or_encoding_or_callback.encoding;
        }
        else if (typeof opts_or_encoding_or_callback === "function") {
            callback = opts_or_encoding_or_callback;
        }
        this._grump.get(filename, function (error, result) {
            if (error) {
                callback(ErrnoException(error.message || error, "ENOENT", filename), undefined);
            }
            else {
                callback(null, encode(result, encoding));
            }
        });
    },
    readFileSync: function (filename, opts_or_encoding) {
        var encoding;
        if (typeof opts_or_encoding === "object")
            encoding = opts_or_encoding.encoding;
        else if (typeof opts_or_encoding === "string")
            encoding = opts_or_encoding;
        try {
            var result = this._grump.getSync(filename);
        }
        catch (error) {
            throw ErrnoException(error.message, "ENOENT", filename);
        }
        return encode(result, encoding);
    }
};
for (var method_name in methods) {
    GrumpFS.prototype[method_name] = methods[method_name];
}
//# sourceMappingURL=grumpfs.js.map