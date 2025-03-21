local dooing = require("dooing")

describe("dooing", function()
	before_each(function()
		-- Setup code that runs before each test
	end)

	after_each(function()
		-- Cleanup code that runs after each test
	end)

	it("should properly initialize", function()
		assert.truthy(dooing)
	end)

	it("should have state module", function()
		assert.truthy(dooing.state)
	end)

	it("should have ui module", function()
		assert.truthy(dooing.ui)
	end)

	-- Test specific functionality
	it("should load todos", function()
		if dooing.state and dooing.state.todos and dooing.state.todos.get_todos then
			local todos = dooing.state.todos.get_todos()
			assert.truthy(todos)
		else
			-- Skip if the function doesn't exist
			pending("get_todos function not found")
		end
	end)
end)
