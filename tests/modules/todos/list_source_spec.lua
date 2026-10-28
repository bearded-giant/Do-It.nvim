-- list source: a list is the user's when it is daily or `_metadata.source == "user"`;
-- session.json `source_filter` (shared with tmux and the MCP) picks which lists the
-- nvim pickers show. Mirrors tests/tmux/test_list_source.sh.

describe("list source", function()
	local tmpdir, orig_stdpath, orig_notify, orig_input, orig_uis, orig_tmux, orig_pane
	local todos, source, notices

	local function list_path(name)
		return tmpdir .. "/doit/lists/" .. name .. ".json"
	end

	local function session_path()
		return tmpdir .. "/doit/session.json"
	end

	local function write_raw(path, content)
		local f = io.open(path, "w")
		f:write(content)
		f:close()
	end

	local function read_raw(path)
		local f = io.open(path, "r")
		local content = f:read("*all")
		f:close()
		return content
	end

	local function write_list(name, data)
		write_raw(list_path(name), vim.fn.json_encode(data))
	end

	local function read_list(name)
		return vim.fn.json_decode(read_raw(list_path(name)))
	end

	local function buffer_text()
		return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
	end

	local function shows(text, name)
		return text:find(" " .. name .. " (", 1, true) ~= nil
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
		-- save_session would otherwise relink the live tmux window running the tests
		orig_tmux, orig_pane = vim.env.TMUX, vim.env.TMUX_PANE
		vim.env.TMUX, vim.env.TMUX_PANE = nil, nil

		write_list("daily", { _metadata = { created_at = 1 }, todos = {} })
		write_list("alpha", { _metadata = { created_at = 1 }, todos = {}, notes = { { id = "na", title = "alpha note" } } })
		write_list("beta", { _metadata = { created_at = 1, source = "mcp" }, todos = {} })
		write_list("zeta", {
			_metadata = { created_at = 1, source = "user", custom = "keep" },
			todos = {
				{ id = "z1", text = "first", done = false, order_index = 1, tags = { "a" } },
				{ id = "z2", text = "second", done = true, order_index = 2 },
			},
			notes = { { id = "nz", title = "zeta note" } },
			extra = { nested = { a = 1 } },
		})

		for key in pairs(package.loaded) do
			if key == "doit" or key:match("^doit%.") then
				package.loaded[key] = nil
			end
		end
		require("doit").setup({ modules = { todos = { enabled = true } } })
		todos = require("doit.core").get_module("todos")
		source = require("doit.modules.todos.state.source")

		notices = {}
		orig_notify = vim.notify
		vim.notify = function(msg)
			table.insert(notices, msg)
		end
		orig_input = vim.ui.input
		orig_uis = vim.api.nvim_list_uis
		vim.api.nvim_list_uis = function()
			return { { width = 120, height = 40 } }
		end
	end)

	after_each(function()
		pcall(todos.ui.list_manager_window.close_window)
		pcall(vim.cmd, "silent! only")
		vim.notify = orig_notify
		vim.ui.input = orig_input
		vim.api.nvim_list_uis = orig_uis
		vim.fn.stdpath = orig_stdpath
		vim.env.TMUX, vim.env.TMUX_PANE = orig_tmux, orig_pane
		vim.fn.delete(tmpdir, "rf")
	end)

	describe("is_mine", function()
		it("daily is mine with or without metadata", function()
			assert.is_true(source.is_mine("daily", nil))
			assert.is_true(source.is_mine("daily", { source = "mcp" }))
		end)

		it("source user is mine", function()
			assert.is_true(source.is_mine("zeta", { source = "user" }))
		end)

		it("source mcp and unflagged are claude", function()
			assert.is_false(source.is_mine("beta", { source = "mcp" }))
			assert.is_false(source.is_mine("alpha", {}))
			assert.is_false(source.is_mine("alpha", nil))
		end)
	end)

	describe("toggle_list_source", function()
		it("round-trips mine and claude keeping todos, notes and other keys", function()
			local before = read_list("zeta")

			assert.are.equal("mcp", source.toggle_list_source("zeta"))
			local flipped = read_list("zeta")
			assert.are.equal("mcp", flipped._metadata.source)
			assert.is_true(flipped._metadata.updated_at >= os.time() - 5)

			assert.are.equal("user", source.toggle_list_source("zeta"))
			local after = read_list("zeta")
			assert.are.equal("user", after._metadata.source)
			assert.are.equal("keep", after._metadata.custom)
			assert.are.equal(1, after._metadata.created_at)
			assert.are.same(before.todos, after.todos)
			assert.are.same(before.notes, after.notes)
			assert.are.same(before.extra, after.extra)
		end)

		it("flags an unflagged list as mine", function()
			assert.are.equal("user", source.toggle_list_source("alpha"))
			assert.are.equal("user", read_list("alpha")._metadata.source)
		end)

		it("daily is a no-op that reports why", function()
			local before = read_raw(list_path("daily"))
			local result, err = source.toggle_list_source("daily")
			assert.is_nil(result)
			assert.are.equal("daily is permanent; it always counts as yours", err)
			assert.are.equal(before, read_raw(list_path("daily")))
		end)

		it("flipping the active list survives the next save", function()
			todos.state.load_list("zeta")
			source.toggle_list_source("zeta")
			todos.state.save_to_disk()
			assert.are.equal("mcp", read_list("zeta")._metadata.source)
		end)
	end)

	describe("view filter", function()
		it("absent or unknown filter reads as all", function()
			assert.are.equal("all", source.get_filter())
			write_raw(session_path(), '{"source_filter":"bogus"}')
			assert.are.equal("all", source.get_filter())
		end)

		it("cycles all -> mine -> claude -> all and persists each step", function()
			local seen = {}
			for _ = 1, 3 do
				table.insert(seen, source.cycle_filter())
				assert.are.equal(seen[#seen], vim.fn.json_decode(read_raw(session_path())).source_filter)
			end
			assert.are.same({ "mine", "claude", "all" }, seen)
		end)

		it("session writes keep keys owned by tmux and the MCP", function()
			write_raw(session_path(),
				'{"active_list":"daily","sessions":{"s:w":"zeta"},"mcp_key":{"nested":{"a":1}},"empty_obj":{}}')
			source.cycle_filter()
			require("doit.modules.todos.state.session").save_session("alpha")

			local raw = read_raw(session_path())
			local data = vim.fn.json_decode(raw)
			assert.are.equal("mine", data.source_filter)
			assert.are.equal("alpha", data.active_list)
			assert.are.same({ ["s:w"] = "zeta" }, data.sessions)
			assert.are.same({ nested = { a = 1 } }, data.mcp_key)
			assert.is_truthy(raw:find('"empty_obj":%s*{}'))
		end)

		it("filter_lists keeps the current list under any filter", function()
			local lists = todos.state.get_available_lists()
			local names = function(filter, keep)
				return vim.tbl_map(function(l)
					return l.name
				end, source.filter_lists(lists, filter, keep))
			end
			assert.are.same({ "alpha", "beta", "daily", "zeta" }, names("all"))
			assert.are.same({ "daily", "zeta" }, names("mine"))
			assert.are.same({ "alpha", "daily", "zeta" }, names("mine", "alpha"))
			assert.are.same({ "alpha", "beta", "daily" }, names("claude", "daily"))
		end)
	end)

	describe("save path", function()
		it("a load/save cycle keeps _metadata.source", function()
			todos.state.load_list("zeta")
			table.insert(todos.state.todos, { id = "z3", text = "third", done = false, order_index = 3 })
			todos.state.save_to_disk()
			local data = read_list("zeta")
			assert.are.equal("user", data._metadata.source)
			assert.are.equal("keep", data._metadata.custom)
			assert.are.equal(3, #data.todos)
		end)

		it("a failed load does not carry the previous list's source", function()
			todos.state.load_list("zeta")
			write_raw(list_path("broken"), "{not json")
			todos.state.load_list("broken")
			assert.is_nil(todos.state.todo_lists.metadata.source)
		end)

		it("the manager preview leaves the active list's metadata and notes in place", function()
			todos.state.switch_list("zeta")
			todos.ui.list_manager_window.toggle_window()
			todos.state.save_to_disk()
			local data = read_list("zeta")
			assert.are.equal("user", data._metadata.source)
			assert.are.equal("zeta note", data.notes[1].title)
		end)

		it("moving a todo out keeps the source list's notes on disk", function()
			todos.state.load_list("zeta")
			assert.is_true((todos.state.move_todo_to_list("z1", "alpha")))
			local data = read_list("zeta")
			assert.are.equal("zeta note", data.notes[1].title)
			assert.are.equal("user", data._metadata.source)
		end)
	end)

	describe("list manager", function()
		it("renders only lists in the filter plus the current list", function()
			todos.state.switch_list("alpha")
			write_raw(session_path(), '{"active_list":"alpha","source_filter":"mine"}')
			todos.ui.list_manager_window.toggle_window()

			local text = buffer_text()
			assert.is_truthy(text:find("view: mine", 1, true))
			assert.is_true(shows(text, "daily"))
			assert.is_true(shows(text, "zeta"))
			assert.is_true(shows(text, "alpha"))
			assert.is_false(shows(text, "beta"))

			todos.ui.list_manager_window.cycle_view()
			text = buffer_text()
			assert.is_truthy(text:find("view: claude", 1, true))
			assert.is_true(shows(text, "alpha"))
			assert.is_true(shows(text, "beta"))
			assert.is_false(shows(text, "daily"))
			assert.is_false(shows(text, "zeta"))
			assert.are.equal("claude", vim.fn.json_decode(read_raw(session_path())).source_filter)
		end)

		it("s and S are mapped in the manager buffer", function()
			todos.ui.list_manager_window.toggle_window()
			local mapped = {}
			for _, map in ipairs(vim.api.nvim_buf_get_keymap(0, "n")) do
				mapped[map.lhs] = true
			end
			assert.is_true(mapped["s"])
			assert.is_true(mapped["S"])
			assert.is_true(mapped["?"])
		end)

		it("S flips the selected list and refuses daily", function()
			todos.ui.list_manager_window.toggle_window()
			todos.ui.list_manager_window.flip_source()
			assert.are.equal("user", read_list("alpha")._metadata.source)
			assert.are.same({ "alpha: mine" }, notices)

			todos.ui.list_manager_window.close_window()
			write_raw(session_path(), '{"source_filter":"mine"}')
			todos.ui.list_manager_window.toggle_window()
			vim.api.nvim_feedkeys("2", "x", false)
			assert.is_truthy(vim.api.nvim_get_current_line():find("daily", 1, true))
			todos.ui.list_manager_window.flip_source()
			assert.are.equal("daily is permanent; it always counts as yours", notices[#notices])
		end)

		it("create stamps the new list as the user's", function()
			vim.ui.input = function(_, cb)
				cb("fresh")
			end
			todos.ui.list_manager_window.create_new_list()
			local meta = read_list("fresh")._metadata
			assert.are.equal("user", meta.source)
			assert.is_number(meta.created_at)
		end)

		it(":DoItLists create stamps the new list as the user's", function()
			vim.cmd("DoItLists create typed")
			assert.are.equal("user", read_list("typed")._metadata.source)
		end)
	end)

	describe("move-to-list selector", function()
		it("honours the filter and cycles with s", function()
			write_raw(session_path(), '{"source_filter":"mine"}')
			require("doit.ui.list_selector").show_list_selector("zeta", function() end)

			local text = buffer_text()
			assert.is_truthy(text:find("view: mine", 1, true))
			assert.is_truthy(text:find("daily", 1, true))
			assert.is_falsy(text:find("alpha", 1, true))
			assert.is_falsy(text:find("zeta", 1, true))

			vim.api.nvim_feedkeys("s", "x", false)
			text = buffer_text()
			assert.is_truthy(text:find("view: claude", 1, true))
			assert.is_truthy(text:find("alpha", 1, true))
			assert.is_truthy(text:find("beta", 1, true))
			assert.is_falsy(text:find("daily", 1, true))

			vim.api.nvim_feedkeys("S", "x", false)
			assert.are.equal("user", read_list("alpha")._metadata.source)
			assert.is_falsy(buffer_text():find("alpha", 1, true))
			vim.api.nvim_feedkeys("q", "x", false)
		end)
	end)
end)
