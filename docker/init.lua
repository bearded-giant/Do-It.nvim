-- Minimal init.lua for doit plugin testing

vim.opt.rtp:append("/plugin")

vim.opt.termguicolors = true
vim.opt.mouse = "a"
vim.opt.clipboard = "unnamedplus"

vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Setup DAP
local dap = require("dap")

-- Configure one-small-step-for-vimkind for Lua debugging
dap.adapters.nlua = function(callback, config)
    callback({ type = "server", host = "0.0.0.0", port = 8086 })
end

-- Path mapping configuration - maps the container paths to host paths
-- This is crucial for breakpoints to work correctly
dap.configurations.lua = {
    {
        type = "nlua",
        request = "attach",
        name = "Attach to running Neovim instance",
        host = "0.0.0.0",
        port = 8086,
        pathMappings = {
            ["/plugin"] = "/host-plugin", -- Maps container path to host path
        },
    }
}

-- DAP UI will be configured after plugins are fully loaded
vim.api.nvim_create_autocmd("VimEnter", {
    callback = function()
        -- Only set up DAP UI after all plugins are loaded
        local has_dapui, dapui = pcall(require, "dapui")
        if has_dapui then
            -- Configure DAP-UI to use floating windows that can overlay modal windows
            dapui.setup({
                icons = { expanded = "▾", collapsed = "▸", current_frame = "▸" },
                mappings = {
                    -- Ensure these mappings don't conflict with the plugin
                    expand = { "<CR>", "<2-LeftMouse>" },
                    open = "o",
                    remove = "d",
                    edit = "e",
                    repl = "r",
                    toggle = "t",
                },
                -- Use floating windows for everything to avoid UI conflicts
                layouts = {
                    {
                        elements = {
                            { id = "scopes", size = 0.25 },
                            "breakpoints",
                            "stacks",
                            "watches",
                        },
                        size = 40,
                        position = "left",
                    },
                    {
                        elements = {
                            "repl",
                            "console",
                        },
                        size = 0.25,
                        position = "bottom",
                    },
                },
                floating = {
                    max_height = 0.9,
                    max_width = 0.9,
                    border = "rounded",
                    mappings = {
                        close = { "q", "<Esc>" },
                    },
                },
                windows = { indent = 1 },
                render = {
                    max_type_length = nil,
                },
            })

            -- Create global functions for debugging that can be called from any context
            _G.debug_toggle_ui = function()
                dapui.toggle()
            end

            _G.debug_eval = function(expr)
                dapui.eval(expr)
            end
            
            _G.debug_float_element = function(element)
                dapui.float_element(element)
            end

            -- Function to show variable scopes in a floating window
            _G.debug_show_scopes = function()
                dapui.float_element("scopes", { enter = true })
            end

            -- Emergency force close function
            _G.force_close_dapui = function()
                dapui.close()
            end

            -- Override DAP continue to make it also show scopes in a floating window
            local dap_continue = require("dap").continue
            require("dap").continue = function()
                dap_continue()
                -- Show scopes after a small delay to let the breakpoint hit
                vim.defer_fn(function()
                    _G.debug_show_scopes()
                end, 100)
            end

            -- Make DAP UI auto-open on breakpoint hit rather than session start
            dap.listeners.after.event_initialized["dapui_config"] = function()
                -- Don't open UI automatically on start to avoid fighting with plugin UI
                -- dapui.open()
            end
            
            -- Hook into stopped event to show debug info
            dap.listeners.after.event_stopped["dapui_config"] = function()
                -- Move plugin window when breakpoint hits
                vim.defer_fn(function()
                    local status, doit_ui = pcall(require, "doit.ui.main_window")
                    if status and doit_ui.is_window_open and doit_ui.is_window_open() then
                        -- Make space for debugging by moving the plugin window
                        doit_ui.resize_for_debug()
                    end
                    
                    -- Show scopes in floating window when hitting a breakpoint
                    _G.debug_show_scopes()
                end, 100)
            end
            
            dap.listeners.before.event_terminated["dapui_config"] = function()
                dapui.close()
            end
            
            dap.listeners.before.event_exited["dapui_config"] = function()
                dapui.close()
            end
        else
            vim.notify("DAP UI not available", vim.log.levels.WARN)
        end
    end,
})

