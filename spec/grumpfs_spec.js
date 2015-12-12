var grump_1 = require("../grump");
describe("GrumpFS", function () {
    var error = new Error("error");
    var grump;
    var fs;
    beforeEach(function () {
        grump = new grump_1.Grump({
            handlers: {
                "file": {
                    handler: function () { return "File contents"; }
                },
                "buffer": {
                    handler: function () { return new Buffer("File contents"); }
                },
                "error": {
                    handler: function () { throw error; return "naw"; }
                }
            }
        });
        fs = grump.fs;
    });
    describe("readFile", function () {
        it("should call handler", function (done) {
            fs.readFile("file", function (error, data) {
                expect(error).toBe(null);
                expect(data instanceof Buffer).toBe(true);
                expect(data.toString()).toBe("File contents");
                done();
            });
        });
        it("should call handler", function (done) {
            fs.readFile("file", "utf-8", function (error, data) {
                expect(error).toBe(null);
                expect(data).toBe("File contents");
                done();
            });
        });
        it("should call handler", function (done) {
            fs.readFile("file", { encoding: "utf-8" }, function (error, data) {
                expect(error).toBe(null);
                expect(data).toBe("File contents");
                done();
            });
        });
        it("should call handler", function (done) {
            fs.readFile("buffer", function (error, data) {
                expect(error).toBe(null);
                expect(data instanceof Buffer).toBe(true);
                expect(data.toString()).toBe("File contents");
                done();
            });
        });
        it("should call handler", function (done) {
            fs.readFile("buffer", "utf-8", function (error, data) {
                expect(error).toBe(null);
                expect(data).toBe("File contents");
                done();
            });
        });
        it("should call handler", function (done) {
            fs.readFile("buffer", { encoding: "utf-8" }, function (error, data) {
                expect(error).toBe(null);
                expect(data).toBe("File contents");
                done();
            });
        });
    });
    describe("readFileSync", function () {
        it("should call handler", function () {
            var data = fs.readFileSync("file");
            expect(data instanceof Buffer).toBe(true);
            expect(data.toString()).toBe("File contents");
        });
        it("should call handler", function () {
            var data = fs.readFileSync("file", "utf-8");
            expect(data).toBe("File contents");
        });
        it("should call handler", function () {
            var data = fs.readFileSync("file", { encoding: "utf-8" });
            expect(data).toBe("File contents");
        });
        it("should call handler", function () {
            var data = fs.readFileSync("buffer");
            expect(data instanceof Buffer).toBe(true);
            expect(data.toString()).toBe("File contents");
        });
        it("should call handler", function () {
            var data = fs.readFileSync("buffer", "utf-8");
            expect(data).toBe("File contents");
        });
        it("should call handler", function () {
            var data = fs.readFileSync("buffer", { encoding: "utf-8" });
            expect(data).toBe("File contents");
        });
    });
});
//# sourceMappingURL=grumpfs_spec.js.map