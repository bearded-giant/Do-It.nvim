-- Full-buffer editor for a todo's text + details and for list notes.
-- Same shape as the tmux temp-file editor: head, a marker line, then the body.
local vim = vim

local footer = require("doit.core.utils.footer")

local M = {}

M.TODO_MARKER = "── details ─────────────────────────────"
M.NOTE_MARKER = "── body ────────────────────────────────"

local function get_state()
	local ok, core = pcall(require, "doit.core")
	local module = ok and core.get_module and core.get_module("todos")
	return (module and module.state) or require("doit.state")
end

local function find_todo(state, id)
	for _, todo in ipairs(state.todos or {}) do
		if todo.id == id then
			return todo
		end
	end
end

-- any line starting "── " ends the head, so a user who retypes the marker still parses
local function split_at_marker(lines)
	for i, line in ipairs(lines) do
		if line:match("^── ") then
			return vim.list_slice(lines, 1, i - 1), vim.list_slice(lines, i + 1)
		end
	end
	return { lines[1] or "" }, vim.list_slice(lines, 2)
end

local function join(lines)
	local text = table.concat(lines, "\n")
	text = text:gsub("^%s*\n", ""):gsub("%s+$", "")
	return text
end

local function focus_existing(name)
	local bufnr = vim.fn.bufnr(name)
	if bufnr == -1 then
		return false
	end
	local win = vim.fn.bufwinid(bufnr)
	if win ~= -1 then
		vim.api.nvim_set_current_win(win)
		return true
	end
	pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
	return false
end

local function open(opts)
	if focus_existing(opts.name) then
		return
	end

	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, opts.lines)
	vim.api.nvim_buf_set_name(buf, opts.name)
	vim.bo[buf].buftype = "acwrite"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	vim.bo[buf].filetype = "markdown"
	vim.bo[buf].modified = false

	local width = math.min(100, math.floor(vim.o.columns * 0.8))
	local height = math.min(math.max(#opts.lines + 4, 12), math.floor(vim.o.lines * 0.7))
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		row = math.floor((vim.o.lines - height) / 2),
		col = math.floor((vim.o.columns - width) / 2),
		width = width,
		height = height,
		style = "minimal",
		border = "rounded",
		title = opts.title,
		title_pos = "center",
		footer = opts.footer or " q save + close · :w save · :q! discard ",
		footer_pos = "center",
		zindex = 60,
	})
	vim.wo[win].wrap = true
	vim.wo[win].linebreak = true

	vim.api.nvim_create_autocmd("BufWriteCmd", {
		buffer = buf,
		callback = function()
			if opts.on_save(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) ~= false then
				vim.bo[buf].modified = false
			end
		end,
	})

	vim.keymap.set("n", "q", function()
		if vim.bo[buf].modified then
			vim.cmd("write")
			if vim.bo[buf].modified then
				return
			end
		end
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
	end, { buffer = buf, nowait = true, desc = "Save and close" })

	for key, fn in pairs(opts.keys or {}) do
		vim.keymap.set("n", key, fn, { buffer = buf, nowait = true })
	end

	pcall(vim.api.nvim_win_set_cursor, win, opts.cursor or { 1, 0 })
	return buf, win
end

function M.edit_todo(todo, opts)
	opts = opts or {}
	if not (todo and todo.id) then
		return
	end
	local head = vim.split(todo.text or "", "\n", { plain = true })
	local original_details = join(vim.split(footer.strip(todo.description or ""), "\n", { plain = true }))
	local lines = vim.list_extend(vim.list_extend({}, head), { M.TODO_MARKER })
	vim.list_extend(lines, vim.split(original_details, "\n", { plain = true }))

	local status = todo.done and "done" or (todo.in_progress and "in-progress" or "pending")
	local priority = type(todo.priorities) == "string" and todo.priorities ~= "" and todo.priorities or "default"

	return open({
		name = "doit://todo/" .. todo.id,
		lines = lines,
		title = string.format(" [%s] [%s] [id:%s] ", status, priority, todo.id),
		footer = opts.footer,
		keys = opts.keys,
		cursor = { #head + 2, 0 },
		on_save = function(buf_lines)
			local state = get_state()
			local live = find_todo(state, todo.id)
			if not live then
				vim.notify("That to-do is no longer in this list", vim.log.levels.WARN)
				return false
			end
			local text_lines, detail_lines = split_at_marker(buf_lines)
			local text = join(text_lines)
			if text ~= "" then
				live.text = text
			end
			local details = join(detail_lines)
			if details ~= original_details then
				live.description = footer.stamp(details)
				original_details = details
			end
			state.save_to_disk()
			if opts.on_saved then
				opts.on_saved(live)
			end
		end,
	})
end

-- note == nil opens an empty buffer that adds a note on its first save.
function M.edit_note(note, opts)
	opts = opts or {}
	local current = note
	local lines = { note and note.title or "", M.NOTE_MARKER }
	vim.list_extend(lines, vim.split(note and note.body or "", "\n", { plain = true }))

	local buf = open({
		name = "doit://note/" .. (note and note.id or ("new-" .. tostring((vim.uv or vim.loop).hrtime()))),
		lines = lines,
		title = note and " note " or " new note ",
		footer = opts.footer,
		keys = opts.keys,
		cursor = note and { 3, 0 } or { 1, 0 },
		on_save = function(buf_lines)
			local state = get_state()
			local title_lines, body_lines = split_at_marker(buf_lines)
			local title, body = join(title_lines), join(body_lines)
			if current then
				if not state.update_note(current.id, title, body) then
					vim.notify("That note is no longer in this list", vim.log.levels.WARN)
					return false
				end
			elseif title ~= "" or body ~= "" then
				current = state.add_note(title, body, opts.todo_ids)
			end
			if opts.on_saved then
				opts.on_saved(current)
			end
		end,
	})
	if buf and not note then
		vim.cmd("startinsert")
	end
	return buf
end

M._split_at_marker = split_at_marker

return M
