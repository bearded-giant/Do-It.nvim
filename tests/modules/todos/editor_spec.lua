-- The details/note editor is a real buffer: :w saves through state, q saves and
-- closes, and nothing parses from fixed line numbers the user can break.

describe("editor", function()
	local tmpdir, orig_stdpath, state, editor

	local function read_list()
		local f = io.open(tmpdir .. "/doit/lists/work.json", "r")
		local data = vim.fn.json_decode(f:read("*all"))
		f:close()
		return data
	end

	local function set_buffer(lines)
		vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
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
			todos = { { id = "a", text = "alpha", description = "old details", done = false } },
			notes = { { id = "n1", title = "scratch", body = "one", updated_at = 1 } },
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
		editor = require("doit.ui.editor")
	end)

	after_each(function()
		for _, w in ipairs(vim.api.nvim_list_wins()) do
			if vim.api.nvim_win_get_config(w).relative ~= "" then
				pcall(vim.api.nvim_win_close, w, true)
			end
		end
		vim.cmd("silent! %bwipeout!")
		vim.fn.stdpath = orig_stdpath
		vim.fn.delete(tmpdir, "rf")
	end)

	it("opens a todo as text, marker, details with the cursor on the details", function()
		editor.edit_todo(state.todos[1])

		assert.are.same({ "alpha", editor.TODO_MARKER, "old details" }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
		assert.are.equal(3, vim.api.nvim_win_get_cursor(0)[1])
	end)

	it("saves text and stamped details on :w", function()
		editor.edit_todo(state.todos[1])
		set_buffer({ "alpha renamed", editor.TODO_MARKER, "line one", "line two", "" })
		vim.cmd("write")

		local saved = read_list().todos[1]
		assert.are.equal("alpha renamed", saved.text)
		assert.is_truthy(saved.description:find("^line one\nline two\n\n\n%-%-%-%-%-%-%-%-%-%-\nlast modified: "))
		assert.is_false(vim.bo.modified)
	end)

	it("q saves and closes", function()
		local before = vim.api.nvim_get_current_win()
		editor.edit_todo(state.todos[1])
		set_buffer({ "alpha", editor.TODO_MARKER, "via q" })
		vim.fn.maparg("q", "n", false, true).callback()

		assert.are.equal(before, vim.api.nvim_get_current_win())
		assert.is_truthy(read_list().todos[1].description:find("^via q"))
	end)

	it("keeps the buffer modified when the todo is gone", function()
		local todo = state.todos[1]
		editor.edit_todo(todo)
		table.remove(state.todos, 1)
		set_buffer({ "alpha", editor.TODO_MARKER, "lost?" })
		vim.cmd("write")

		assert.is_true(vim.bo.modified)
	end)

	it("edits a note title and body together", function()
		editor.edit_note(state.get_notes()[1])
		assert.are.same({ "scratch", editor.NOTE_MARKER, "one" }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
		set_buffer({ "renamed", editor.NOTE_MARKER, "two", "three" })
		vim.cmd("write")

		local note = read_list().notes[1]
		assert.are.equal("renamed", note.title)
		assert.are.equal("two\nthree", note.body)
		assert.is_true(note.updated_at > 1)
	end)

	it("adds a new note once and updates it on later saves", function()
		editor.edit_note(nil, { todo_ids = { "a" } })
		vim.cmd("stopinsert")
		set_buffer({ "repro steps", editor.NOTE_MARKER, "first" })
		vim.cmd("write")
		set_buffer({ "repro steps", editor.NOTE_MARKER, "second" })
		vim.cmd("write")

		local notes = read_list().notes
		assert.are.equal(2, #notes)
		assert.are.equal("second", notes[2].body)
		assert.are.same({ "a" }, notes[2].todo_ids)
	end)

	it("adds nothing for an empty new note", function()
		editor.edit_note(nil)
		vim.cmd("stopinsert")
		vim.cmd("write")

		assert.are.equal(1, #read_list().notes)
	end)

	it("treats line 1 as the head when the marker was deleted", function()
		local head, body = editor._split_at_marker({ "title", "body a", "body b" })
		assert.are.same({ "title" }, head)
		assert.are.same({ "body a", "body b" }, body)
	end)
end)
