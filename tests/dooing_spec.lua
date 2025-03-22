local doit = require("doit")

describe("doit", function()
	before_each(function() end)

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

	it("should load todos", function()
		if doit.state and doit.state.todos and doit.state.todos.get_todos then
			local todos = doit.state.todos.get_todos()
			assert.truthy(todos)
		else
			pending("get_todos function not found")
		end
	end)
end)
