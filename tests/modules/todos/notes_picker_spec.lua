-- Notes related to todos: note.todo_ids links a list note to todos in the same
-- list; the picker scopes to a todo, creates linked notes, and toggles links.

describe("notes picker and note links", function()
	local tmpdir, orig_stdpath, state, picker, note_links

	local function read_list()
		local f = io.open(tmpdir .. "/doit/lists/work.json", "r")
		local data = vim.fn.json_decode(f:read("*all"))
		f:close()
		return data
	end

	local function press(key)
		local map = vim.fn.maparg(key, "n", false, true)
		assert.is_not_nil(map.callback, key .. " is not mapped")
		map.callback()
	end

	local function buffer_text()
		return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
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
		local f = io.open(tmpdir .. "/doit/lists/work.json", "w")
		f:write(vim.fn.json_encode({
			_metadata = {},
			todos = {
				{ id = "a", text = "fix login", done = false, order_index = 1 },
				{ id = "b", text = "deploy", done = false, order_index = 2 },
			},
			notes = {
				{ id = "n1", title = "repro", body = "steps", todo_ids = { "a", "gone" } },
				{ id = "n2", title = "unrelated", body = "misc" },
			},
		}))
		f:close()
		for key in pairs(package.loaded) do
			if key == "doit" or key:match("^doit%.") then
				package.loaded[key] = nil
			end
		end
		require("doit").setup({ modules = { todos = { enabled = true } } })
		state = require("doit.core").get_module("todos").state
		state.load_list("work")
		picker = require("doit.ui.notes_picker")
		note_links = require("doit.modules.todos.state.note_links")
	end)

	after_each(function()
		picker.close()
		for _, w in ipairs(vim.api.nvim_list_wins()) do
			if vim.api.nvim_win_get_config(w).relative ~= "" then
				pcall(vim.api.nvim_win_close, w, true)
			end
		end
		vim.cmd("silent! %bwipeout!")
		vim.fn.stdpath = orig_stdpath
		vim.fn.delete(tmpdir, "rf")
	end)

	describe("note_links", function()
		it("skips stale ids in both directions", function()
			local notes = state.get_notes()
			assert.are.equal(1, #note_links.notes_for_todo(notes, "a"))
			assert.are.equal(0, #note_links.notes_for_todo(notes, "b"))
			assert.are.same({ "a" }, vim.tbl_map(function(t) return t.id end, note_links.todos_for_note(state.todos, notes[1])))
			assert.are.same({}, note_links.todos_for_note(state.todos, notes[2]))
		end)

		it("toggles an id in and out", function()
			assert.are.same({ "x", "b" }, note_links.toggled({ "x" }, "b"))
			assert.are.same({ "x" }, note_links.toggled({ "x", "b" }, "b"))
			assert.are.same({ "b" }, note_links.toggled(nil, "b"))
		end)
	end)

	it("scopes to a todo's notes and toggles to all", function()
		picker.open({ todo = state.todos[1] })
		assert.is_truthy(buffer_text():find("repro", 1, true))
		assert.is_falsy(buffer_text():find("unrelated", 1, true))

		press("a")
		assert.is_truthy(buffer_text():find("unrelated", 1, true))
	end)

	it("creates a note already linked to the todo", function()
		picker.open({ todo = state.todos[2] })
		press("n")
		vim.cmd("stopinsert")
		vim.api.nvim_buf_set_lines(0, 0, -1, false, { "deploy notes", "── body", "run it" })
		vim.cmd("write")

		local notes = read_list().notes
		assert.are.equal(3, #notes)
		assert.are.same({ "b" }, notes[3].todo_ids)
	end)

	it("links and unlinks an existing note", function()
		picker.open({ todo = state.todos[2] })
		press("a")
		vim.api.nvim_win_set_cursor(0, { 2, 0 })
		press("l")
		assert.are.same({ "b" }, read_list().notes[2].todo_ids)

		press("l")
		assert.is_nil(read_list().notes[2].todo_ids)
	end)

	it("filters by title and body", function()
		local orig_input = vim.ui.input
		vim.ui.input = function(_, cb)
			cb("misc")
		end
		picker.open({})
		press("/")
		vim.ui.input = orig_input

		local text = buffer_text()
		assert.is_truthy(text:find("unrelated", 1, true))
		assert.is_falsy(text:find("repro", 1, true))
	end)

	it("opens the note editor on <CR>", function()
		picker.open({})
		press("<CR>")

		assert.are.equal("repro", vim.api.nvim_buf_get_lines(0, 0, 1, false)[1])
		assert.is_truthy(vim.api.nvim_win_get_config(0).footer)
	end)

	describe("main window", function()
		local main_window

		local function line_of(pred)
			for i, row in ipairs(main_window._rendered_rows) do
				if pred(row) then
					return i, row
				end
			end
		end

		before_each(function()
			main_window = require("doit.ui.main_window")
			main_window.toggle_todo_window()
		end)

		after_each(function()
			main_window.close_window()
		end)

		it("marks linked counts on todo and note rows", function()
			local _, todo_row = line_of(function(r) return r.todo and r.todo.id == "a" end)
			local _, other_row = line_of(function(r) return r.todo and r.todo.id == "b" end)
			local _, note_row = line_of(function(r) return r.note and r.note.id == "n1" end)

			assert.is_truthy(todo_row.display:find("≡1", 1, true))
			assert.is_falsy(other_row.display:find("≡", 1, true))
			assert.is_truthy(note_row.display:find("≡1", 1, true))
		end)

		it("hides the details marker for a footer-only description", function()
			state.todos[2].description = "\n\n\n----------\nlast modified: 2026-10-30: 06:00"
			main_window.render_todos()
			local _, row = line_of(function(r) return r.todo and r.todo.id == "b" end)

			assert.is_falsy(row.display:find("[NOTES]", 1, true))
		end)

		it("g on a todo row opens the picker scoped to that todo", function()
			vim.api.nvim_win_set_cursor(0, { line_of(function(r) return r.todo and r.todo.id == "a" end), 0 })
			press("g")

			assert.is_true(picker.is_open())
			assert.is_truthy(buffer_text():find("repro", 1, true))
			assert.is_falsy(buffer_text():find("unrelated", 1, true))
		end)

		it("n on the Notes header starts a new note, not a todo", function()
			vim.api.nvim_win_set_cursor(0, { line_of(function(r) return r.kind == "note_header" end), 0 })
			press("n")

			assert.is_truthy(vim.api.nvim_buf_get_name(0):find("doit://note/new", 1, true))
		end)
	end)
end)
