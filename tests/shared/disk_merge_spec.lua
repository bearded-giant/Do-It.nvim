-- tmux and the MCP write list files while nvim holds the same list in memory.
-- An nvim save must keep their edits: per item, per field, nvim wins only what
-- nvim changed since it last read or wrote the file.

describe("disk merge", function()
	local tmpdir, orig_stdpath, state

	local function list_path(name)
		return tmpdir .. "/doit/lists/" .. name .. ".json"
	end

	local function read_list(name)
		local f = io.open(list_path(name), "r")
		local data = vim.fn.json_decode(f:read("*all"))
		f:close()
		return data
	end

	-- what tmux does: read, jq, write back; the sleep forces a new mtime on coarse clocks
	local function external_edit(name, fn)
		vim.wait(1100)
		local data = read_list(name)
		fn(data)
		local f = io.open(list_path(name), "w")
		f:write(vim.fn.json_encode(data))
		f:close()
	end

	local function find(items, id)
		for _, item in ipairs(items or {}) do
			if item.id == id then
				return item
			end
		end
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
		local f = io.open(list_path("work"), "w")
		f:write(vim.fn.json_encode({
			_metadata = { source = "user" },
			todos = {
				{ id = "a", text = "alpha", done = false, order_index = 1 },
				{ id = "x", text = "xray", done = false, order_index = 2 },
			},
			notes = { { id = "n1", title = "scratch", body = "one" } },
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
	end)

	after_each(function()
		vim.fn.stdpath = orig_stdpath
		vim.fn.delete(tmpdir, "rf")
	end)

	it("keeps an item the MCP added while nvim changes another", function()
		external_edit("work", function(data)
			table.insert(data.todos, { id = "b", text = "bravo", done = false, order_index = 3 })
		end)

		find(state.todos, "a").done = true
		state.save_to_disk()

		local disk = read_list("work")
		assert.is_truthy(find(disk.todos, "b"))
		assert.is_true(find(disk.todos, "a").done)
		assert.is_truthy(find(state.todos, "b"))
	end)

	it("merges per field on the same item", function()
		external_edit("work", function(data)
			find(data.todos, "x").done = true
		end)

		local x = find(state.todos, "x")
		x.text = "xray renamed"
		state.save_to_disk()

		local disk_x = find(read_list("work").todos, "x")
		assert.is_true(disk_x.done)
		assert.are.equal("xray renamed", disk_x.text)
		assert.are.equal(x, find(state.todos, "x"))
		assert.is_true(x.done)
	end)

	it("does not resurrect an item tmux deleted, and keeps an nvim delete", function()
		external_edit("work", function(data)
			table.remove(data.todos, 1)
		end)

		for i, t in ipairs(state.todos) do
			if t.id == "x" then
				table.remove(state.todos, i)
			end
		end
		state.save_to_disk()

		assert.are.equal(0, #read_list("work").todos)
	end)

	it("ignores render-only keys when deciding what nvim changed", function()
		external_edit("work", function(data)
			find(data.todos, "a").done = true
		end)

		find(state.todos, "a")._priority_weight = 4
		find(state.todos, "x").text = "touched"
		state.save_to_disk()

		assert.is_true(find(read_list("work").todos, "a").done)
	end)

	it("merges list notes the same way", function()
		external_edit("work", function(data)
			data.notes[1].body = "edited in tmux"
		end)

		state.add_note("new", "from nvim")

		local notes = read_list("work").notes
		assert.are.equal("edited in tmux", find(notes, "n1").body)
		assert.are.equal(2, #notes)
	end)

	it("refresh_if_changed reloads only after an outside write", function()
		assert.is_false(state.refresh_if_changed())
		external_edit("work", function(data)
			table.insert(data.todos, { id = "c", text = "charlie", done = false })
		end)

		assert.is_true(state.refresh_if_changed())
		assert.is_truthy(find(state.todos, "c"))
		assert.is_false(state.refresh_if_changed())
	end)

	it("re-renders an open window on an outside write and keeps the cursor item", function()
		local main_window = require("doit.ui.main_window")
		main_window.toggle_todo_window()
		local win = vim.api.nvim_get_current_win()
		local function line_of(id)
			for i, row in ipairs(main_window._rendered_rows) do
				if row.todo and row.todo.id == id then
					return i
				end
			end
		end
		vim.api.nvim_win_set_cursor(win, { line_of("x"), 0 })

		external_edit("work", function(data)
			table.insert(data.todos, 1, { id = "b", text = "bravo", done = false, order_index = 0 })
		end)

		assert.is_true(vim.wait(3000, function()
			return line_of("b") ~= nil
		end, 50))
		assert.are.equal(line_of("x"), vim.api.nvim_win_get_cursor(win)[1])
		main_window.close_window()
	end)
end)
