-- Central help/keybinding documentation module
-- This ensures all help information stays in sync across the plugin

local M = {}

M.keymaps = {
	global = {
		{ key = "<leader>do", desc = "Toggle main todo window" },
		{ key = "<leader>dn", desc = "Toggle notes window" },
		{ key = "<leader>dl", desc = "Toggle quick todo list" },
		{ key = "<leader>dL", desc = "Open list manager" },
	},
	todo_window = {
		basic = {
			{ key = "i", desc = "Add new todo" },
			{ key = "<Space>", desc = "Toggle todo status (pending→in-progress→done)" },
			{ key = "p", desc = "Set/change priority (critical/urgent/important)" },
			{ key = "d", desc = "Delete current todo" },
			{ key = "D", desc = "Delete all completed todos" },
			{ key = "u", desc = "Undo last delete" },
			{ key = "e", desc = "Edit current todo" },
			{ key = "q/<Esc>", desc = "Close window" },
			{ key = "?", desc = "Show help (with ALL keybindings)" },
		},
		organization = {
			{ key = "t", desc = "Toggle tags window (filter by #tag)" },
			{ key = "C", desc = "Toggle categories window" },
			{ key = "L", desc = "List manager - switch lists, create new lists" },
			{ key = "m", desc = "Move current todo to another list" },
			{ key = "c", desc = "Clear active filter" },
			{ key = "/", desc = "Search todos" },
		},
		advanced = {
			{ key = "H", desc = "Add/edit due date (calendar)" },
			{ key = "r", desc = "Reorder current todo (use j/k to move)" },
			{ key = "T", desc = "Add time estimation" },
			{ key = "R", desc = "Remove time estimation" },
			{ key = "o", desc = "Open linked note" },
			{ key = "<leader>p", desc = "Open scratchpad for todo" },
		},
		import_export = {
			{ key = "I", desc = "Import todos from file" },
			{ key = "E", desc = "Export todos to file" },
		},
	},
	list_manager = {
		{ key = "1-9, 0", desc = "Quick select list by number" },
		{ key = "j/k", desc = "Navigate up/down" },
		{ key = "Enter/Space", desc = "Switch to selected list" },
		{ key = "n", desc = "Create new list" },
		{ key = "d", desc = "Delete selected list" },
		{ key = "r", desc = "Rename selected list" },
		{ key = "i", desc = "Import list from file" },
		{ key = "e", desc = "Export selected list" },
		{ key = "q/Esc", desc = "Close manager" },
	},
	notes_window = {
		{ key = "m", desc = "Switch between global/project mode" },
		{ key = "q", desc = "Close window" },
	},
}

M.commands = {
	{ cmd = ":DoIt", desc = "Open main todo window" },
	{ cmd = ":DoItList", desc = "Open quick todo list (floating)" },
	{ cmd = ":DoItLists", desc = "Manage multiple todo lists" },
	{ cmd = ":DoItNotes", desc = "Open notes window" },
}

M.features = {
	"Multiple named todo lists with persistence",
	"Categories for organization",
	"Tag-based filtering with #hashtags",
	"Due dates with calendar integration",
	"Priority system with weights",
	"Time estimation tracking",
	"Project-specific or global notes",
	"Import/export for backup and sharing",
}

