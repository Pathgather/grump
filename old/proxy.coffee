proxyquire = require('proxyquire')

# a = require("./a")
# a.hello()

a = proxyquire("./a", {
  "fs": {
    stat: -> console.log "hacked!"
    "@global": true
  }
})

a.hello()
