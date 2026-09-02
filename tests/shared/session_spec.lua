-- session.lua: per-tmux-session link map in session.json.
-- The file is shared with the tmux and MCP surfaces, so save_session must
-- read-merge-write (a wholesale rewrite clobbers other sessions' links).

local session = require("doit.modules.todos.state.session")

describe("session links", function()
	local tmpdir
	local orig_stdpath
	local orig_path

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

	-- fake tmux on PATH answering `display-message -p '#S'` with a fixed name
	local function enter_fake_tmux(name)
		local bindir = tmpdir .. "/bin"
		vim.fn.mkdir(bindir, "p")
		local f = io.open(bindir .. "/tmux", "w")
		f:write("#!/bin/sh\necho " .. name .. "\n")
		f:close()
		os.execute("chmod +x " .. bindir .. "/tmux")
		vim.env.PATH = bindir .. ":" .. orig_path
		vim.env.TMUX = "/tmp/fake-tmux-sock,1,0"
	end

	before_each(function()
		tmpdir = vim.fn.tempname()
		vim.fn.mkdir(tmpdir, "p")
		orig_stdpath = vim.fn.stdpath
		orig_path = vim.env.PATH
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
		vim.fn.stdpath = orig_stdpath
		vim.env.PATH = orig_path
		vim.env.TMUX = nil
		vim.fn.delete(tmpdir, "rf")
	end)

	it("save_session outside tmux preserves other sessions' links", function()
		write_session({ active_list = "work", sessions = { alpha = "play", beta = "other" } })

		session.save_session("daily")

		local data = read_session()
		assert.are.equal("daily", data.active_list)
		assert.are.equal("play", data.sessions.alpha)
		assert.are.equal("other", data.sessions.beta)
	end)

	it("save_session outside tmux adds no link", function()
		write_session({ active_list = "work" })

		session.save_session("daily")

		local data = read_session()
		assert.are.equal("daily", data.active_list)
		assert.is_nil(data.sessions)
	end)

	it("save_session inside tmux writes both the link and the global pointer", function()
		write_session({ active_list = "work", sessions = { beta = "other" } })
		enter_fake_tmux("alpha")

		session.save_session("play")

		local data = read_session()
		assert.are.equal("play", data.active_list)
		assert.are.equal("play", data.sessions.alpha)
		assert.are.equal("other", data.sessions.beta)
	end)

	it("load_session outside tmux returns the global pointer", function()
		write_session({ active_list = "work", sessions = { alpha = "play" } })

		local list, from_link = session.load_session()
		assert.are.equal("work", list)
		assert.is_false(from_link)
	end)

	it("load_session inside tmux prefers the session's link", function()
		write_session({ active_list = "work", sessions = { alpha = "play" } })
		enter_fake_tmux("alpha")

		local list, from_link = session.load_session()
		assert.are.equal("play", list)
		assert.is_true(from_link)
	end)

	it("load_session inside tmux without a link falls back to the global pointer", function()
		write_session({ active_list = "work", sessions = { beta = "play" } })
		enter_fake_tmux("alpha")

		local list, from_link = session.load_session()
		assert.are.equal("work", list)
		assert.is_false(from_link)
	end)

	it("load_session with no session file returns nil", function()
		local list = session.load_session()
		assert.is_nil(list)
	end)

	it("save_session round-trips through load_session inside tmux", function()
		enter_fake_tmux("alpha")

		session.save_session("play")

		local list, from_link = session.load_session()
		assert.are.equal("play", list)
		assert.is_true(from_link)
	end)
end)
