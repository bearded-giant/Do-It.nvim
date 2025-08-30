local M = {}

M.version = "2.0.0"

function M.setup(opts)
	opts = opts or {}

	if not opts.modules then
		opts.modules = {}
	end

	-- Setup the global config with the full options
	require("doit.config").setup(opts)

	M.core = require("doit.core").setup(opts)

	if M.core and not M.core.ui then
		M.core.ui = require("doit.core.ui").setup()
	end

	if M.core and M.core.registry then
		if opts.plugins and opts.plugins.auto_discover then
			M.core.registry.discover()
		end
	end

	if opts.plugins and opts.plugins.auto_discover then
		local plugins = require("doit.core.plugins")
		local discovered = plugins.discover_modules()

		for _, name in ipairs(discovered) do
			local module_opts = opts.modules[name] or {}
			if module_opts.enabled ~= false then
				M.load_module(name, module_opts)
			end
		end
	end

	for name, module_opts in pairs(opts.modules) do
		if module_opts.enabled ~= false and not M[name] then
			M.load_module(name, module_opts)
		end
	end

	-- Legacy behavior: Auto-load core modules for backwards compatibility
	if not M.todos and (not opts.modules or (opts.modules.todos and opts.modules.todos.enabled ~= false)) then
		M.load_module("todos", (opts.modules and opts.modules.todos) or {})
	end

	if not M.notes and (not opts.modules or (opts.modules.notes and opts.modules.notes.enabled ~= false)) then
		M.load_module("notes", (opts.modules and opts.modules.notes) or {})
	end

	-- Backwards compatibility: expose module APIs at root level
	M.state = M.todos and M.todos.state or {}
	M.ui = {}

	if M.todos then
		for name, func in pairs(M.todos.state) do
			if type(func) == "function" and not M.state[name] then
				M.state[name] = func
			end
		end

		for name, component in pairs(M.todos.ui) do
			M.ui[name] = component
		end
	end

	if M.notes then
		M.ui.notes_window = M.notes.ui.notes_window
	end

	M.lualine = require("doit.lualine")

	M.register_module_commands()

	function M.show_dashboard()
		local dashboard_buf = vim.api.nvim_create_buf(false, true)
		local width = 70
		local height = 40
		local ui = vim.api.nvim_list_uis()[1]
		local row = math.floor((ui.height - height) / 2)
		local col = math.floor((ui.width - width) / 2)

		local dashboard_win = vim.api.nvim_open_win(dashboard_buf, true, {
			relative = "editor",
			row = row,
			col = col,
			width = width,
			height = height,
			style = "minimal",
			border = "rounded",
			title = " DoIt Dashboard ",
			title_pos = "center",
		})

		local content = {
			"",
			"          ██████╗  ██████╗     ██╗████████╗",
			"          ██╔══██╗██╔═══██╗    ██║╚══██╔══╝",
			"          ██║  ██║██║   ██║    ██║   ██║   ",
			"          ██║  ██║██║   ██║    ██║   ██║   ",
			"          ██████╔╝╚██████╔╝    ██║   ██║   ",
			"          ╚═════╝  ╚═════╝     ╚═╝   ╚═╝   ",
			"",
			"",
			"ver " .. M.version,
			"",
		}

		local registry_modules = {}
		if M.core and M.core.registry then
			registry_modules = M.core.registry.list()
		end

		if #registry_modules > 0 then
			table.insert(content, "  Registered Modules:")
			for _, module in ipairs(registry_modules) do
				local version = module.version and (" (v" .. module.version .. ")") or ""
				local author = module.author and (" by " .. module.author) or ""
				local custom = module.custom and " [custom]" or ""
				table.insert(content, "  • " .. module.name .. version .. custom .. author)
			end
		else
			table.insert(content, "  Loaded Modules:")
			for name, module in pairs(M) do
				if type(module) == "table" and module.version then
					table.insert(content, "  • " .. name .. " (v" .. module.version .. ")")
				end
			end
		end

		table.insert(content, "")

		if M.todos then
			if M.todos.state.todo_lists then
				local active_list = M.todos.state.todo_lists.active or "default"
				local todo_count = #(M.todos.state.todos or {})
				local lists = M.todos.state.get_available_lists()
				local list_count = #lists

				table.insert(content, "  Todo Lists: " .. list_count)
				table.insert(content, "  Active List: " .. active_list)
				table.insert(content, "  Todo Count: " .. todo_count)
			else
				table.insert(content, "  Todo Count: " .. #(M.todos.state.todos or {}))
			end
		end

		table.insert(content, "")
		table.insert(content, "  Available Commands:")
		table.insert(content, "  • :DoIt - Open main todo window")

		if M.todos then
			table.insert(content, "  • :DoItList - Open quick todo list")
			table.insert(content, "  • :DoItLists - Manage todo lists")
		end

		if M.notes then
			table.insert(content, "  • :DoItNotes - Open notes interface")
		end

		if M.core and M.core.registry then
			table.insert(content, "")
			table.insert(content, "  Plugin Management Commands:")
			table.insert(content, "  • :DoItPlugins list - List available plugins")
			table.insert(content, "  • :DoItPlugins info <name> - Show plugin details")
			table.insert(content, "  • :DoItPlugins install <name> <path> - Install custom plugin")
			table.insert(content, "  • :DoItPlugins discover - Discover new plugins")
		end

		table.insert(content, "")
		table.insert(content, "  Press 'q' to close")

		vim.api.nvim_buf_set_lines(dashboard_buf, 0, -1, false, content)
		vim.api.nvim_buf_set_option(dashboard_buf, "modifiable", false)

		vim.keymap.set("n", "q", function()
			vim.api.nvim_win_close(dashboard_win, true)
		end, { buffer = dashboard_buf, nowait = true })
	end

	return M
end

function M.register_module_commands()
	-- Note: Module commands are now registered by core.register_module()
	-- This function only registers fallback commands if modules aren't loaded
	local commands = {}
	
	-- Only register DoIt if todos module hasn't registered it
	if not (M.todos and M.todos.commands and M.todos.commands.DoIt) then
		commands.DoIt = {
			callback = function()
				if M.todos and M.todos.ui and M.todos.ui.main_window then
					M.todos.ui.main_window.toggle_todo_window()
				elseif M.ui and M.ui.main_window then
					M.ui.main_window.toggle_todo_window()
				else
					vim.notify("Todo module not available", vim.log.levels.ERROR)
				end
			end,
			opts = {
				desc = "Toggle todo window",
			},
		}
	end
	
	-- Note: Keeping this structure to check for other commands
	
	-- Only register DoItList if todos module hasn't registered it
	if not (M.todos and M.todos.commands and M.todos.commands.DoItList) then
		commands.DoItList = {
			callback = function()
				if M.todos and M.todos.ui and M.todos.ui.list_window then
					M.todos.ui.list_window.toggle_list_window()
				elseif M.ui and M.ui.list_window then
					M.ui.list_window.toggle_list_window()
				else
					vim.notify("Todo module not available", vim.log.levels.ERROR)
				end
			end,
			opts = {
				desc = "Toggle todo list window",
			},
		}
	end
	
	-- Only register DoItNotes if notes module hasn't registered it
	if not (M.notes and M.notes.commands and M.notes.commands.DoItNotes) then
		commands.DoItNotes = {
			callback = function()
				if M.notes and M.notes.ui and M.notes.ui.notes_window then
					M.notes.ui.notes_window.toggle_notes_window()
				elseif M.ui and M.ui.notes_window then
					M.ui.notes_window.toggle_notes_window()
				else
					vim.notify("Notes module not available", vim.log.levels.ERROR)
				end
			end,
			opts = {
				desc = "Toggle notes window",
			},
		}
	end
	
	-- Only register DoItLists if todos module hasn't registered it  
	if not (M.todos and M.todos.commands and M.todos.commands.DoItLists) then
		commands.DoItLists = {
			callback = function()
				if M.todos and M.todos.ui and M.todos.ui.list_manager_window then
					M.todos.ui.list_manager_window.toggle_window()
				else
					vim.notify("List manager not available", vim.log.levels.ERROR)
				end
			end,
			opts = {
				desc = "Manage todo lists",
			},
		}
	end

	for name, cmd in pairs(commands) do
		local cmd_list = vim.api.nvim_get_commands({})
		local exists = cmd_list[name] ~= nil

		if not exists then
			pcall(vim.api.nvim_create_user_command, name, cmd.callback, cmd.opts or {})
		end
	end
end

function M.load_module(name, opts)
	local core = M.core
	local registry = core and core.registry

	if registry and registry.is_registered(name) then
		local module, err = registry.initialize_module(name, opts)
		if module then
			M[name] = module
			return module
		else
			vim.notify(
				"Do-It.nvim: Failed to load module '" .. name .. "': " .. (err or "Unknown error"),
				vim.log.levels.WARN
			)
			return nil
		end
	end

	local success, module = pcall(require, "doit.modules." .. name)

	if success and module then
		if registry then
			local metadata = module.metadata
				or {
					name = name,
					path = "doit.modules." .. name,
					version = module.version,
				}
			registry.register(name, metadata)
		end

		M[name] = module.setup(opts)
		return M[name]
	else
		vim.notify("Do-It.nvim: Failed to load module '" .. name .. "'", vim.log.levels.WARN)
		return nil
	end
end

return M

