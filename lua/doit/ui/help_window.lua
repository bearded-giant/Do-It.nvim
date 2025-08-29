local vim = vim

local M = {}

local help_win_id = nil
local help_buf_id = nil

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

	-- Use the centralized help module for consistency
	local help = require("doit.help")
	local help_text = help.get_help_text()
	local help_lines = vim.split(help_text, "\n")

	help_buf_id = vim.api.nvim_create_buf(false, true)
	local width = 70
	local height = math.min(#help_lines + 2, 40)
	local ui = vim.api.nvim_list_uis()[1]
	local col = math.floor((ui.width - width) / 2)
	local row = math.floor((ui.height - height) / 2)

	help_win_id = vim.api.nvim_open_win(help_buf_id, true, {  -- Changed to true to take focus
		relative = "editor",
		row = row,
		col = col,
		width = width,
		height = height,
		style = "minimal",
		border = "rounded",
		title = " Do-It.nvim Help ",
		title_pos = "center",
		footer = " [q/Esc/?] to close ",
		footer_pos = "center",
		zindex = 100,
	})

	-- Set buffer content from centralized help
	vim.api.nvim_buf_set_lines(help_buf_id, 0, -1, false, help_lines)
	vim.api.nvim_buf_set_option(help_buf_id, "modifiable", false)
	vim.api.nvim_buf_set_option(help_buf_id, "buftype", "nofile")

	-- Store the previous window to return focus to it
	local prev_win = vim.fn.win_getid(vim.fn.winnr('#'))
	
	-- Set up keymaps to close help and return focus
	local function close_help()
		M.close_help_window()
		-- Return focus to the todo window if it's still valid
		if prev_win and vim.api.nvim_win_is_valid(prev_win) then
			vim.api.nvim_set_current_win(prev_win)
		end
	end

	vim.keymap.set("n", "q", close_help, { buffer = help_buf_id, nowait = true })
	vim.keymap.set("n", "<Esc>", close_help, { buffer = help_buf_id, nowait = true })
	vim.keymap.set("n", "?", close_help, { buffer = help_buf_id, nowait = true })

	return help_win_id, help_buf_id
end

return M