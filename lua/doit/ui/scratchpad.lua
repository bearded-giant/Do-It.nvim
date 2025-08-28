local vim = vim

local config = require("doit.config")
-- Get the todo module and use its state
local core = require("doit.core")
local todo_module = core.get_module("todos")
local state = todo_module and todo_module.state or {}

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
    
    -- Check if we should use the notes module instead
    local core = package.loaded["doit.core"]
    local notes_module = core and core.get_module and core.get_module("notes")
    
    if notes_module and todo.id then
        -- Use the notes module for a richer experience
        if not todo.note_id then
            -- Create a new note linked to this todo
            local new_note = {
                content = todo.notes or "",
                title = "Notes for: " .. todo.text:sub(1, 30) .. (todo.text:len() > 30 and "..." or ""),
                metadata = {
                    todo_id = todo.id
                }
            }
            
            -- Save the note and update todo with the note ID
            local saved = notes_module.state.save_notes(new_note)
            if saved then
                local current_notes = notes_module.state.get_current_notes()
                todo.note_id = current_notes.id
                todo.note_summary = notes_module.state.generate_summary(current_notes.content)
                state.save_todos()
                
                -- Open the notes window
                notes_module.ui.notes_window.toggle_notes_window()
                return
            end
        else
            -- Open existing linked note
            notes_module.ui.notes_window.toggle_notes_window()
            return
        end
    end
    
    -- Fallback to the old notes implementation if notes module not available
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