-- Function to get formatted help text
function M.get_help_text()
	local lines = {}
	
	-- Commands
	table.insert(lines, "COMMANDS:")
	for _, cmd in ipairs(M.commands) do
		table.insert(lines, string.format("  %-14s - %s", cmd.cmd, cmd.desc))
	end
	
	table.insert(lines, "")
	table.insert(lines, "GLOBAL KEYMAPS:")
	for _, km in ipairs(M.keymaps.global) do
		table.insert(lines, string.format("  %-14s - %s", km.key, km.desc))
	end
	
	-- Todo window keymaps
	table.insert(lines, "")
	table.insert(lines, "TODO WINDOW KEYMAPS:")
	table.insert(lines, "  Basic:")
	for _, km in ipairs(M.keymaps.todo_window.basic) do
		table.insert(lines, string.format("    %-12s - %s", km.key, km.desc))
	end
	
	table.insert(lines, "")
	table.insert(lines, "  Organization:")
	for _, km in ipairs(M.keymaps.todo_window.organization) do
		table.insert(lines, string.format("    %-12s - %s", km.key, km.desc))
	end
	
	table.insert(lines, "")
	table.insert(lines, "  Advanced:")
	for _, km in ipairs(M.keymaps.todo_window.advanced) do
		table.insert(lines, string.format("    %-12s - %s", km.key, km.desc))
	end
	
	table.insert(lines, "")
	table.insert(lines, "  Import/Export:")
	for _, km in ipairs(M.keymaps.todo_window.import_export) do
		table.insert(lines, string.format("    %-12s - %s", km.key, km.desc))
	end
	
	-- List manager
	table.insert(lines, "")
	table.insert(lines, "LIST MANAGER KEYMAPS:")
	for _, km in ipairs(M.keymaps.list_manager) do
		table.insert(lines, string.format("  %-14s - %s", km.key, km.desc))
	end
	
	-- Notes window
	table.insert(lines, "")
	table.insert(lines, "NOTES WINDOW KEYMAPS:")
	for _, km in ipairs(M.keymaps.notes_window) do
		table.insert(lines, string.format("  %-14s - %s", km.key, km.desc))
	end
	
	-- Features
	table.insert(lines, "")
	table.insert(lines, "FEATURES:")
	for _, feature in ipairs(M.features) do
		table.insert(lines, "  • " .. feature)
	end
	
	return table.concat(lines, "\n")
end

-- Function to get markdown formatted help
function M.get_markdown_help()
	local lines = {}
	
	-- Header
	table.insert(lines, "# Do-It.nvim Keybindings and Commands Reference")
	table.insert(lines, "")
	table.insert(lines, "<!-- This file is auto-generated from lua/doit/help.lua - DO NOT EDIT DIRECTLY -->")
	table.insert(lines, "<!-- To update: make update-help -->")
	table.insert(lines, "")
	
	-- Commands
	table.insert(lines, "## Commands")
	table.insert(lines, "")
	table.insert(lines, "| Command | Description |")
	table.insert(lines, "|---------|-------------|")
	for _, cmd in ipairs(M.commands) do
		table.insert(lines, string.format("| `%s` | %s |", cmd.cmd, cmd.desc))
	end
	
	-- Global keymaps
	table.insert(lines, "")
	table.insert(lines, "## Global Keymaps")
	table.insert(lines, "")
	table.insert(lines, "| Key | Description |")
	table.insert(lines, "|-----|-------------|")
	for _, km in ipairs(M.keymaps.global) do
		table.insert(lines, string.format("| `%s` | %s |", km.key, km.desc))
	end
	
	-- Todo window keymaps
	table.insert(lines, "")
	table.insert(lines, "## Todo Window Keymaps")
	table.insert(lines, "")
	table.insert(lines, "### Basic Operations")
	table.insert(lines, "")
	table.insert(lines, "| Key | Description |")
	table.insert(lines, "|-----|-------------|")
	for _, km in ipairs(M.keymaps.todo_window.basic) do
		table.insert(lines, string.format("| `%s` | %s |", km.key, km.desc))
	end
	
	table.insert(lines, "")
	table.insert(lines, "### Organization")
	table.insert(lines, "")
	table.insert(lines, "| Key | Description |")
	table.insert(lines, "|-----|-------------|")
	for _, km in ipairs(M.keymaps.todo_window.organization) do
		table.insert(lines, string.format("| `%s` | %s |", km.key, km.desc))
	end
	
	table.insert(lines, "")
	table.insert(lines, "### Advanced Features")
	table.insert(lines, "")
	table.insert(lines, "| Key | Description |")
	table.insert(lines, "|-----|-------------|")
	for _, km in ipairs(M.keymaps.todo_window.advanced) do
		table.insert(lines, string.format("| `%s` | %s |", km.key, km.desc))
	end
	
	table.insert(lines, "")
	table.insert(lines, "### Import/Export")
	table.insert(lines, "")
	table.insert(lines, "| Key | Description |")
	table.insert(lines, "|-----|-------------|")
	for _, km in ipairs(M.keymaps.todo_window.import_export) do
		table.insert(lines, string.format("| `%s` | %s |", km.key, km.desc))
	end
	
	-- List manager
	table.insert(lines, "")
	table.insert(lines, "## List Manager Keymaps")
	table.insert(lines, "")
	table.insert(lines, "| Key | Description |")
	table.insert(lines, "|-----|-------------|")
	for _, km in ipairs(M.keymaps.list_manager) do
		table.insert(lines, string.format("| `%s` | %s |", km.key, km.desc))
	end
	
	-- Notes window
	table.insert(lines, "")
	table.insert(lines, "## Notes Window Keymaps")
	table.insert(lines, "")
	table.insert(lines, "| Key | Description |")
	table.insert(lines, "|-----|-------------|")
	for _, km in ipairs(M.keymaps.notes_window) do
		table.insert(lines, string.format("| `%s` | %s |", km.key, km.desc))
	end
	
	-- Features
	table.insert(lines, "")
	table.insert(lines, "## Features")
	table.insert(lines, "")
	for _, feature in ipairs(M.features) do
		-- Simple approach: just add bullet with feature
		table.insert(lines, "- " .. feature)
	end
	
	-- Add customization section
	table.insert(lines, "")
	table.insert(lines, "## Customization")
	table.insert(lines, "")
	table.insert(lines, "All keybindings can be customized in your config:")
	table.insert(lines, "")
	table.insert(lines, "```lua")
	table.insert(lines, 'require("doit").setup({')
	table.insert(lines, "  modules = {")
	table.insert(lines, "    todos = {")
	table.insert(lines, "      keymaps = {")
	table.insert(lines, '        new_todo = "a",  -- Change \'i\' to \'a\' for adding todos')
	table.insert(lines, '        toggle_todo = "<Space>",  -- Use space to toggle')
	table.insert(lines, "        -- etc...")
	table.insert(lines, "      }")
	table.insert(lines, "    }")
	table.insert(lines, "  }")
	table.insert(lines, "})")
	table.insert(lines, "```")
	
	return table.concat(lines, "\n")
