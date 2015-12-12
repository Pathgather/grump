var grump_1 = require("../grump");
// Create a new instance of Grump with a single handler
var setup = function (handler) {
    return new grump_1.Grump({
        handlers: {
            "*": { handler: handler }
        }
    });
};
// Return a Callback function that asserts on error and content and calls done when done
var assert = function (err, content, done) {
    return function (_err, _content) {
        expect(_err).toBe(err);
        expect(_content).toBe(content);
        done();
    };
};
describe("Grump handlers", function () {
    var error = new Error("Error");
    var handlers = [
        function (ctx) { return "Content"; },
        function (ctx) {
            throw error;
            return "Not it.";
        },
        function (ctx) { return Promise.resolve("Content"); },
        function (ctx) { return Promise.reject(error); }
    ];
    var results = [
        [null, "Content"],
        [error, undefined],
        [null, "Content"],
        [error, undefined]
    ];
    for (var i = handlers.length - 1; i >= 0; i--) {
        (function (handler, result) {
            it("should resolve correctly using Grump#get", function (done) {
                setup(handler).get("file", function (error, content) {
                    expect(error).toBe(result[0]);
                    expect(content).toBe(result[1]);
                    done();
                });
            });
        })(handlers[i], results[i]);
    }
    for (var i = handlers.length - 1; i >= 0; i--) {
        (function (handler, result) {
            it("should resolve correctly using Grump#get as a promise", function (done) {
                setup(handler).get("file").then(function (content) {
                    expect(content).toBe(result[1]);
                    done();
                }, function (error) {
                    expect(error).toBe(result[0]);
                    done();
                });
            });
        })(handlers[i], results[i]);
    }
    for (var i = handlers.length - 1; i >= 0; i--) {
        (function (handler, result) {
            it("should resolve correctly using Grump#getSync", function () {
                var error = null;
                try {
                    var content = setup(handler).getSync("file");
                }
                catch (err) {
                    var error = err;
                }
                expect(error).toBe(result[0]);
                expect(content).toBe(result[1]);
            });
        })(handlers[i], results[i]);
    }
});
//# sourceMappingURL=handler_spec.js.map