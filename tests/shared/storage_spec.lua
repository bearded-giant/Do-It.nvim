local doit_state = require("doit.state")
local storage = require("doit.state.storage")
local config = require("doit.config")
local mock_config = {
	options = {
		save_path = "/tmp/doit_test_todos.json",
	},
}

local original_io_open = io.open
local mock_file = {
	write = function(self, content)
		self.content = content
	end,
	read = function(self)
		return self.content
	end,
	close = function() end,
	content = "",
}

describe("storage", function()
	before_each(function()
		_G.io.open = function(path, mode)
			if mode == "r" and not mock_file.content then
				return nil -- Simulate file not found for reading
			end
			return mock_file
		end

		doit_state.todos = {}

		config.options = mock_config.options
	end)

	after_each(function()
		_G.io.open = original_io_open
		mock_file.content = ""
	end)

	it("should save todos to disk", function()
		doit_state.todos = {
			{ text = "Test todo", done = false, created_at = os.time() },
		}

		local original_json_encode = vim.fn.json_encode
		vim.fn.json_encode = function(data)
			return '{"text":"Test todo","done":false}'
		end

		doit_state.save_to_disk()

		assert.are.equal('{"text":"Test todo","done":false}', mock_file.content)

		vim.fn.json_encode = original_json_encode
	end)

	it("should load todos from disk", function()
		mock_file.content = '[{"text":"Loaded todo","done":false}]'

		local original_json_decode = vim.fn.json_decode
		vim.fn.json_decode = function(content)
			return { { text = "Loaded todo", done = false } }
		end

		doit_state.load_from_disk()

		assert.are.equal("Loaded todo", doit_state.todos[1].text)
		assert.are.equal(false, doit_state.todos[1].done)

		vim.fn.json_decode = original_json_decode
	end)

	it("should import todos from file", function()
		mock_file.content = '[{"text":"Imported todo","done":false}]'

		doit_state.todos = { { text = "Existing todo", done = false } }

		local original_json_decode = vim.fn.json_decode
		vim.fn.json_decode = function(content)
			return { { text = "Imported todo", done = false } }
		end

		doit_state.sort_todos = function() end

		local success, message = doit_state.import_todos("/path/to/import.json")

		assert.is_true(success)
		assert.are.equal(2, #doit_state.todos)
		assert.are.equal("Existing todo", doit_state.todos[1].text)
		assert.are.equal("Imported todo", doit_state.todos[2].text)

		vim.fn.json_decode = original_json_decode
	end)

	it("should export todos to file", function()
		doit_state.todos = {
			{ text = "Todo to export", done = false, created_at = os.time() },
		}

		local original_json_encode = vim.fn.json_encode
		vim.fn.json_encode = function(data)
			return '[{"text":"Todo to export","done":false}]'
		end

		local success, message = doit_state.export_todos("/path/to/export.json")

		assert.is_true(success)
		assert.are.equal('[{"text":"Todo to export","done":false}]', mock_file.content)

		vim.fn.json_encode = original_json_encode
	end)
end)
