-- window links in the nvim list views: rows show the tmux windows linked to each
-- list ("[sess:win, ...]", dead windows dimmed) and mark the list linked here.
-- Enter views without touching links; l links this window and the global pointer,
-- g sets the global pointer only, u unlinks. Mirrors tmux/scripts/todo-list-manager.sh.
-- A real tmux server on a private socket stands in for the user's.

local session = require("doit.modules.todos.state.session")

describe("window links", function()
	local tmpdir, orig_stdpath, orig_notify, orig_uis, sock
	local notices

	local function T(...)
		return vim.trim(vim.fn.system(vim.list_extend({ "tmux", "-S", sock }, { ... })))
	end

	-- this nvim sits in window s:alpha; s:beta is another live window
	local function enter_tmux()
		T("-f", "/dev/null", "new-session", "-d", "-s", "s", "-n", "alpha", "-x", "80", "-y", "24")
		T("new-window", "-d", "-t", "s:", "-n", "beta")
		vim.env.TMUX = sock .. "," .. T("display", "-p", "#{pid}") .. ",0"
		vim.env.TMUX_PANE = T("display", "-p", "-t", "s:alpha", "#{pane_id}")
	end

	local function live(window)
		return T("display", "-p", "-t", "s:" .. window, "#{@doit-window-list}")
	end

	local function session_file()
		return tmpdir .. "/doit/session.json"
	end

	local function write_session(tbl)
		local f = io.open(session_file(), "w")
		f:write(vim.fn.json_encode(tbl))
		f:close()
	end

	local function read_session()
		local f = io.open(session_file(), "r")
		local content = f:read("*all")
		f:close()
		return vim.fn.json_decode(content)
	end

	local function write_list(name)
		local f = io.open(tmpdir .. "/doit/lists/" .. name .. ".json", "w")
		f:write('{"todos": [], "_metadata": {"created_at": 1}}')
		f:close()
	end

	local function buffer_lines()
		return vim.api.nvim_buf_get_lines(0, 0, -1, false)
	end

	local function row(name)
		for _, line in ipairs(buffer_lines()) do
			if line:find("%] " .. vim.pesc(name) .. " ") then
				return line
			end
		end
	end

	local function press(keys)
		vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "x", false)
	end

	local function select_row(name)
		press(row(name):match("%[(%d)%]"))
	end

	before_each(function()
		tmpdir = vim.fn.tempname()
		vim.fn.mkdir(tmpdir .. "/doit/lists", "p")
		sock = "/tmp/doit-spec-" .. vim.fn.getpid() .. "-" .. math.random(1000000) .. ".sock"
		orig_stdpath = vim.fn.stdpath
		vim.fn.stdpath = function(what)
			if what == "data" then
				return tmpdir
			end
			return orig_stdpath(what)
		end
		vim.env.TMUX = nil
		vim.env.TMUX_PANE = nil
		notices = {}
		orig_notify = vim.notify
		vim.notify = function(msg)
			table.insert(notices, msg)
		end
		orig_uis = vim.api.nvim_list_uis
		vim.api.nvim_list_uis = function()
			return { { width = 160, height = 40 } }
		end
	end)

	after_each(function()
		vim.fn.system({ "tmux", "-S", sock, "kill-server" })
		os.remove(sock)
		vim.notify = orig_notify
		vim.api.nvim_list_uis = orig_uis
		vim.fn.stdpath = orig_stdpath
		vim.env.TMUX = nil
		vim.env.TMUX_PANE = nil
		vim.fn.delete(tmpdir, "rf")
	end)

	describe("session", function()
		it("links_by_list is nil outside tmux", function()
			write_session({ active_list = "work", sessions = { ["s:alpha"] = "play" } })
			assert.is_nil(session.links_by_list())
			assert.is_nil(session.window_key())
		end)

		it("links_by_list groups persisted links by list, live and dead, and names the list linked here", function()
			write_session({
				active_list = "work",
				sessions = { ["s:beta"] = "play", ["s:gone"] = "play", ["s:alpha"] = "work" },
			})
			enter_tmux()
			T("set-option", "-wq", "-t", "s:alpha", "@doit-window-list", "work")

			local by_list, here = session.links_by_list()

			assert.are.same({ { key = "s:beta", live = true }, { key = "s:gone", live = false } }, by_list.play)
			assert.are.same({ { key = "s:alpha", live = true } }, by_list.work)
			assert.is_nil(by_list.daily)
			assert.are.equal("work", here)
			assert.are.equal("s:alpha", session.window_key())
		end)

		it("an unlinked window has no list here", function()
			write_session({ active_list = "work", sessions = { ["s:beta"] = "play" } })
			enter_tmux()

			local by_list, here = session.links_by_list()
			assert.are.equal(1, #by_list.play)
			assert.is_nil(here)
		end)

		it("set_global moves only the global pointer", function()
			write_session({ active_list = "work", sessions = { ["s:alpha"] = "play" } })
			enter_tmux()
			T("set-option", "-wq", "-t", "s:alpha", "@doit-window-list", "play")

			session.set_global("other")

			local data = read_session()
			assert.are.equal("other", data.active_list)
			assert.are.equal("play", data.sessions["s:alpha"])
			assert.are.equal("play", live("alpha"))
		end)

		it("unlink_window drops this window's live and persisted link, keeps the rest", function()
			write_session({ active_list = "work", sessions = { ["s:alpha"] = "play", ["s:beta"] = "other" } })
			enter_tmux()
			session.save_session("play")

			assert.are.equal("s:alpha", session.unlink_window())

			local data = read_session()
			assert.is_nil(data.sessions["s:alpha"])
			assert.are.equal("other", data.sessions["s:beta"])
			assert.are.equal("play", data.active_list)
			assert.are.equal("", live("alpha"))
		end)

		it("unlink_window outside tmux touches nothing", function()
			write_session({ active_list = "work", sessions = { ["s:alpha"] = "play" } })
			assert.is_nil(session.unlink_window())
			assert.are.equal("play", read_session().sessions["s:alpha"])
		end)
	end)

	describe("link_tags", function()
		local link_tags = require("doit.modules.todos.ui.list_manager_window").link_tags

		it("renders nothing without links (outside tmux)", function()
			assert.are.same({ "", {} }, { link_tags("play", nil, nil) })
		end)

		it("marks the list linked here and dims dead windows", function()
			local links = { play = { { key = "s:beta", live = true }, { key = "s:gone", live = false } } }
			local text, spans = link_tags("play", links, "play")

			assert.are.equal(" [here] [s:beta, s:gone]", text)
			assert.are.same({
				{ 1, 7, "DiagnosticWarn" },
				{ 9, 15, "DiagnosticWarn" },
				{ 17, 23, "Comment" },
			}, spans)
			assert.are.equal("[here]", text:sub(2, 7))
			assert.are.equal("s:beta", text:sub(10, 15))
			assert.are.equal("s:gone", text:sub(18, 23))
		end)
	end)

	describe("list views", function()
		local todos

		local function setup_plugin()
			for _, name in ipairs({ "daily", "work", "play" }) do
				write_list(name)
			end
			for key in pairs(package.loaded) do
				if key == "doit" or key:match("^doit%.") then
					package.loaded[key] = nil
				end
			end
			require("doit").setup({ modules = { todos = { enabled = true } } })
			todos = require("doit.core").get_module("todos")
			todos.state.load_list("daily")
		end

		after_each(function()
			if todos then
				pcall(todos.ui.list_manager_window.close_window)
			end
			pcall(vim.cmd, "silent! only")
		end)

		describe("inside tmux", function()
			before_each(function()
				write_session({ active_list = "work", sessions = { ["s:beta"] = "play", ["s:gone"] = "play" } })
				enter_tmux()
				setup_plugin()
				-- setup reloaded the modules; the spec-level session is stale
				session = require("doit.modules.todos.state.session")
			end)

			it("l, g and u are mapped in the manager buffer", function()
				todos.ui.list_manager_window.toggle_window()
				local mapped = {}
				for _, map in ipairs(vim.api.nvim_buf_get_keymap(0, "n")) do
					mapped[map.lhs] = true
				end
				assert.is_true(mapped["l"])
				assert.is_true(mapped["g"])
				assert.is_true(mapped["u"])
			end)

			it("rows show linked windows and the list linked here", function()
				session.save_session("work")
				todos.ui.list_manager_window.toggle_window()

				assert.is_truthy(row("play"):find(" [s:beta, s:gone]", 1, true))
				assert.is_truthy(row("work"):find(" [here] [s:alpha]", 1, true))
				assert.is_falsy(row("daily"):find("s:", 1, true))
				assert.is_falsy(row("daily"):find("[here]", 1, true))
				assert.is_falsy(row("play"):find("[here]", 1, true))
			end)

			it("Enter opens the list without touching any link or the global pointer", function()
				todos.ui.list_manager_window.toggle_window()
				select_row("play")
				press("<CR>")

				assert.are.equal("play", todos.state.todo_lists.active)
				local data = read_session()
				assert.are.equal("work", data.active_list)
				assert.is_nil(data.sessions["s:alpha"])
				assert.are.equal("", live("alpha"))
			end)

			it("l links this window and sets the global pointer", function()
				todos.ui.list_manager_window.toggle_window()
				select_row("play")
				press("l")

				assert.are.equal("play", todos.state.todo_lists.active)
				local data = read_session()
				assert.are.equal("play", data.active_list)
				assert.are.equal("play", data.sessions["s:alpha"])
				assert.are.equal("play", live("alpha"))
			end)

			it("g sets the global pointer only", function()
				todos.ui.list_manager_window.toggle_window()
				select_row("play")
				press("g")

				local data = read_session()
				assert.are.equal("play", data.active_list)
				assert.is_nil(data.sessions["s:alpha"])
				assert.are.equal("", live("alpha"))
				assert.are.equal("daily", todos.state.todo_lists.active)
			end)

			it("u unlinks this window and drops the here marker", function()
				session.save_session("work")
				todos.ui.list_manager_window.toggle_window()
				assert.is_truthy(row("work"):find("[here]", 1, true))

				press("u")

				local data = read_session()
				assert.is_nil(data.sessions["s:alpha"])
				assert.are.equal("play", data.sessions["s:beta"])
				assert.are.equal("", live("alpha"))
				assert.is_falsy(row("work"):find("[here]", 1, true))
				assert.are.equal("Unlinked window 's:alpha'", notices[#notices])
			end)

			it("the move picker shows the link column", function()
				session.save_session("work")
				require("doit.ui.list_selector").show_list_selector("daily", function() end)

				local text = table.concat(buffer_lines(), "\n")
				assert.is_truthy(text:find("play (0) [s:beta, s:gone]", 1, true))
				assert.is_truthy(text:find("work (0) [here] [s:alpha]", 1, true))
				press("q")
			end)
		end)

		describe("outside tmux", function()
			before_each(function()
				write_session({ active_list = "work", sessions = { ["s:beta"] = "play" } })
				setup_plugin()
				session = require("doit.modules.todos.state.session")
			end)

			it("rows carry no link column or here marker", function()
				todos.ui.list_manager_window.toggle_window()
				assert.is_falsy(row("play"):find("s:beta", 1, true))
				assert.is_falsy(table.concat(buffer_lines(), "\n"):find("[here]", 1, true))
			end)

			it("l and u only notify; g still sets the global pointer", function()
				todos.ui.list_manager_window.toggle_window()
				select_row("play")

				press("l")
				assert.are.equal("Not in a tmux window; nothing to link", notices[#notices])
				press("u")
				assert.are.equal("Not in a tmux window; nothing to unlink", notices[#notices])
				local data = read_session()
				assert.are.equal("work", data.active_list)
				assert.are.equal("play", data.sessions["s:beta"])
				assert.are.equal("daily", todos.state.todo_lists.active)

				press("g")
				assert.are.equal("play", read_session().active_list)
			end)

			it("the move picker carries no link column", function()
				require("doit.ui.list_selector").show_list_selector("daily", function() end)
				assert.is_falsy(table.concat(buffer_lines(), "\n"):find("s:beta", 1, true))
				press("q")
			end)
		end)
	end)
end)
