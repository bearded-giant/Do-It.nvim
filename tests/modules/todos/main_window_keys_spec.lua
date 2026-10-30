-- Enter is the tmux manager's "open item" key, so the nvim main window binds it
-- to the same thing: detail on a todo row, the note on a note row.
describe("main window keys", function()
	local main_window, todo_actions, doit_state

	local function line_where(pred)
		for i, row in ipairs(main_window.build_render_rows()) do
			if pred(row) then
				return i
			end
		end
	end

	local function press(key)
		local map = vim.fn.maparg(key, "n", false, true)
		assert.is_not_nil(map.callback, key .. " is not mapped in the main window")
		map.callback()
	end

	before_each(function()
		package.loaded["doit.state"] = nil
		require("doit").setup({ modules = { todos = { enabled = true } } })
		doit_state = require("doit.state")
		doit_state.todos = {}
		doit_state.save_to_disk = function() end
		doit_state.save_todos = function() end
		doit_state.load_list = function() end
		doit_state.get_notes = function()
			return { { id = "n1", title = "scratch" } }
		end
		main_window = require("doit.ui.main_window")
		todo_actions = require("doit.ui.todo_actions")
	end)

	after_each(function()
		for _, w in ipairs(vim.api.nvim_list_wins()) do
			if vim.api.nvim_win_get_config(w).relative ~= "" then
				pcall(vim.api.nvim_win_close, w, true)
			end
		end
	end)

	it("opens the detail of the todo under the cursor", function()
		local todo = doit_state.add_todo("ship the fix", {})
		todo.description = "why it broke"
		main_window.toggle_todo_window()
		local main_win = vim.api.nvim_get_current_win()
		vim.api.nvim_win_set_cursor(main_win, { line_where(function(r) return r.todo == todo end), 0 })

		press("<CR>")

		assert.are_not.equal(main_win, vim.api.nvim_get_current_win())
		local shown = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
		assert.is_truthy(shown:find("ship the fix", 1, true))
		assert.is_truthy(shown:find("why it broke", 1, true))
	end)

	it("opens the note on a note row", function()
		local opened
		local original = todo_actions.edit_note
		todo_actions.edit_note = function()
			opened = todo_actions.get_note_at_cursor(vim.api.nvim_get_current_win())
		end
		doit_state.add_todo("a todo", {})
		main_window.toggle_todo_window()
		vim.api.nvim_win_set_cursor(0, { line_where(function(r) return r.kind == "note" end), 0 })

		press("<CR>")
		todo_actions.edit_note = original

		assert.are.equal("n1", opened and opened.id)
	end)

	it("walks section headers with [ and ] like tmux, wrapping at the ends", function()
		doit_state.add_todo("urgent thing", { "critical" })
		doit_state.add_todo("someday", {})
		main_window.toggle_todo_window()
		local win = vim.api.nvim_get_current_win()
		local heads = {}
		for i, row in ipairs(main_window.build_render_rows()) do
			if row.kind == "priority_header" or row.kind == "note_header" then
				heads[#heads + 1] = i
			end
		end
		assert.are.equal(3, #heads)
		vim.api.nvim_win_set_cursor(win, { heads[1], 0 })

		local function at()
			return vim.api.nvim_win_get_cursor(win)[1]
		end
		press("[")
		assert.are.equal(heads[2], at())
		press("[")
		assert.are.equal(heads[3], at())
		assert.are.equal("note_header", main_window.build_render_rows()[at()].kind)
		press("[")
		assert.are.equal(heads[1], at())
		press("]")
		assert.are.equal(heads[3], at())
	end)
end)
