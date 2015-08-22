beforeEach ->
  jasmine.addMatchers
    toBeEmpty: ->
      compare: (actual, expected) ->
        if typeof actual == "object" and actual != null
          pass: Object.keys(actual).length == 0
        else
          pass: false
          message: "Expected #{actual} to be an object"
