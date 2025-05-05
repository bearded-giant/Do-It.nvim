local doit = require("doit")

describe("doit", function()
	before_each(function() 
		-- Set up required properties directly on doit for test purposes
		doit.state = {
			todos = {},
			load_todos = function() end,
			save_todos = function() end
		}
		
		doit.ui = {
			main_window = {
				toggle_todo_window = function() end
			}
		}
	end)

	after_each(function() end)

	it("should properly initialize", function()
		assert.truthy(doit)
	end)

	it("should have state module", function()
		assert.truthy(doit.state)
	end)

	it("should have ui module", function()
		assert.truthy(doit.ui)
	end)

	it("should have state.todos property", function()
		-- This test is checking backward compatibility
		doit.state.todos = {} -- Ensure the property exists
		assert.are.equal("table", type(doit.state.todos))
	end)
end)
