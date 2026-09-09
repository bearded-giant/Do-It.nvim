-- The list views badge each list with its overdue count, so get_available_lists
-- has to carry the counts (and enough item detail for the startup notification)
-- without loading every list into state.

describe("list overdue metadata", function()
	local tmpdir, orig_stdpath, state

	local function day_offset(days)
		return os.date("%Y-%m-%d", os.time() + days * 86400)
	end

	local function write_list(name, todos)
		vim.fn.mkdir(tmpdir .. "/doit/lists", "p")
		local f = io.open(tmpdir .. "/doit/lists/" .. name .. ".json", "w")
		f:write(vim.fn.json_encode({ todos = todos, _metadata = {} }))
		f:close()
	end

	local function list_named(lists, name)
		for _, list in ipairs(lists) do
			if list.name == name then
				return list
			end
		end
	end

	before_each(function()
		tmpdir = vim.fn.tempname()
		vim.fn.mkdir(tmpdir, "p")
		orig_stdpath = vim.fn.stdpath
		vim.fn.stdpath = function(what)
			if what == "data" then
				return tmpdir
			end
			return orig_stdpath(what)
		end

		write_list("daily", {
			{ id = "1", text = "late one\nsecond line", done = false, due_date = day_offset(-3) },
			{ id = "2", text = "late two", done = false, due_date = day_offset(-1) },
			{ id = "3", text = "today", done = false, due_date = day_offset(0) },
			{ id = "4", text = "later", done = false, due_date = day_offset(5) },
			{ id = "5", text = "finished late", done = true, due_date = day_offset(-9) },
			{ id = "6", text = "no due date", done = false },
		})
		write_list("clean", {
			{ id = "1", text = "nothing due", done = false },
		})

		for key in pairs(package.loaded) do
			if key == "doit" or key:match("^doit%.") then
				package.loaded[key] = nil
			end
		end
		require("doit").setup({ modules = { todos = { enabled = true } } })
		state = require("doit.core").get_module("todos").state
	end)

	after_each(function()
		vim.fn.stdpath = orig_stdpath
		vim.fn.delete(tmpdir, "rf")
	end)

	it("counts open overdue and due-today items per list", function()
		local lists = state.get_available_lists()
		local daily = list_named(lists, "daily")

		assert.are.equal(2, daily.metadata.overdue_count)
		assert.are.equal(1, daily.metadata.due_today_count)
	end)

	it("carries the first line of each overdue item for the notification", function()
		local daily = list_named(state.get_available_lists(), "daily")

		assert.are.equal(2, #daily.metadata.overdue_items)
		assert.are.equal("late one", daily.metadata.overdue_items[1].text)
		assert.are.equal(day_offset(-3), daily.metadata.overdue_items[1].due_date)
	end)

	it("reports zero for a list with nothing due", function()
		local clean = list_named(state.get_available_lists(), "clean")

		assert.are.equal(0, clean.metadata.overdue_count)
		assert.are.equal(0, clean.metadata.due_today_count)
		assert.are.same({}, clean.metadata.overdue_items)
	end)

	it("never writes the derived counts back to disk", function()
		state.get_available_lists()
		state.load_list("daily")
		state.save_todos()

		local f = io.open(tmpdir .. "/doit/lists/daily.json", "r")
		local data = vim.fn.json_decode(f:read("*all"))
		f:close()
		assert.is_nil(data._metadata.overdue_count)
		assert.is_nil(data._metadata.overdue_items)
	end)
end)
