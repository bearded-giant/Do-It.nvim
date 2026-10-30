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
			{ key = "n", desc = "New todo (in the Notes section: new note)" },
			{ key = "<CR>", desc = "Open todo text + details in the editor (note row: the note; Notes header: new note)" },
			{ key = "s", desc = "Start (in progress; one per list)" },
			{ key = "x", desc = "Complete" },
			{ key = "X", desc = "Revert to pending" },
			{ key = "e", desc = "Edit todo text (note row: edit the note)" },
			{ key = "N", desc = "Edit details in the editor" },
			{ key = "P", desc = "Set priority (critical/urgent/important)" },
			{ key = "p", desc = "New todo from the clipboard" },
			{ key = "d", desc = "Delete todo (or note, on a note row)" },
			{ key = "D", desc = "Delete all completed todos" },
			{ key = "u", desc = "Undo the last start/complete/revert or delete" },
			{ key = "q/<Esc>", desc = "Close window" },
			{ key = "?", desc = "Show help (with ALL keybindings)" },
		},
		notes = {
			{ key = "g", desc = "Notes picker (on a todo row: that todo's notes; n new linked note, l link, a all)" },
			{ key = "gN", desc = "In the todo editor: open that todo's notes" },
			{ key = "q / :w", desc = "In the editor: save and close / save" },
		},
		organization = {
			{ key = "K / J", desc = "Move todo up / down within its group" },
			{ key = "[ / ]", desc = "Jump section down / up (priority groups, Mine/Claude, Notes)" },
			{ key = "h", desc = "Set or clear due date (YYYY-MM-DD)" },
			{ key = "S", desc = "Set or clear sequence (run order across priorities)" },
			{ key = "t", desc = "Filter by #tag" },
			{ key = "c", desc = "Clear the tag filter" },
			{ key = "/", desc = "Search and jump to a todo" },
			{ key = "m", desc = "Move todo to another list (s cycles view, m mine/claude, S flips list)" },
			{ key = "l", desc = "Switch list (links this tmux window)" },
			{ key = "L", desc = "List manager" },
			{ key = "r", desc = "Refresh from disk" },
		},
		copy = {
			{ key = "y", desc = "Copy todo text (note row: note body)" },
			{ key = "<C-y>", desc = "Copy details without the footer (note row: note body)" },
			{ key = "i", desc = "Copy the item id (the doit MCP resolves it across lists)" },
			{ key = "Y", desc = "Copy the list name" },
		},
		nvim_only = {
			{ key = "a", desc = "Add a child todo nested under the current one" },
			{ key = "<Space>", desc = "Cycle status (pending, in progress, done)" },
			{ key = "H", desc = "Due date from the calendar" },
			{ key = "T / R", desc = "Add / remove time estimation" },
			{ key = "<leader>D", desc = "Remove duplicate todos (confirms first, undoable with u)" },
		},
		import_export = {
			{ key = "I", desc = "Import todos from file" },
			{ key = "E", desc = "Export pending todos to markdown" },
			{ key = "<leader>E", desc = "Export todos to JSON file" },
			{ key = "O", desc = "Send todo to the Obsidian daily note" },
			{ key = "B", desc = "Back up all lists" },
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
		{ key = "s", desc = "Cycle view: all -> mine -> claude (shared with tmux)" },
		{ key = "m", desc = "Toggle view straight between mine and claude" },
		{ key = "S", desc = "Flip selected list between mine and claude" },
		{ key = "?", desc = "Show full help" },
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
	"Tag-based filtering with #hashtags",
	"Due dates with calendar integration",
	"Priority system with weights",
	"Time estimation tracking",
	"Project-specific or global notes",
	"Import/export for backup and sharing",
}

-- Function to get formatted help text
M.todo_window_sections = {
	{ name = "basic", title = "Basic" },
	{ name = "notes", title = "Notes and editor" },
	{ name = "organization", title = "Organization" },
	{ name = "copy", title = "Copy" },
	{ name = "nvim_only", title = "nvim only" },
	{ name = "import_export", title = "Import/Export" },
}

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
	for i, section in ipairs(M.todo_window_sections) do
		if i > 1 then
			table.insert(lines, "")
		end
		table.insert(lines, "  " .. section.title .. ":")
		for _, km in ipairs(M.keymaps.todo_window[section.name]) do
			table.insert(lines, string.format("    %-12s - %s", km.key, km.desc))
		end
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
	for i, section in ipairs(M.todo_window_sections) do
		if i > 1 then
			table.insert(lines, "")
		end
		table.insert(lines, "### " .. section.title)
		table.insert(lines, "")
		table.insert(lines, "| Key | Description |")
		table.insert(lines, "|-----|-------------|")
		for _, km in ipairs(M.keymaps.todo_window[section.name]) do
			table.insert(lines, string.format("| `%s` | %s |", km.key, km.desc))
		end
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
	table.insert(lines, '        complete_todo = "x",')
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