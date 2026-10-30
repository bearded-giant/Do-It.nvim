-- List notes picker: filter, preview, open, add, delete, and link notes to a todo.
local vim = vim

local current_state = require("doit.modules.todos.state.current")
local note_links = require("doit.modules.todos.state.note_links")

local M = {}

local picker = nil

local function note_label(note)
	local title = note.title or ""
	if title == "" then
		title = vim.split(note.body or "", "\n", { plain = true })[1] or ""
	end
	return title ~= "" and title or "(untitled)"
end

local function visible_notes()
	local notes = current_state().get_notes() or {}
	if picker.todo and picker.scoped then
		notes = note_links.notes_for_todo(notes, picker.todo.id)
	end
	if picker.query and picker.query ~= "" then
		local keyed = {}
		for _, note in ipairs(notes) do
			table.insert(keyed, { note = note, text = (note.title or "") .. " " .. (note.body or "") })
		end
		notes = {}
		for _, item in ipairs(vim.fn.matchfuzzy(keyed, picker.query, { key = "text" })) do
			table.insert(notes, item.note)
		end
	end
	return notes
end

local function selected()
	if not (picker and vim.api.nvim_win_is_valid(picker.list_win)) then
		return nil
	end
	return picker.items[vim.api.nvim_win_get_cursor(picker.list_win)[1]]
end

local function render_preview()
	local note = selected()
	local lines = {}
	if note then
		table.insert(lines, note_label(note))
		table.insert(lines, string.rep("─", 30))
		vim.list_extend(lines, vim.split(note.body or "", "\n", { plain = true }))
		local todos = note_links.todos_for_note(current_state().todos, note)
		if #todos > 0 then
			table.insert(lines, "")
			table.insert(lines, "todos:")
			for _, todo in ipairs(todos) do
				table.insert(lines, "  " .. (todo.done and "✓ " or "• ") .. vim.split(todo.text or "", "\n")[1])
			end
		end
	end
	vim.bo[picker.preview_buf].modifiable = true
	vim.api.nvim_buf_set_lines(picker.preview_buf, 0, -1, false, lines)
	vim.bo[picker.preview_buf].modifiable = false
end

local function render()
	picker.items = visible_notes()
	local lines = {}
	for _, note in ipairs(picker.items) do
		local mark = (picker.todo and note_links.has(note.todo_ids, picker.todo.id)) and "● " or "  "
		local date = note.updated_at and os.date("%m-%d", note.updated_at) or ""
		table.insert(lines, mark .. note_label(note) .. "  " .. date)
	end
	if #lines == 0 then
		lines = { picker.todo and picker.scoped and "  (no notes for this to-do: n adds one, a shows all)" or "  (no notes)" }
	end
	vim.bo[picker.list_buf].modifiable = true
	vim.api.nvim_buf_set_lines(picker.list_buf, 0, -1, false, lines)
	vim.bo[picker.list_buf].modifiable = false

	local title = " notes "
	if picker.todo then
		local text = vim.split(picker.todo.text or "", "\n")[1]
		title = string.format(" %s: %s ", picker.scoped and "notes for" or "all notes, ● linked to", text:sub(1, 40))
	end
	if picker.query and picker.query ~= "" then
		title = title .. "/" .. picker.query .. " "
	end
	vim.api.nvim_win_set_config(picker.list_win, { title = title, title_pos = "center" })
	render_preview()
end

function M.close()
	if not picker then
		return
	end
	local p = picker
	picker = nil
	for _, win in ipairs({ p.list_win, p.preview_win }) do
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
	end
	if p.on_close then
		p.on_close()
	end
end

local function changed()
	if picker.on_change then
		picker.on_change()
	end
	render()
end

local function open_editor(note)
	local todo, on_change = picker.todo, picker.on_change
	M.close()
	require("doit.ui.editor").edit_note(note, {
		todo_ids = (not note and todo) and { todo.id } or nil,
		on_saved = on_change,
		on_close = on_change,
	})
end

local function map(key, fn)
	vim.keymap.set("n", key, fn, { buffer = picker.list_buf, nowait = true })
end

-- opts.todo scopes the picker to that todo's notes; opts.on_change re-renders the caller.
function M.open(opts)
	opts = opts or {}
	M.close()

	local height = math.max(10, math.floor(vim.o.lines * 0.6))
	local total = math.min(140, math.floor(vim.o.columns * 0.9))
	local list_width = math.floor(total * 0.45)
	local preview_width = total - list_width - 2
	local row = math.floor((vim.o.lines - height) / 2)
	local col = math.floor((vim.o.columns - total) / 2)

	local list_buf = vim.api.nvim_create_buf(false, true)
	local preview_buf = vim.api.nvim_create_buf(false, true)
	vim.bo[list_buf].bufhidden = "wipe"
	vim.bo[preview_buf].bufhidden = "wipe"
	vim.bo[preview_buf].filetype = "markdown"

	local preview_win = vim.api.nvim_open_win(preview_buf, false, {
		relative = "editor", row = row, col = col + list_width + 2, width = preview_width, height = height,
		style = "minimal", border = "rounded", zindex = 70,
	})
	vim.wo[preview_win].wrap = true
	local list_win = vim.api.nvim_open_win(list_buf, true, {
		relative = "editor", row = row, col = col, width = list_width, height = height,
		style = "minimal", border = "rounded", zindex = 70,
		footer = " <CR> open · n new · d del · l link · a all · / filter · q ",
		footer_pos = "center",
	})
	vim.wo[list_win].cursorline = true

	picker = {
		list_buf = list_buf,
		list_win = list_win,
		preview_buf = preview_buf,
		preview_win = preview_win,
		todo = opts.todo,
		scoped = opts.todo ~= nil,
		on_change = opts.on_change,
		on_close = opts.on_close,
		items = {},
	}
	render()

	vim.api.nvim_create_autocmd("CursorMoved", { buffer = list_buf, callback = render_preview })

	map("<CR>", function()
		local note = selected()
		if note then
			open_editor(note)
		end
	end)
	map("n", function()
		open_editor(nil)
	end)
	map("d", function()
		local note = selected()
		if not note then
			return
		end
		vim.ui.input({ prompt = "Delete note '" .. note_label(note) .. "'? (y/N): " }, function(answer)
			if picker and answer and answer:lower() == "y" then
				current_state().delete_note(note.id)
				changed()
			end
		end)
	end)
	map("l", function()
		local note = selected()
		if not (note and picker.todo) then
			return
		end
		current_state().update_note(note.id, nil, nil, note_links.toggled(note.todo_ids, picker.todo.id))
		changed()
	end)
	map("a", function()
		if picker.todo then
			picker.scoped = not picker.scoped
			render()
		end
	end)
	map("/", function()
		vim.ui.input({ prompt = "Filter notes: ", default = picker.query or "" }, function(query)
			if picker and query ~= nil then
				picker.query = query
				render()
			end
		end)
	end)
	map("q", M.close)
	map("<Esc>", M.close)
end

function M.is_open()
	return picker ~= nil
end

return M
