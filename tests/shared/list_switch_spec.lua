-- storage.load_list runs for startup restore, previews and cross-list moves;
-- only switch_list may write the tmux session link. A restore that persisted
-- the global fallback is how unrelated tmux sessions ended up linked to one list.

describe("list switch persistence", function()
	local tmpdir, orig_stdpath, orig_path, state

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

	local function write_list(name)
		vim.fn.mkdir(tmpdir .. "/doit/lists", "p")
		local f = io.open(tmpdir .. "/doit/lists/" .. name .. ".json", "w")
		f:write('{"todos": [], "_metadata": {}}')
		f:close()
	end

	-- fake tmux on PATH answering every display-message with a fixed session name
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
		vim.env.TMUX_PANE = nil
		enter_fake_tmux("alpha")

		-- alpha is unlinked; the global pointer names an existing list
		write_session({ active_list = "work", sessions = { beta = "play" } })
		write_list("work")
		write_list("play")

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
		vim.env.PATH = orig_path
		vim.env.TMUX = nil
		vim.fn.delete(tmpdir, "rf")
	end)

	it("startup restore of the global fallback writes no link for this session", function()
		state.load_from_disk()

		assert.are.equal("work", state.todo_lists.active)
		local data = read_session()
		assert.is_nil(data.sessions.alpha)
		assert.are.equal("play", data.sessions.beta)
		assert.are.equal("work", data.active_list)
	end)

	it("load_list alone never touches session.json", function()
		state.load_list("play")

		local data = read_session()
		assert.is_nil(data.sessions.alpha)
		assert.are.equal("work", data.active_list)
	end)

	it("switch_list links this session and moves the global pointer", function()
		local ok = state.switch_list("play")

		assert.is_true(ok)
		local data = read_session()
		assert.are.equal("play", data.sessions.alpha)
		assert.are.equal("play", data.sessions.beta)
		assert.are.equal("play", data.active_list)
	end)
end)
