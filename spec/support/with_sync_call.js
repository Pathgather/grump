fs = require("fs")

// a module that does some initialization and performs a *Sync call
module.exports = fs.readFileSync(__filename)
