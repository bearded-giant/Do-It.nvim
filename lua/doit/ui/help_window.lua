local vim = vim
local config = require("doit.config")

local M = {}

local help_win_id = nil
local help_buf_id = nil
local ns_id = vim.api.nvim_create_namespace("doit_help")

function M.is_help_window_open()
	return help_win_id ~= nil and vim.api.nvim_win_is_valid(help_win_id)
end

function M.close_help_window()
	if M.is_help_window_open() then
		vim.api.nvim_win_close(help_win_id, true)
		help_win_id = nil
		help_buf_id = nil
		return true
	end
	return false
end

function M.create_help_window()
	if M.close_help_window() then
		return
	end

	help_buf_id = vim.api.nvim_create_buf(false, true)
	local width = 50
	local height = 40
	local ui = vim.api.nvim_list_uis()[1]
	local col = math.floor((ui.width - width) / 2) + width + 2
	local row = math.floor((ui.height - height) / 2)

	help_win_id = vim.api.nvim_open_win(help_buf_id, false, {
		relative = "editor",
		row = row,
		col = col,
		width = width,
		height = height,
		style = "minimal",
		border = "rounded",
		title = " help ",
		title_pos = "center",
		zindex = 100,
	})

	local keys = config.options.keymaps
	local help_content = {
		" Main window:",
		string.format(" %-12s - Add new to-do", keys.new_todo),
		string.format(" %-12s - Toggle status", keys.toggle_todo),
		string.format(" %-12s - Delete current to-do", keys.delete_todo),
		string.format(" %-12s - Delete all completed", keys.delete_completed),
		string.format(" %-12s - Close window", keys.close_window),
		string.format(" %-12s - Add due date", keys.add_due_date),
		string.format(" %-12s - Remove due date", keys.remove_due_date),
		string.format(" %-12s - Add time estimation", keys.add_time_estimation),
		string.format(" %-12s - Remove time estimation", keys.remove_time_estimation),
		string.format(" %-12s - Toggle this help window", keys.toggle_help),
		string.format(" %-12s - Toggle tags window", keys.toggle_tags),
		string.format(" %-12s - Clear active tag filter", keys.clear_filter),
		string.format(" %-12s - Edit to-do", keys.edit_todo),
		string.format(" %-12s - Edit to-do priorities", keys.edit_priorities),
		string.format(" %-12s - Undo deletion", keys.undo_delete),
		string.format(" %-12s - Search to-dos", keys.search_todos),
		string.format(" %-12s - Import to-dos", keys.import_todos),
		string.format(" %-12s - Export to-dos", keys.export_todos),
		string.format(" %-12s - Remove duplicates", keys.remove_duplicates),
		string.format(" %-12s - Open scratchpad", keys.open_todo_scratchpad),
		string.format(" %-12s - Toggle priority", keys.toggle_priority),
		string.format(" %-12s - Enter reordering mode", keys.reorder_todo),
		"",
		" Reordering to-dos:",
		string.format(" %-12s - Move to-do up", keys.move_todo_up),
		string.format(" %-12s - Move to-do down", keys.move_todo_down),
		string.format(" %-12s - Save and exit reordering", keys.reorder_todo),
		"",
		" Tags window:",
		string.format(" %-12s - Edit tag", keys.edit_tag),
		string.format(" %-12s - Delete tag", keys.delete_tag),
		string.format(" %-12s - Filter by tag", "<CR>"),
		string.format(" %-12s - Close window", keys.close_window),
		"",
		" Calendar window:",
		string.format(" %-12s - Previous day", config.options.calendar.keymaps.previous_day),
		string.format(" %-12s - Next day", config.options.calendar.keymaps.next_day),
		string.format(" %-12s - Previous week", config.options.calendar.keymaps.previous_week),
		string.format(" %-12s - Next week", config.options.calendar.keymaps.next_week),
		string.format(" %-12s - Previous month", config.options.calendar.keymaps.previous_month),
		string.format(" %-12s - Next month", config.options.calendar.keymaps.next_month),
		string.format(" %-12s - Select date", config.options.calendar.keymaps.select_day),
		string.format(" %-12s - Close calendar", config.options.calendar.keymaps.close_calendar),
		"",
	}

	vim.api.nvim_buf_set_lines(help_buf_id, 0, -1, false, help_content)
	vim.api.nvim_buf_set_option(help_buf_id, "modifiable", false)
	vim.api.nvim_buf_set_option(help_buf_id, "buftype", "nofile")

	for i = 0, #help_content - 1 do
		vim.api.nvim_buf_add_highlight(help_buf_id, ns_id, "DoItHelpText", i, 0, -1)
	end

	vim.api.nvim_create_autocmd("BufLeave", {
		buffer = help_buf_id,
		callback = function()
			if help_win_id and vim.api.nvim_win_is_valid(help_win_id) then
				vim.api.nvim_win_close(help_win_id, true)
				help_win_id = nil
				help_buf_id = nil
			end
			return true
		end,
	})

	vim.keymap.set(
		"n",
		config.options.keymaps.close_window,
		M.close_help_window,
		{ buffer = help_buf_id, nowait = true }
	)
	vim.keymap.set(
		"n",
		config.options.keymaps.toggle_help,
		M.close_help_window,
		{ buffer = help_buf_id, nowait = true }
	)
end

return M
