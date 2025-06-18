local M = {}
local config

function M.setup()
	local doit = require("doit")
	config = require("doit.config").options

	if not config.development_mode then
		return
	end

	vim.api.nvim_create_user_command("DoitReload", function()
		M.reload()
	end, { desc = "Reload DoIt plugin" })

	vim.api.nvim_create_user_command("DoitAutoReload", function()
		M.toggle_auto_reload()
	end, { desc = "Toggle auto-reload for DoIt plugin" })

	vim.api.nvim_create_user_command("DoitDebug", function()
		M.start_debug_server()
	end, { desc = "Start Lua debug server for Do-It plugin" })

	vim.api.nvim_create_user_command("DoitDebugConnect", function()
		M.start_debug_server_and_connect()
	end, { desc = "Start Lua debug server and connect DAP" })

	vim.api.nvim_create_user_command("DoitDebugStatus", function()
		M.check_dap_status()
	end, { desc = "Check DAP connection status" })

	vim.keymap.set("n", "<leader>osc", function()
		M.start_debug_server_and_connect()
	end, { desc = "Start OSV server and connect DAP" })

	vim.notify("Do-It.nvim development tools enabled", vim.log.levels.INFO)
end

function M.reload()
	for k in pairs(package.loaded) do
		if k:match("^doit") then
			package.loaded[k] = nil
		end
	end

	require("doit")
	vim.notify("Do-It.nvim plugin reloaded", vim.log.levels.INFO)
end

local _auto_reload_group
function M.toggle_auto_reload()
	if _auto_reload_group then
		vim.api.nvim_del_augroup_by_id(_auto_reload_group)
		_auto_reload_group = nil
		vim.notify("Do-It.nvim auto-reload disabled", vim.log.levels.INFO)
	else
		_auto_reload_group = vim.api.nvim_create_augroup("DoitAutoReload", { clear = true })
		vim.api.nvim_create_autocmd("BufWritePost", {
			group = _auto_reload_group,
			pattern = { "**/lua/doit/**/*.lua" },
			callback = function()
				M.reload()
			end,
			desc = "Auto-reload Do-It.nvim plugin on change",
		})
		vim.notify("Do-It.nvim auto-reload enabled", vim.log.levels.INFO)
	end
end

function M.start_debug_server()
	local has_osv, osv = pcall(require, "osv")
	if not has_osv then
		vim.notify(
			"one-small-step-for-vimkind (osv) is not installed. Please install it with your package manager.",
			vim.log.levels.ERROR
		)
		return
	end

	osv.launch({ port = 8086 })
	vim.notify("Debug server started on port 8086", vim.log.levels.INFO)
end

function M.start_debug_server_and_connect()
	local has_osv, osv = pcall(require, "osv")
	if not has_osv then
		vim.notify(
			"one-small-step-for-vimkind (osv) is not installed. Please install it with your package manager.",
			vim.log.levels.ERROR
		)
		return
	end

	osv.launch({ port = 8086 })
	vim.notify("Debug server started on port 8086", vim.log.levels.INFO)

	vim.defer_fn(function()
		local has_dap, dap = pcall(require, "dap")
		if not has_dap then
			vim.notify("nvim-dap is not installed. Please install it with your package manager.", vim.log.levels.ERROR)
			return
		end

		pcall(function()
			dap.continue()
			vim.notify("DAP connected to debug server", vim.log.levels.INFO)
		end)
	end, 500) -- Delay to ensure server is ready
end

function M.check_dap_status()
	local has_dap, dap = pcall(require, "dap")
	if not has_dap then
		vim.notify("nvim-dap is not installed.", vim.log.levels.ERROR)
		return
	end

	local session = dap.session()
	if session then
		vim.notify("DAP is connected to " .. session.config.host .. ":" .. session.config.port, vim.log.levels.INFO)
	else
		vim.notify("DAP is not connected to any debug server", vim.log.levels.WARN)
	end
end

return M
