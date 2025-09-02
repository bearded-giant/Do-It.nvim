-- Full framework init.lua for Docker interactive environment
vim.opt.rtp:append("/plugin")

vim.opt.termguicolors = true
vim.opt.mouse = "a"
vim.opt.clipboard = "unnamedplus"

vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Set up oil.nvim for file navigation
require("oil").setup({
	keymaps = {
		["<Esc>"] = "actions.close",
	},
})
vim.keymap.set("n", "-", "<CMD>Oil<CR>", { desc = "Open parent directory" })

-- Create necessary directories for data persistence
local function ensure_directories()
	vim.fn.mkdir("/data/doit", "p")
	vim.fn.mkdir("/data/doit/projects", "p")
	vim.fn.mkdir("/data/doit/notes", "p")
	vim.fn.mkdir("/data/doit/lists", "p")
	
	-- Initialize default list if needed
	local default_list_path = "/data/doit/lists/default.json"
	if vim.fn.filereadable(default_list_path) == 0 then
		local file = io.open(default_list_path, "w")
		if file then
			file:write("[]")
			file:close()
		end
	end
end

ensure_directories()

-- Load the full framework with proper configuration
local config = {
	-- Core framework configuration
	development_mode = false,  -- Set to false for normal operation
	quick_keys = true,
	timestamp = {
		enabled = true,
	},
	lualine = {
		enabled = false,  -- No lualine in Docker
		max_length = 30,
	},
	project = {
		enabled = true,
		detection = {
			use_git = false,  -- No git in container
			fallback_to_cwd = true,
		},
		storage = {
			path = "/data/doit/projects",
		},
	},
	
	-- Module configurations
	modules = {
		-- Todo module with lists support
		todos = {
			enabled = true,
			categories = {
				enabled = true,
				default_categories = {
					"Work",
					"Personal",
					"Projects",
					"Ideas",
					"Uncategorized"
				},
			},
			ui = {
				window = {
					width = 55,
					height = 20,
					border = "rounded",
					position = "center",
				},
				list_window = {
					width = 40,
					height = 10,
					position = "bottom-right",
				},
				list_manager = {
					preview_enabled = true,
					width_ratio = 0.8,
					height_ratio = 0.8,
					list_panel_ratio = 0.4,
				},
			},
			formatting = {
				pending = {
					icon = "○",
					format = { "icon", "text", "due_date", "relative_time" },
				},
				in_progress = {
					icon = "◐",
					format = { "icon", "text", "due_date", "relative_time" },
				},
				done = {
					icon = "✓",
					format = { "icon", "text", "due_date", "relative_time" },
				},
			},
			priorities = {
				{ name = "critical", weight = 16 },
				{ name = "urgent", weight = 8 },
				{ name = "important", weight = 4 },
			},
			storage = {
				save_path = "/data/doit/lists",  -- Lists are stored here
				import_export_path = "/data/todos.json",
			},
			lists = {
				enabled = true,
				default_list = "default",
				auto_create_default = true,
				save_path = "/data/doit/lists",
			},
			keymaps = {
				new_todo = "i",
				toggle_todo = "x",
				delete_todo = "d",
				close_window = "q",
				undo_delete = "u",
				toggle_help = "?",
				toggle_tags = "t",
				toggle_categories = "C",
				toggle_list_manager = "L",
				add_due_date = "H",
				edit_todo = "e",
				reorder_todo = "r",
				search_todos = "/",
				clear_filter = "c",
			},
		},
		
		-- Calendar module (with mock data in Docker)
		calendar = {
			enabled = true,
			default_view = "day",
			hours = {
				start = 8,
				["end"] = 20
			},
			window = {
				width = 80,
				height = 30,
				position = "center",
				border = "rounded"
			},
			keymaps = {
				toggle_window = "<leader>dC",
				switch_view_day = "d",
				switch_view_3day = "3",
				switch_view_week = "w",
				next_period = "l",
				prev_period = "h",
				today = "t",
				close = "q",
				refresh = "r"
			}
		},
		
		-- Notes module
		notes = {
			enabled = true,
			ui = {
				window = {
					width = 80,
					height = 30,
					border = "rounded",
					title = " Notes ",
					title_pos = "center",
					position = "center",
				},
			},
			storage = {
				path = "/data/doit/notes",
				mode = "global",  -- Use global mode in container
			},
			keymaps = {
				close = "q",
				switch_mode = "m",
			},
		},
	},
	
	-- Legacy keymaps for backward compatibility
	keymaps = {
		toggle_window = "<leader>do",
		toggle_list_window = "<leader>dl",
		new_todo = "i",
		toggle_todo = "x",
		delete_todo = "d",
		close_window = "q",
		undo_delete = "u",
		toggle_help = "?",
		toggle_tags = "t",
		toggle_categories = "C",
		add_due_date = "H",
		edit_todo = "e",
		reorder_todo = "r",
		search_todos = "/",
		clear_filter = "c",
		toggle_list_manager = "L",
	},
}

-- Setup the Do-It framework
local ok, doit = pcall(require, "doit")
if not ok then
	print("ERROR: Failed to load Do-It framework: " .. tostring(doit))
	return
end

-- Setup with our configuration
doit.setup(config)

-- Set up global keymaps
vim.keymap.set("n", "<leader>do", "<cmd>DoIt<CR>", { desc = "Toggle DoIt Todos" })
vim.keymap.set("n", "<leader>dn", "<cmd>DoItNotes<CR>", { desc = "Toggle DoIt Notes" })
vim.keymap.set("n", "<leader>dl", "<cmd>DoItList<CR>", { desc = "Toggle DoIt List" })
vim.keymap.set("n", "<leader>dL", "<cmd>DoItLists<CR>", { desc = "Manage DoIt Lists" })
vim.keymap.set("n", "<leader>dC", "<cmd>DoItCalendar<CR>", { desc = "Toggle DoIt Calendar" })

-- Welcome message function that reads from HELP.txt
local function show_welcome()
	print("=====================================")
	print("Do-It.nvim Interactive Environment")
	print("=====================================")
	print("")
	
	-- Try to load help content
	local help_file = "/plugin/docker/HELP.txt"
	local file = io.open(help_file, "r")
	if file then
		-- Just show a summary from the help file
		print("Quick Reference (use '?' in todo window for full help):")
		print("")
		print("COMMANDS:")
		print("  :DoIt        - Open main todo window")
		print("  :DoItList    - Open quick todo list")
		print("  :DoItLists   - Manage todo lists")
		print("  :DoItNotes   - Open notes window")
		print("  :DoItCalendar - Open calendar view")
		print("")
		print("BASIC KEYS in todo window:")
		print("  i - Add    x - Toggle    d - Delete    ? - Help")
		print("  L - Lists  t - Tags      q - Close")
		file:close()
	else
		-- Fallback if help file not found
		print("Commands: :DoIt, :DoItList, :DoItLists, :DoItNotes")
	end
	
	print("")
	print("Data is saved to /data/")
end

-- Show welcome message after a short delay
vim.defer_fn(show_welcome, 100)