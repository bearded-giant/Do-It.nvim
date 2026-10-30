-- The nvim todo window shares the tmux manager's keys (tmux/scripts/todo-interactive.sh)
-- so one set of habits works on both surfaces; each shared key does the same thing.

describe("keymap parity with the tmux manager", function()
	local defaults = require("doit.modules.todos.config").defaults.keymaps

	local tmux = {
		new_todo = "n", paste_todo = "p", view_detail = "<CR>", start_todo = "s", complete_todo = "x",
		revert_to_pending = "X", edit_todo = "e", edit_description = "N", edit_priorities = "P",
		delete_todo = "d", delete_completed = "D", undo_delete = "u", set_due_date = "h", set_sequence = "S",
		move_up = "K", move_down = "J", section_down = "[", section_up = "]", toggle_tags = "t",
		clear_filter = "c", search_todos = "/", move_todo_to_list = "m", switch_list = "l",
		toggle_list_manager = "L", notes_picker = "g", copy_text = "y", copy_details = "<C-y>",
		copy_todo_id = "i", copy_list_name = "Y", export_to_daily = "O", export_markdown = "E",
		backup_todos = "B", refresh = "r", toggle_help = "?", close_window = "q",
	}

	it("binds every shared action to the tmux key", function()
		for action, key in pairs(tmux) do
			assert.are.equal(key, defaults[action], action)
		end
	end)

	it("gives no two main-window actions the same key", function()
		local picker_only = { toggle_priority = true, edit_tag = true, delete_tag = true }
		local seen = {}
		for action, key in pairs(defaults) do
			if not picker_only[action] and not key:match("^<leader>") then
				assert.is_nil(seen[key], key .. " bound to " .. tostring(seen[key]) .. " and " .. action)
				seen[key] = action
			end
		end
	end)

	describe("in the window", function()
		local tmpdir, orig_stdpath, state, main_window

		local function press(key)
			local map = vim.fn.maparg(key, "n", false, true)
			assert.is_not_nil(map.callback, key .. " is not mapped")
			map.callback()
		end

		local function find(id)
			for _, t in ipairs(state.todos) do
				if t.id == id then
					return t
				end
			end
		end

		local function cursor_on(id)
			for i, row in ipairs(main_window._rendered_rows) do
				if row.todo and row.todo.id == id then
					vim.api.nvim_win_set_cursor(0, { i, 0 })
					return i
				end
			end
			error("no row for " .. id)
		end

		local function cursor_todo()
			local row = main_window._rendered_rows[vim.api.nvim_win_get_cursor(0)[1]]
			return row and row.todo and row.todo.id
		end

		before_each(function()
			tmpdir = vim.fn.tempname()
			vim.fn.mkdir(tmpdir .. "/doit/lists", "p")
			orig_stdpath = vim.fn.stdpath
			vim.fn.stdpath = function(what)
				if what == "data" then
					return tmpdir
				end
				return orig_stdpath(what)
			end
			for _, name in ipairs({ "work", "other" }) do
				local f = io.open(tmpdir .. "/doit/lists/" .. name .. ".json", "w")
				f:write(vim.fn.json_encode({
					_metadata = {},
					todos = name == "work" and {
						{ id = "a", text = "alpha", done = false, in_progress = true, order_index = 1 },
						{ id = "b", text = "bravo", done = false, order_index = 2, description = "why\n\n\n----------\nlast modified: 2026-10-30: 06:00" },
						{ id = "c", text = "charlie", done = false, order_index = 3 },
					} or { { id = "z", text = "zulu", done = false } },
					notes = {},
				}))
				f:close()
			end
			for key in pairs(package.loaded) do
				if key == "doit" or key:match("^doit%.") then
					package.loaded[key] = nil
				end
			end
			require("doit").setup({ modules = { todos = { enabled = true } } })
			state = require("doit.core").get_module("todos").state
			state.load_list("work")
			main_window = require("doit.ui.main_window")
			main_window.toggle_todo_window()
		end)

		after_each(function()
			main_window.close_window()
			for _, w in ipairs(vim.api.nvim_list_wins()) do
				if vim.api.nvim_win_get_config(w).relative ~= "" then
					pcall(vim.api.nvim_win_close, w, true)
				end
			end
			vim.fn.stdpath = orig_stdpath
			vim.fn.delete(tmpdir, "rf")
		end)

		it("s starts one item and stops the others", function()
			cursor_on("b")
			press("s")

			assert.is_true(find("b").in_progress)
			assert.is_false(find("a").in_progress == true)
		end)

		it("x completes and u undoes it", function()
			cursor_on("c")
			press("x")
			assert.is_true(find("c").done)
			assert.is_truthy(find("c").completed_at)

			press("u")
			assert.is_false(find("c").done)
			assert.is_nil(find("c").completed_at)
		end)

		it("u restores a delete", function()
			cursor_on("c")
			press("d")
			assert.is_nil(find("c"))

			press("u")
			assert.is_truthy(find("c"))
		end)

		it("J and K move within the group and the cursor follows", function()
			cursor_on("b")
			press("J")
			assert.are.equal("b", cursor_todo())
			assert.is_true(find("b").order_index > find("c").order_index)

			press("K")
			assert.is_true(find("b").order_index < find("c").order_index)
		end)

		it("h sets and clears a typed due date", function()
			local orig = vim.ui.input
			cursor_on("c")
			vim.ui.input = function(_, cb) cb("2030-01-02") end
			press("h")
			assert.are.equal("2030-01-02", find("c").due_date)

			cursor_on("c")
			vim.ui.input = function(_, cb) cb("") end
			press("h")
			vim.ui.input = orig
			assert.is_nil(find("c").due_date)
		end)

		it("y, C-y, i and Y copy text, details, id and list name", function()
			cursor_on("b")
			press("y")
			assert.are.equal("bravo", vim.fn.getreg('"'))
			press("<C-Y>")
			assert.are.equal("why", vim.fn.getreg('"'))
			press("i")
			assert.are.equal("b", vim.fn.getreg('"'))
			press("Y")
			assert.are.equal("work", vim.fn.getreg('"'))
		end)

		it("p adds a todo from the clipboard", function()
			local orig_getreg, orig_input = vim.fn.getreg, vim.ui.input
			vim.fn.getreg = function(r)
				return r == "+" and "from clipboard\nsecond line" or orig_getreg(r)
			end
			vim.ui.input = function(opts, cb) cb(opts.default) end
			press("p")
			vim.fn.getreg, vim.ui.input = orig_getreg, orig_input

			assert.are.equal("from clipboard", state.todos[#state.todos].text)
		end)

		it("/ jumps to the chosen match", function()
			local orig_input, orig_select = vim.ui.input, vim.ui.select
			vim.ui.input = function(_, cb) cb("a") end
			vim.ui.select = function(items, _, cb)
				for _, t in ipairs(items) do
					if t.id == "c" then
						cb(t)
					end
				end
			end
			cursor_on("a")
			press("/")
			vim.ui.input, vim.ui.select = orig_input, orig_select

			assert.are.equal("c", cursor_todo())
		end)

		it("l switches the list", function()
			local selector = require("doit.ui.list_selector")
			local orig = selector.show_list_selector
			selector.show_list_selector = function(_, cb) cb("other") end
			press("l")
			selector.show_list_selector = orig

			assert.are.equal("other", state.todo_lists.active)
			assert.are.equal("z", state.todos[1].id)
		end)

		it("r reloads an outside edit", function()
			local path = tmpdir .. "/doit/lists/work.json"
			local f = io.open(path, "r")
			local data = vim.fn.json_decode(f:read("*all"))
			f:close()
			table.insert(data.todos, { id = "d", text = "delta", done = false })
			f = io.open(path, "w")
			f:write(vim.fn.json_encode(data))
			f:close()

			press("r")
			assert.is_truthy(find("d"))
		end)
	end)
end)
