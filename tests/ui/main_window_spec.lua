local main_window = require("dooing.ui.main_window")
local dooing_state = require("dooing.state")
local config = require("dooing.config")

describe("main_window", function()
	before_each(function()
		_G._original_vim_api_nvim_create_buf = vim.api.nvim_create_buf
		_G._original_vim_api_nvim_open_win = vim.api.nvim_open_win
		_G._original_vim_api_nvim_buf_set_lines = vim.api.nvim_buf_set_lines
		_G._original_vim_api_nvim_buf_set_option = vim.api.nvim_buf_set_option
		_G._original_vim_api_nvim_win_set_option = vim.api.nvim_win_set_option
		_G._original_vim_keymap_set = vim.keymap.set

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
		dooing_state.todos = {
			{ text = "Test todo", done = false, created_at = os.time() },
		}

		dooing_state.sort_todos = function() end

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
			},
			window = {
				width = 60,
				height = 20,
				position = "right",
			},
		}
	end)

	after_each(function()
		vim.api.nvim_create_buf = _G._original_vim_api_nvim_create_buf
		vim.api.nvim_open_win = _G._original_vim_api_nvim_open_win
		vim.api.nvim_buf_set_lines = _G._original_vim_api_nvim_buf_set_lines
		vim.api.nvim_buf_set_option = _G._original_vim_api_nvim_buf_set_option
		vim.api.nvim_win_set_option = _G._original_vim_api_nvim_win_set_option
		vim.keymap.set = _G._original_vim_keymap_set
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
		_G._original_calendar = require("dooing.calendar")
		package.loaded["dooing.calendar"] = {
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
		package.loaded["dooing.calendar"] = _G._original_calendar
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
end)

