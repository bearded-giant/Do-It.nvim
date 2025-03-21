local dooing = require("dooing")

describe("dooing", function()
	before_each(function() end)

	after_each(function() end)

	it("should properly initialize", function()
		assert.truthy(dooing)
	end)

	it("should have state module", function()
		assert.truthy(dooing.state)
	end)

	it("should have ui module", function()
		assert.truthy(dooing.ui)
	end)

	it("should load todos", function()
		if dooing.state and dooing.state.todos and dooing.state.todos.get_todos then
			local todos = dooing.state.todos.get_todos()
			assert.truthy(todos)
		else
			pending("get_todos function not found")
		end
	end)
end)
