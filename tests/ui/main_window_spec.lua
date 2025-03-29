local main_window = require("doit.ui.main_window")
local doit_state = require("doit.state")
local config = require("doit.config")

describe("main_window", function()
	before_each(function()
		_G._original_vim_api_nvim_create_buf = vim.api.nvim_create_buf
		_G._original_vim_api_nvim_open_win = vim.api.nvim_open_win
		_G._original_vim_api_nvim_buf_set_lines = vim.api.nvim_buf_set_lines
		_G._original_vim_api_nvim_buf_set_option = vim.api.nvim_buf_set_option
		_G._original_vim_api_nvim_win_set_option = vim.api.nvim_win_set_option
		_G._original_vim_keymap_set = vim.keymap.set
		_G._original_vim_ui_input = vim.ui.input
		_G._original_vim_notify = vim.notify
		_G._original_vim_fn_expand = vim.fn.expand

		vim.api.nvim_create_buf = function()
			return 1
		end
		vim.api.nvim_open_win = function()
			return 1
		end
		vim.api.nvim_buf_set_lines = function() end
		vim.api.nvim_buf_set_option = function() end
		vim.api.nvim_win_set_option = function() end
		vim.keymap.set = function() end

		vim.api.nvim_list_uis = function()
			return {
				{
					width = 100,
					height = 40,
					rgb = true,
					ext_multigrid = false,
					ext_cmdline = false,
					ext_popupmenu = false,
				},
			}
		end

		vim.api.nvim_win_is_valid = function()
			return true
		end
		vim.api.nvim_buf_is_valid = function()
			return true
		end
		vim.api.nvim_win_close = function() end
		vim.api.nvim_create_namespace = function()
			return 1
		end
		vim.api.nvim_buf_add_highlight = function() end
		vim.api.nvim_buf_clear_namespace = function() end

		-- test data
		doit_state.todos = {
			{ text = "Test todo", done = false, created_at = os.time() },
		}

		doit_state.sort_todos = function() end

		config.options = {
			formatting = {
				done = {
					icon = "✓",
					format = { "icon", "text" },
				},
				pending = {
					icon = "○",
					format = { "icon", "text" },
				},
				in_progress = {
					icon = "◔",
					format = { "icon", "text" },
				},
			},
			keymaps = {
				new_todo = "n",
				toggle_todo = "<CR>",
				delete_todo = "d",
				close_window = "q",
				import_todos = "I",
				export_todos = "E",
			},
			window = {
				width = 60,
				height = 20,
				position = "right",
			},
			import_export_path = "~/todos.json",
		}
	end)

	after_each(function()
		vim.api.nvim_create_buf = _G._original_vim_api_nvim_create_buf
		vim.api.nvim_open_win = _G._original_vim_api_nvim_open_win
		vim.api.nvim_buf_set_lines = _G._original_vim_api_nvim_buf_set_lines
		vim.api.nvim_buf_set_option = _G._original_vim_api_nvim_buf_set_option
		vim.api.nvim_win_set_option = _G._original_vim_api_nvim_win_set_option
		vim.keymap.set = _G._original_vim_keymap_set
		vim.ui.input = _G._original_vim_ui_input
		vim.notify = _G._original_vim_notify
		vim.fn.expand = _G._original_vim_fn_expand
	end)

	it("should format todo line correctly", function()
		local todo = {
			text = "Test todo",
			done = false,
			created_at = os.time(),
		}

		local formatted = main_window.format_todo_line(todo)
		assert.are.equal("○ Test todo", formatted)
	end)

	it("should format completed todo line correctly", function()
		local todo = {
			text = "Completed todo",
			done = true,
			created_at = os.time(),
		}

		local formatted = main_window.format_todo_line(todo)
		assert.are.equal("✓ Completed todo", formatted)
	end)

	it("should format in-progress todo line correctly", function()
		local todo = {
			text = "In progress todo",
			done = false,
			in_progress = true,
			created_at = os.time(),
		}

		local formatted = main_window.format_todo_line(todo)
		assert.are.equal("◔ In progress todo", formatted)
	end)

	it("should format todo with due date correctly", function()
		_G._original_calendar = require("doit.calendar")
		package.loaded["doit.calendar"] = {
			MONTH_NAMES = {
				en = {
					"January",
					"February",
					"March",
					"April",
					"May",
					"June",
					"July",
					"August",
					"September",
					"October",
					"November",
					"December",
				},
			},
			get_language = function()
				return "en"
			end,
		}

		config.options.formatting.pending.format = { "icon", "text", "due_date" }
		config.options.calendar = { icon = "📅" }

		local tomorrow = os.time() + 86400 -- 24 hours from now
		local todo = {
			text = "Todo with due date",
			done = false,
			created_at = os.time(),
			due_at = tomorrow,
		}

		local formatted = main_window.format_todo_line(todo)
		assert.truthy(formatted:match("○ Todo with due date %[📅"))

		-- Restore original
		package.loaded["doit.calendar"] = _G._original_calendar
	end)

	it("should toggle todo window", function()
		local render_called = false
		local original_render = main_window.render_todos
		main_window.render_todos = function()
			render_called = true
		end

		main_window.toggle_todo_window()

		assert.is_true(render_called)

		main_window.render_todos = original_render
	end)

	it("should handle export todos correctly", function()
		local input_called = false
		local notify_called = false
		local notify_message = nil
		local notify_level = nil
		local export_called = false
		local expanded_path = nil

		-- Mock vim.ui.input to simulate user input
		vim.ui.input = function(opts, callback)
			input_called = true
			assert.are.equal("Export todos to file: ", opts.prompt)
			assert.are.equal("~/todos.json", opts.default)
			callback("/test/export_path.json")
		end

		-- Mock vim.notify to capture notifications
		vim.notify = function(msg, level)
			notify_called = true
			notify_message = msg
			notify_level = level
		end

		-- Mock vim.fn.expand to simulate path expansion
		vim.fn.expand = function(path)
			expanded_path = path
			return "/test/export_path.json"
		end

		-- Mock state.export_todos function
		doit_state.export_todos = function(path)
			export_called = true
			assert.are.equal("/test/export_path.json", path)
			return true, "Exported todos successfully"
		end

		-- Call the function being tested
		main_window.toggle_todo_window() -- Initialize window
		
		-- Extract the keymaps setup function
		local export_fn = nil
		local original_setup_keymap = vim.keymap.set
		vim.keymap.set = function(mode, key, fn, opts)
			if key == config.options.keymaps.export_todos then
				export_fn = fn
			end
		end
		
		main_window.toggle_todo_window() -- This will set up the keymaps
		
		-- Restore original function
		vim.keymap.set = original_setup_keymap
		
		-- Execute the export function
		export_fn()

		-- Assertions
		assert.is_true(input_called)
		assert.is_true(notify_called)
		assert.are.equal("Exported todos successfully", notify_message)
		assert.are.equal(vim.log.levels.INFO, notify_level)
		assert.is_true(export_called)
		assert.are.equal("/test/export_path.json", expanded_path)
	end)

	it("should handle import todos correctly", function()
		local input_called = false
		local notify_called = false
		local notify_message = nil
		local notify_level = nil
		local import_called = false
		local expanded_path = nil
		local render_called = false

		-- Mock vim.ui.input to simulate user input
		vim.ui.input = function(opts, callback)
			input_called = true
			assert.are.equal("Import todos from file: ", opts.prompt)
			assert.are.equal("~/todos.json", opts.default)
			callback("/test/import_path.json")
		end

		-- Mock vim.notify to capture notifications
		vim.notify = function(msg, level)
			notify_called = true
			notify_message = msg
			notify_level = level
		end

		-- Mock vim.fn.expand to simulate path expansion
		vim.fn.expand = function(path)
			expanded_path = path
			return "/test/import_path.json"
		end

		-- Mock state.import_todos function
		doit_state.import_todos = function(path)
			import_called = true
			assert.are.equal("/test/import_path.json", path)
			return true, "Imported todos successfully"
		end

		-- Save the original render function
		local original_render = main_window.render_todos
		main_window.render_todos = function()
			render_called = true
		end

		-- Call the function being tested
		main_window.toggle_todo_window() -- Initialize window
		
		-- Extract the keymaps setup function
		local import_fn = nil
		local original_setup_keymap = vim.keymap.set
		vim.keymap.set = function(mode, key, fn, opts)
			if key == config.options.keymaps.import_todos then
				import_fn = fn
			end
		end
		
		main_window.toggle_todo_window() -- This will set up the keymaps
		
		-- Restore original function
		vim.keymap.set = original_setup_keymap
		
		-- Execute the import function
		import_fn()

		-- Assertions
		assert.is_true(input_called)
		assert.is_true(notify_called)
		assert.are.equal("Imported todos successfully", notify_message)
		assert.are.equal(vim.log.levels.INFO, notify_level)
		assert.is_true(import_called)
		assert.are.equal("/test/import_path.json", expanded_path)
		assert.is_true(render_called)

		-- Restore original render function
		main_window.render_todos = original_render
	end)

	it("should handle cancelled import correctly", function()
		local notify_called = false
		local notify_message = nil
		local notify_level = nil
		local import_called = false

		-- Mock vim.ui.input to simulate cancelled input
		vim.ui.input = function(opts, callback)
			callback(nil) -- User cancelled
		end

		-- Mock vim.notify to capture notifications
		vim.notify = function(msg, level)
			notify_called = true
			notify_message = msg
			notify_level = level
		end

		-- Mock state.import_todos function
		doit_state.import_todos = function()
			import_called = true
			return true, "This should not be called"
		end

		-- Call the function being tested
		main_window.toggle_todo_window() -- Initialize window
		
		-- Extract the keymaps setup function
		local import_fn = nil
		local original_setup_keymap = vim.keymap.set
		vim.keymap.set = function(mode, key, fn, opts)
			if key == config.options.keymaps.import_todos then
				import_fn = fn
			end
		end
		
		main_window.toggle_todo_window() -- This will set up the keymaps
		
		-- Restore original function
		vim.keymap.set = original_setup_keymap
		
		-- Execute the import function
		import_fn()

		-- Assertions
		assert.is_true(notify_called)
		assert.are.equal("Import cancelled", notify_message)
		assert.are.equal(vim.log.levels.INFO, notify_level)
		assert.is_false(import_called)
	end)

	it("should handle import failure correctly", function()
		local notify_called = false
		local notify_message = nil
		local notify_level = nil

		-- Mock vim.ui.input to simulate user input
		vim.ui.input = function(opts, callback)
			callback("/test/import_path.json")
		end

		-- Mock vim.notify to capture notifications
		vim.notify = function(msg, level)
			notify_called = true
			notify_message = msg
			notify_level = level
		end

		-- Mock vim.fn.expand to return the path
		vim.fn.expand = function(path)
			return "/test/import_path.json"
		end

		-- Mock state.import_todos function to simulate failure
		doit_state.import_todos = function()
			return false, "Failed to import: file not found"
		end

		-- Call the function being tested
		main_window.toggle_todo_window() -- Initialize window
		
		-- Extract the keymaps setup function
		local import_fn = nil
		local original_setup_keymap = vim.keymap.set
		vim.keymap.set = function(mode, key, fn, opts)
			if key == config.options.keymaps.import_todos then
				import_fn = fn
			end
		end
		
		main_window.toggle_todo_window() -- This will set up the keymaps
		
		-- Restore original function
		vim.keymap.set = original_setup_keymap
		
		-- Execute the import function
		import_fn()

		-- Assertions
		assert.is_true(notify_called)
		assert.are.equal("Failed to import: file not found", notify_message)
		assert.are.equal(vim.log.levels.ERROR, notify_level)
	end)
end)