end

-- Function to update the HELP.txt file
function M.update_help_file()
	local help_path = vim.fn.expand("~/.config/nvim/lua/doit/docker/HELP.txt")
	local file = io.open(help_path, "w")
	if file then
		file:write(M.get_help_text())
		file:close()
		return true
	end
	return false
end

-- Function to update the markdown documentation
function M.update_markdown_docs()
	local md_path = vim.fn.expand("~/.config/nvim/lua/doit/docs/KEYBINDINGS.md")
	local file = io.open(md_path, "w")
	if file then
		file:write(M.get_markdown_help())
		file:close()
		return true
	end
	return false
end

-- Function to show help in a floating window
function M.show_help_window()
	local lines = vim.split(M.get_help_text(), "\n")
	
	-- Create buffer
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.api.nvim_buf_set_option(buf, "modifiable", false)
	vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
	
	-- Calculate window size
	local width = 70
	local height = math.min(#lines + 2, 40)
	
	-- Get editor dimensions
	local ui = vim.api.nvim_list_uis()[1]
	local row = math.floor((ui.height - height) / 2)
	local col = math.floor((ui.width - width) / 2)
	
	-- Create window
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		row = row,
		col = col,
		width = width,
		height = height,
		style = "minimal",
		border = "rounded",
		title = " Do-It.nvim Help ",
		title_pos = "center",
	})
	
	-- Set up keymaps
	vim.keymap.set("n", "q", function()
		vim.api.nvim_win_close(win, true)
	end, { buffer = buf, nowait = true })
	
	vim.keymap.set("n", "<Esc>", function()
		vim.api.nvim_win_close(win, true)
	end, { buffer = buf, nowait = true })
	
	return win
end

return M