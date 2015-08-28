Grump = require("../lib/grump")

describe "Grump#serve", ->
  jasmine.DEFAULT_TIMEOUT_INTERVAL = 50

  grump = null

  beforeEach ->
    grump = new Grump()

  it "should be a function", ->
    expect(typeof grump.serve).toBe("function")


