local doit_state = require("doit.state")
local todos = require("doit.state.todos")
local config = require("doit.config")

describe("todos", function()
	before_each(function()
		doit_state.todos = {}
		doit_state.deleted_todos = {}
		doit_state.MAX_UNDO_HISTORY = 10
		doit_state.save_to_disk = function() end -- Mock save_to_disk

		_G._original_vim_notify = vim.notify
		vim.notify = function() end
	end)

	after_each(function()
		vim.notify = _G._original_vim_notify
	end)

	it("should add a todo", function()
		doit_state.add_todo("Test todo", {})

		assert.are.equal(1, #doit_state.todos)
		assert.are.equal("Test todo", doit_state.todos[1].text)
		assert.are.equal(false, doit_state.todos[1].done)
	end)

	it("should parse categories from tags", function()
		doit_state.add_todo("Test todo with #category tag", {})

		assert.are.equal("category", doit_state.todos[1].category)
	end)

	it("should toggle todo status correctly", function()
		doit_state.add_todo("Test todo", {})

		assert.are.equal(false, doit_state.todos[1].done)
		assert.are.equal(false, doit_state.todos[1].in_progress)

		doit_state.toggle_todo(1)
		assert.are.equal(false, doit_state.todos[1].done)
		assert.are.equal(true, doit_state.todos[1].in_progress)

		doit_state.toggle_todo(1)
		assert.are.equal(true, doit_state.todos[1].done)
		assert.are.equal(false, doit_state.todos[1].in_progress)

		doit_state.toggle_todo(1)
		assert.are.equal(false, doit_state.todos[1].done)
		assert.are.equal(false, doit_state.todos[1].in_progress)
	end)

	it("should delete a todo", function()
		doit_state.add_todo("Test todo", {})
		doit_state.delete_todo(1)

		assert.are.equal(0, #doit_state.todos)
		assert.are.equal(1, #doit_state.deleted_todos)
	end)

	it("should delete completed todos", function()
		doit_state.add_todo("Todo 1", {})
		doit_state.add_todo("Todo 2", {})
		doit_state.add_todo("Todo 3", {})

		doit_state.toggle_todo(2) -- Make it in_progress
		doit_state.toggle_todo(2) -- Make it done

		doit_state.delete_completed()

		assert.are.equal(2, #doit_state.todos)
		assert.are.equal("Todo 1", doit_state.todos[1].text)
		assert.are.equal("Todo 3", doit_state.todos[2].text)
	end)

	it("should undo deleted todos", function()
		doit_state.add_todo("Test todo", {})
		doit_state.delete_todo(1)

		assert.are.equal(0, #doit_state.todos)

		local result = doit_state.undo_delete()

		assert.is_true(result)
		assert.are.equal(1, #doit_state.todos)
		assert.are.equal("Test todo", doit_state.todos[1].text)
		assert.are.equal(0, #doit_state.deleted_todos)
	end)

	it("should limit undo history size", function()
		for i = 1, 15 do
			doit_state.add_todo("Todo " .. i, {})
		end

		for i = 15, 1, -1 do
			doit_state.delete_todo(i)
		end

		assert.are.equal(doit_state.MAX_UNDO_HISTORY, #doit_state.deleted_todos)
	end)

	it("should remove duplicates", function()
		local original_vim_inspect = vim.inspect
		vim.inspect = function(obj)
			return obj.text
		end

		local original_vim_fn_sha256 = vim.fn.sha256
		vim.fn.sha256 = function(str)
			return str
		end

		doit_state.add_todo("Duplicate todo", {})
		doit_state.add_todo("Unique todo", {})
		doit_state.add_todo("Duplicate todo", {})

		local removed = doit_state.remove_duplicates()

		assert.are.equal("1", removed) -- returns string
		assert.are.equal(2, #doit_state.todos)

		vim.inspect = original_vim_inspect
		vim.fn.sha256 = original_vim_fn_sha256
	end)
end)
