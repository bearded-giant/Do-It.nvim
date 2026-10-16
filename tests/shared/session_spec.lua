-- session.lua: per-tmux-window list links. The live link is the window's
-- @doit-window-list option; session.json's sessions map, keyed
-- "<session>:<window>", is the copy a tmux restart restores from. The file is
-- shared with the tmux and MCP surfaces, so save_session must read-merge-write
-- (a wholesale rewrite clobbers other windows' links). A real tmux server on a
-- private socket stands in for the user's.

local session = require("doit.modules.todos.state.session")

describe("session links", function()
	local tmpdir
	local orig_stdpath
	local sock

	local function T(...)
		return vim.trim(vim.fn.system(vim.list_extend({ "tmux", "-S", sock }, { ... })))
	end

	local function start_tmux()
		T("-f", "/dev/null", "new-session", "-d", "-s", "s", "-n", "alpha", "-x", "80", "-y", "24")
		T("new-window", "-d", "-t", "s:", "-n", "beta")
		vim.env.TMUX = sock .. "," .. T("display", "-p", "#{pid}") .. ",0"
	end

	local function enter(window)
		vim.env.TMUX_PANE = T("display", "-p", "-t", "s:" .. window, "#{pane_id}")
	end

	local function live(window)
		return T("display", "-p", "-t", "s:" .. window, "#{@doit-window-list}")
	end

	local function session_file()
		return tmpdir .. "/doit/session.json"
	end

	local function write_session(tbl)
		vim.fn.mkdir(tmpdir .. "/doit", "p")
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

	before_each(function()
		tmpdir = vim.fn.tempname()
		vim.fn.mkdir(tmpdir, "p")
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
	end)

	after_each(function()
		vim.fn.system({ "tmux", "-S", sock, "kill-server" })
		os.remove(sock)
		vim.fn.stdpath = orig_stdpath
		vim.env.TMUX = nil
		vim.env.TMUX_PANE = nil
		vim.fn.delete(tmpdir, "rf")
	end)

	it("save_session outside tmux preserves other windows' links", function()
		write_session({ active_list = "work", sessions = { ["s:alpha"] = "play", ["s:beta"] = "other" } })

		session.save_session("daily")

		local data = read_session()
		assert.are.equal("daily", data.active_list)
		assert.are.equal("play", data.sessions["s:alpha"])
		assert.are.equal("other", data.sessions["s:beta"])
	end)

	it("save_session outside tmux adds no link", function()
		write_session({ active_list = "work" })

		session.save_session("daily")

		local data = read_session()
		assert.are.equal("daily", data.active_list)
		assert.is_nil(data.sessions)
	end)

	it("save_session inside tmux writes the live link, its persisted copy and the global pointer", function()
		write_session({ active_list = "work", sessions = { ["s:beta"] = "other" } })
		start_tmux()
		enter("alpha")

		session.save_session("play")

		local data = read_session()
		assert.are.equal("play", data.active_list)
		assert.are.equal("play", data.sessions["s:alpha"])
		assert.are.equal("other", data.sessions["s:beta"])
		assert.are.equal("play", live("alpha"))
		assert.are.equal("", live("beta"))
	end)

	it("load_session outside tmux returns the global pointer", function()
		write_session({ active_list = "work", sessions = { ["s:alpha"] = "play" } })

		local list, from_link = session.load_session()
		assert.are.equal("work", list)
		assert.is_false(from_link)
	end)

	it("load_session inside tmux returns the window's live link", function()
		write_session({ active_list = "work" })
		start_tmux()
		T("set-option", "-wq", "-t", "s:alpha", "@doit-window-list", "play")
		enter("alpha")

		local list, from_link = session.load_session()
		assert.are.equal("play", list)
		assert.is_true(from_link)
	end)

	it("the live link follows a renamed window", function()
		write_session({ active_list = "work" })
		start_tmux()
		enter("alpha")
		session.save_session("play")
		T("rename-window", "-t", "s:alpha", "renamed")

		local list, from_link = session.load_session()
		assert.are.equal("play", list)
		assert.is_true(from_link)
	end)

	it("after a tmux restart the persisted link comes back into the window", function()
		write_session({ active_list = "work", sessions = { ["s:alpha"] = "play" } })
		start_tmux()
		enter("alpha")

		local list, from_link = session.load_session()
		assert.are.equal("play", list)
		assert.is_true(from_link)
		assert.are.equal("play", live("alpha"))
	end)

	it("a persisted link another same-named live window holds is not taken", function()
		write_session({ active_list = "work", sessions = { ["s:alpha"] = "play" } })
		start_tmux()
		T("new-window", "-d", "-t", "s:", "-n", "alpha")
		local first = T("display", "-p", "-t", "s:^", "#{window_id}")
		T("set-option", "-wq", "-t", first, "@doit-window-list", "play")
		T("set-option", "-wq", "-t", first, "@doit-window-key", "s:alpha")
		vim.env.TMUX_PANE = T("display", "-p", "-t", "s:$", "#{pane_id}")

		local list, from_link = session.load_session()
		assert.is_nil(list)
		assert.is_false(from_link)
	end)

	it("load_session inside tmux without a link returns nil, never the global pointer", function()
		write_session({ active_list = "work", sessions = { ["s:beta"] = "play" } })
		start_tmux()
		enter("alpha")

		local list, from_link = session.load_session()
		assert.is_nil(list)
		assert.is_false(from_link)
	end)

	it("load_session ignores a legacy session-name link", function()
		write_session({ active_list = "work", sessions = { s = "play" } })
		start_tmux()
		enter("alpha")

		local list, from_link = session.load_session()
		assert.is_nil(list)
		assert.is_false(from_link)
	end)

	it("load_session with no session file returns nil", function()
		local list = session.load_session()
		assert.is_nil(list)
	end)

	it("relink_list moves live and persisted links to the new list name", function()
		write_session({ active_list = "work", sessions = { ["s:beta"] = "other" } })
		start_tmux()
		enter("alpha")
		session.save_session("play")

		session.relink_list("play", "renamed")

		local data = read_session()
		assert.are.equal("renamed", data.sessions["s:alpha"])
		assert.are.equal("other", data.sessions["s:beta"])
		assert.are.equal("renamed", live("alpha"))
	end)
end)
