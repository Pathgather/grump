path = require("path");

// require with an expression that can be statically analyzed.
module.exports = require(path.join(path.dirname(__filename), "hello_dep"));
