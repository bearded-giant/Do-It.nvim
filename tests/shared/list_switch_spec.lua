-- storage.load_list runs for startup restore, previews and cross-list moves;
-- only switch_list may write the tmux window link. A restore that persisted
-- the global fallback is how unrelated tmux sessions ended up linked to one list.

describe("list switch persistence", function()
	local tmpdir, orig_stdpath, state, sock

	local function T(...)
		return vim.trim(vim.fn.system(vim.list_extend({ "tmux", "-S", sock }, { ... })))
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

	local function write_list(name)
		vim.fn.mkdir(tmpdir .. "/doit/lists", "p")
		local f = io.open(tmpdir .. "/doit/lists/" .. name .. ".json", "w")
		f:write('{"todos": [], "_metadata": {}}')
		f:close()
	end

	-- a real tmux server on a private socket; this nvim sits in window s:alpha
	local function enter_tmux()
		sock = "/tmp/doit-spec-" .. vim.fn.getpid() .. "-" .. math.random(1000000) .. ".sock"
		T("-f", "/dev/null", "new-session", "-d", "-s", "s", "-n", "alpha", "-x", "80", "-y", "24")
		T("new-window", "-d", "-t", "s:", "-n", "beta")
		vim.env.TMUX = sock .. "," .. T("display", "-p", "#{pid}") .. ",0"
		vim.env.TMUX_PANE = T("display", "-p", "-t", "s:alpha", "#{pane_id}")
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
		enter_tmux()

		-- alpha is unlinked; the global pointer names an existing list
		write_session({ active_list = "work", sessions = { ["s:beta"] = "play" } })
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
		vim.fn.system({ "tmux", "-S", sock, "kill-server" })
		os.remove(sock)
		vim.fn.stdpath = orig_stdpath
		vim.env.TMUX = nil
		vim.env.TMUX_PANE = nil
		vim.fn.delete(tmpdir, "rf")
	end)

	it("startup restore of an unlinked window lands on daily and writes no link", function()
		state.load_from_disk()

		assert.are.equal("daily", state.todo_lists.active)
		local data = read_session()
		assert.is_nil(data.sessions["s:alpha"])
		assert.are.equal("play", data.sessions["s:beta"])
		assert.are.equal("", T("display", "-p", "-t", "s:alpha", "#{@doit-window-list}"))
		assert.are.equal("work", data.active_list)
	end)

	it("load_list alone never touches session.json", function()
		state.load_list("play")

		local data = read_session()
		assert.is_nil(data.sessions["s:alpha"])
		assert.are.equal("work", data.active_list)
	end)

	it("switch_list links this window and moves the global pointer", function()
		local ok = state.switch_list("play")

		assert.is_true(ok)
		local data = read_session()
		assert.are.equal("play", data.sessions["s:alpha"])
		assert.are.equal("play", data.sessions["s:beta"])
		assert.are.equal("play", data.active_list)
		assert.are.equal("play", T("display", "-p", "-t", "s:alpha", "#{@doit-window-list}"))
	end)
end)
