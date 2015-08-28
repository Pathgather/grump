fs = require("fs")

module.exports = {
  fs: fs,
  reverse: function(filename, cb) {
    fs.readFile(filename, function(err, result) {
      if (err) {
        cb(err)
      } else {
        cb(null, result.toString().split(/\B/).reverse().join(""))
      };
    });
  },
  Hello: require("./hello_dep_dep")
}
