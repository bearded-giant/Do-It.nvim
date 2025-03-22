local vim = vim

local config = require("doit.config")
local state = require("doit.state")

local M = {}

function M.open_todo_scratchpad(win_id)
	if not win_id or not vim.api.nvim_win_is_valid(win_id) then
		return
	end

	local cursor = vim.api.nvim_win_get_cursor(win_id)
	local todo_index = cursor[1] - 1
	local todo = state.todos[todo_index]

	if not todo then
		vim.notify("No todo selected", vim.log.levels.WARN)
		return
	end

	if todo.notes == nil then
		todo.notes = ""
	end

	local function is_valid_filetype(filetype)
		local syntax_file = vim.fn.globpath(vim.o.runtimepath, "syntax/" .. filetype .. ".vim")
		return syntax_file ~= ""
	end

	local scratch_buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_option(scratch_buf, "buftype", "acwrite")
	vim.api.nvim_buf_set_option(scratch_buf, "swapfile", false)

	local syntax_highlight = config.options.scratchpad.syntax_highlight
	if not is_valid_filetype(syntax_highlight) then
		vim.notify(
			"Invalid scratchpad syntax highlight '" .. syntax_highlight .. "'. Using 'markdown' by default.",
			vim.log.levels.WARN
		)
		syntax_highlight = "markdown"
	end

	vim.api.nvim_buf_set_option(scratch_buf, "filetype", syntax_highlight)

	local ui = vim.api.nvim_list_uis()[1]
	local width = math.floor(ui.width * 0.6)
	local height = math.floor(ui.height * 0.6)
	local row = math.floor((ui.height - height) / 2)
	local col = math.floor((ui.width - width) / 2)

	local scratch_win = vim.api.nvim_open_win(scratch_buf, true, {
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		style = "minimal",
		border = "rounded",
		title = " Scratchpad ",
		title_pos = "center",
	})

	local initial_notes = todo.notes or ""
	vim.api.nvim_buf_set_lines(scratch_buf, 0, -1, false, vim.split(initial_notes, "\n"))

	local function close_notes()
		if vim.api.nvim_win_is_valid(scratch_win) then
			vim.api.nvim_win_close(scratch_win, true)
		end

		if vim.api.nvim_buf_is_valid(scratch_buf) then
			vim.api.nvim_buf_delete(scratch_buf, { force = true })
		end
	end

	local function save_notes()
		local lines = vim.api.nvim_buf_get_lines(scratch_buf, 0, -1, false)
		local new_notes = table.concat(lines, "\n")

		if new_notes ~= initial_notes then
			todo.notes = new_notes
			state.save_to_disk()
			vim.notify("Notes saved", vim.log.levels.INFO)
		end
		close_notes()
	end

	vim.api.nvim_create_autocmd("WinLeave", {
		buffer = scratch_buf,
		callback = close_notes,
	})

	vim.keymap.set("n", "<CR>", save_notes, { buffer = scratch_buf })
	vim.keymap.set("n", "<Esc>", close_notes, { buffer = scratch_buf })
end

return M
