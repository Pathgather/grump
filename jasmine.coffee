path = require("path")
Jasmine = require('jasmine')

jasmine = new Jasmine(projectBaseDir: path.resolve())

jasmine.loadConfigFile('spec/support/jasmine.json')
jasmine.execute()