-- Define a debugging keymaps group
vim.api.nvim_create_user_command("DebugStart", function()
    require('osv').launch({ host = '0.0.0.0', port = 8086 })
    vim.notify("Debug adapter started on port 8086", vim.log.levels.INFO)
end, { desc = "Start OSV Debug Adapter" })

-- Create user commands for debugging that work even in modal windows
vim.api.nvim_create_user_command("DebugStart", function()
    require('osv').launch({ host = '0.0.0.0', port = 8086 })
    vim.notify("Debug adapter started on port 8086", vim.log.levels.INFO)
end, { desc = "Start OSV Debug Adapter" })

-- Emergency command to restore window after debug
vim.api.nvim_create_user_command("DebugRestoreWindow", function()
    local status, doit_ui = pcall(require, "doit.ui.main_window")
    if status and doit_ui.restore_window then
        doit_ui.restore_window()
        vim.notify("Window position restored", vim.log.levels.INFO)
    end
end, { desc = "Restore doit window position after debugging" })

-- Emergency escape command that closes plugin windows and debugger
vim.api.nvim_create_user_command("DebugEmergencyExit", function()
    -- First try to close the plugin window
    local status, doit_ui = pcall(require, "doit.ui")
    if status and doit_ui.main_window and doit_ui.main_window.close_window then
        doit_ui.main_window.close_window()
    end
    
    -- Then close all DAP UI windows
    if _G.force_close_dapui then
        _G.force_close_dapui()
    end
    
    -- Restore the cursor to a better buffer
    vim.cmd("edit!")
    vim.notify("Emergency exit complete - all windows closed", vim.log.levels.INFO)
end, { desc = "Emergency exit from plugin and debug windows" })

vim.api.nvim_create_user_command("DebugContinue", function()
    require('dap').continue()
end, { desc = "DAP: Continue execution" })

vim.api.nvim_create_user_command("DebugToggleBreakpoint", function()
    require('dap').toggle_breakpoint()
end, { desc = "DAP: Toggle breakpoint" })

vim.api.nvim_create_user_command("DebugStepOver", function()
    require('dap').step_over()
end, { desc = "DAP: Step over" })

vim.api.nvim_create_user_command("DebugStepInto", function()
    require('dap').step_into()
end, { desc = "DAP: Step into" })

vim.api.nvim_create_user_command("DebugStepOut", function()
    require('dap').step_out()
end, { desc = "DAP: Step out" })

vim.api.nvim_create_user_command("DebugShowScopes", function()
    _G.debug_show_scopes()
end, { desc = "DAP: Show variable scopes" })

vim.api.nvim_create_user_command("DebugToggleUI", function()
    _G.debug_toggle_ui()
end, { desc = "DAP: Toggle UI" })

vim.api.nvim_create_user_command("DebugEval", function(opts)
    _G.debug_eval(opts.args)
end, { desc = "DAP: Evaluate expression", nargs = 1 })

vim.api.nvim_create_user_command("DebugShowElement", function(opts)
    _G.debug_float_element(opts.args)
end, { desc = "DAP: Show UI element", nargs = 1, complete = function()
    return { "scopes", "stacks", "breakpoints", "watches", "repl", "console" }
end })

vim.api.nvim_create_user_command("DebugCloseAll", function()
    _G.force_close_dapui()
end, { desc = "DAP: Force close all UI elements" })

-- Standard keymaps that work in normal buffers
vim.api.nvim_set_keymap(
    "n",
    "<leader>ds",
    ":DebugStart<CR>",
    { noremap = true, silent = true, desc = "Start Debug Adapter" }
)

vim.api.nvim_set_keymap("n", "<leader>db", ":DebugToggleBreakpoint<CR>", 
    { noremap = true, silent = true, desc = "DAP: Toggle breakpoint" })
vim.api.nvim_set_keymap("n", "<leader>dc", ":DebugContinue<CR>", 
    { noremap = true, silent = true, desc = "DAP: Continue" })
vim.api.nvim_set_keymap("n", "<leader>dso", ":DebugStepOver<CR>", 
    { noremap = true, silent = true, desc = "DAP: Step over" })
vim.api.nvim_set_keymap("n", "<leader>dsi", ":DebugStepInto<CR>", 
    { noremap = true, silent = true, desc = "DAP: Step into" })
vim.api.nvim_set_keymap("n", "<leader>dx", ":DebugStepOut<CR>", 
    { noremap = true, silent = true, desc = "DAP: Step out" })
