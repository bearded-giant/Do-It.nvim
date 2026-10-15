-- daily is the owed-items inbox every surface writes twins into, so it can be
-- neither deleted nor renamed, from the state API or from the list manager.

describe("permanent daily list", function()
	local tmpdir, orig_stdpath, orig_notify, orig_input, orig_uis, todos, warnings, prompts

	local function list_path(name)
		return tmpdir .. "/doit/lists/" .. name .. ".json"
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
		local f = io.open(list_path("daily"), "w")
		f:write('{"todos": [], "_metadata": {"created_at": 1}}')
		f:close()

		for key in pairs(package.loaded) do
			if key == "doit" or key:match("^doit%.") then
				package.loaded[key] = nil
			end
		end
		require("doit").setup({ modules = { todos = { enabled = true } } })
		todos = require("doit.core").get_module("todos")

		warnings, prompts = {}, {}
		orig_notify = vim.notify
		vim.notify = function(msg, level)
			if level == vim.log.levels.WARN then
				table.insert(warnings, msg)
			end
		end
		orig_input = vim.ui.input
		vim.ui.input = function(opts)
			table.insert(prompts, opts.prompt)
		end
		-- headless has no attached UI and the list manager sizes itself from one
		orig_uis = vim.api.nvim_list_uis
		vim.api.nvim_list_uis = function()
			return { { width = 120, height = 40 } }
		end
	end)

	after_each(function()
		pcall(todos.ui.list_manager_window.close_window)
		vim.notify = orig_notify
		vim.ui.input = orig_input
		vim.api.nvim_list_uis = orig_uis
		vim.fn.stdpath = orig_stdpath
		vim.fn.delete(tmpdir, "rf")
	end)

	it("state.delete_list refuses daily", function()
		local ok, msg = todos.state.delete_list("daily")
		assert.is_false(ok)
		assert.are.equal("daily is permanent; it can't be deleted", msg)
		assert.are.equal(1, vim.fn.filereadable(list_path("daily")))
	end)

	it("state.rename_list refuses daily", function()
		local ok, msg = todos.state.rename_list("daily", "inbox")
		assert.is_false(ok)
		assert.are.equal("daily is permanent; it can't be renamed", msg)
		assert.are.equal(1, vim.fn.filereadable(list_path("daily")))
		assert.are.equal(0, vim.fn.filereadable(list_path("inbox")))
	end)

	it("list manager delete on daily warns before any prompt", function()
		todos.ui.list_manager_window.toggle_window()
		todos.ui.list_manager_window.delete_list()
		assert.are.same({}, prompts)
		assert.are.same({ "daily is permanent; it can't be deleted" }, warnings)
		assert.are.equal(1, vim.fn.filereadable(list_path("daily")))
	end)

	it("list manager rename on daily warns before any prompt", function()
		todos.ui.list_manager_window.toggle_window()
		todos.ui.list_manager_window.rename_list()
		assert.are.same({}, prompts)
		assert.are.same({ "daily is permanent; it can't be renamed" }, warnings)
	end)
end)