vim.api.nvim_set_keymap("n", "<leader>dv", ":DebugShowScopes<CR>", 
    { noremap = true, silent = true, desc = "DAP: Show variables" })
vim.api.nvim_set_keymap("n", "<leader>du", ":DebugToggleUI<CR>", 
    { noremap = true, silent = true, desc = "DAP: Toggle UI" })

-- IMPORTANT: Emergency exit sequence that will work even when UI is stuck
vim.api.nvim_set_keymap("n", "<leader>dX", ":DebugEmergencyExit<CR>", 
    { noremap = true, silent = true, desc = "DAP: Emergency exit (plugin + debugger)" })
    
-- Add command to restore window position
vim.api.nvim_set_keymap("n", "<leader>dr", ":DebugRestoreWindow<CR>", 
    { noremap = true, silent = true, desc = "DAP: Restore plugin window position" })

-- Create terminal-mode mappings for common debug operations
-- These allow controlling debugger even from insert mode
vim.api.nvim_set_keymap("t", "<C-b>", "<C-\\><C-n>:DebugToggleBreakpoint<CR>a", 
    { noremap = true, silent = true, desc = "DAP: Toggle breakpoint" })
vim.api.nvim_set_keymap("t", "<C-c>", "<C-\\><C-n>:DebugContinue<CR>a", 
    { noremap = true, silent = true, desc = "DAP: Continue" })
vim.api.nvim_set_keymap("t", "<C-v>", "<C-\\><C-n>:DebugShowScopes<CR>", 
    { noremap = true, silent = true, desc = "DAP: Show variables" })
vim.api.nvim_set_keymap("t", "<C-x>", "<C-\\><C-n>:DebugCloseAll<CR>", 
    { noremap = true, silent = true, desc = "DAP: Close UI" })

-- Set up Neovim commands for doit....based on my personal preferences
vim.api.nvim_create_user_command("ToDo", function()
	require("doit").toggle_window()
end, { desc = "Toggle doit window" })

-- Ensure the toggle_window function exists
vim.api.nvim_create_autocmd("VimEnter", {
	callback = function()
		if not require("doit").toggle_window then
			require("doit").toggle_window = function()
				require("doit").ui.main_window.toggle_todo_window()
			end
		end
	end,
})

-- print("doit plugin initializing...")

local function test_file_access()
	local test_path = "/data/test_write.txt"

	-- print("Testing file access with: " .. test_path)
	local write_test = io.open(test_path, "w")
	if write_test then
		write_test:write("Test write at " .. os.date())
		write_test:close()
		-- print("✅ Successfully wrote test file")

		local read_test = io.open(test_path, "r")
		if read_test then
			local content = read_test:read("*all")
			read_test:close()
			-- print("✅ Successfully read test file: " .. content)
		else
			print("❌ Failed to read test file")
		end
	else
		print("❌ Failed to write test file")
	end

	-- Check/create the todos file
	local todos_path = "/data/doit_todos.json"
	local todos_file = io.open(todos_path, "r")
	if todos_file then
		local content = todos_file:read("*all")
		todos_file:close()
		-- print("✅ Todos file exists with content length: " .. #content)

		-- Try to append to it
		local append_test = io.open(todos_path, "a")
		if append_test then
			append_test:close()
			-- print("✅ Can write to todos file")
		else
			print("❌ Cannot write to todos file")
		end
	else
		-- print("ℹ️ Todos file not found, creating it")
		-- Create an empty todos file with an empty array
		local create_file = io.open(todos_path, "w")
		if create_file then
			create_file:write("[]")
			create_file:close()
			-- print("✅ Created empty todos file")

			-- Verify it
			local verify = io.open(todos_path, "r")
			if verify then
				local content = verify:read("*all")
				verify:close()
				-- print("✅ Verified todos file with content: " .. content)
			else
				print("❌ Could not verify todos file")
			end
		else
			print("❌ Could not create todos file")
		end
	end
end

test_file_access()

local doit_storage = require("doit.state.storage")
local original_setup = doit_storage.setup

doit_storage.setup = function(M, config)
	original_setup(M, config)

	-- Replace save_to_disk with our own implementation
	M.save_to_disk = function()
		local save_path = "/data/doit_todos.json"
		-- print("Saving todos to: " .. save_path)

		-- Ensure todos is initialized
		if not M.todos then
			print("WARNING: M.todos is nil, initializing empty array")
			M.todos = {}
		end

		-- Convert todos to JSON
		local json_content = vim.fn.json_encode(M.todos)
		print("Encoded " .. #M.todos .. " todos to JSON (length: " .. #json_content .. ")")

		-- Write to file with explicit error handling
		local file, err = io.open(save_path, "w")
		if not file then
			print("ERROR: Failed to open file for writing: " .. (err or "unknown error"))
			return false
		end

		local ok, write_err = pcall(function()
			file:write(json_content)
		end)
		file:close()

		if not ok then
			print("ERROR: Failed to write to file: " .. (write_err or "unknown error"))
			return false
		end

		-- print("✅ Successfully saved todos to " .. save_path)

		-- Verify the file
		local verify_file = io.open(save_path, "r")
		if verify_file then
			local content = verify_file:read("*all")
			verify_file:close()
			-- print("✅ Verified file after save, size: " .. #content .. " bytes")
		else
			print("❌ Could not verify file after save")
		end

		-- Force sync to disk
		os.execute("sync")
		-- print("✅ Forced sync to disk")

		return true
	end

	-- Also override load from disk to be more robust
	M.load_from_disk = function()
		-- Use fixed path directly since config might not be fully initialized yet
		local save_path = "/data/doit_todos.json"
		-- print("Loading todos from: " .. save_path)

		local file = io.open(save_path, "r")
		if not file then
			print("❌ Could not open todos file for reading")
			return
		end

		local content = file:read("*all")
		file:close()

		-- print("Read " .. #content .. " bytes from todos file")

		if content and content ~= "" then
			local ok, result = pcall(vim.fn.json_decode, content)
			if ok and result then
				M.todos = result
				-- print("✅ Successfully loaded " .. #M.todos .. " todos")
			else
				print("❌ Error parsing JSON: " .. (result or "unknown error"))
			end
		else
			-- print("⚠️ Todos file is empty")
			M.todos = {}
		end
	end
end

require("doit").setup({
	save_path = "/data/doit_todos.json",

	timestamp = {
		enabled = false,
	},

	window = {
		width = 140,
		height = 40,
		border = "rounded",
		position = "center",
		padding = {
			top = 1,
			bottom = 1,
			left = 2,
			right = 2,
		},
	},

	formatting = {
		pending = {
			icon = "○",
			format = { "icon", "notes_icon", "text", "due_date", "ect" },
		},
		in_progress = {
			icon = "◐",
			format = { "icon", "text", "due_date", "ect" },
		},
		done = {
			icon = "✓",
			format = { "icon", "notes_icon", "text", "due_date", "ect" },
		},
	},

	quick_keys = true,

	notes = {
		icon = "📓",
	},

	scratchpad = {
		syntax_highlight = "markdown",
	},

	keymaps = {
		toggle_window = "<leader>do",
		new_todo = "i",
		toggle_todo = "x",
		delete_todo = "d",
		delete_completed = "D",
		delete_confirmation = "<CR>",
		close_window = "<Esc>",
		undo_delete = "u",
		add_due_date = "H",
		remove_due_date = "r",
		toggle_help = "?",
		toggle_tags = "t",
		toggle_priority = "<Space>",
		clear_filter = "c",
		edit_todo = "e",
		edit_tag = "e",
		edit_priorities = "p",
		delete_tag = "d",
		search_todos = "/",
		add_time_estimation = "T",
		remove_time_estimation = "R",
		import_todos = "I",
		export_todos = "E",
		remove_duplicates = "<leader>D",
		open_todo_scratchpad = "<leader>p",
	},

	calendar = {
		language = "en",
		icon = "",
		keymaps = {
			previous_day = "h",
			next_day = "l",
			previous_week = "k",
			next_week = "j",
			previous_month = "H",
			next_month = "L",
			select_day = "<CR>",
			close_calendar = "q",
		},
	},

	priorities = {
		{
			name = "important",
			weight = 4,
		},
		{
			name = "urgent",
			weight = 2,
		},
	},
	priority_groups = {
		high = {
			members = { "important", "urgent" },
			color = nil,
			hl_group = "DiagnosticError",
		},
		medium = {
			members = { "important" },
			color = nil,
			hl_group = "DiagnosticWarn",
		},
		low = {
			members = { "urgent" },
			color = nil,
			hl_group = "DiagnosticInfo",
		},
	},
	hour_score_value = 1 / 8,
})

-- For debugging
vim.opt.verbosefile = "/tmp/nvim.log"
