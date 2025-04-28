local vim = vim

local config = require("doit.config")
local calendar = require("doit.calendar")
local highlights = require("doit.ui.highlights")
local todo_actions = require("doit.ui.todo_actions")
local help_window = require("doit.ui.help_window")
local tag_window = require("doit.ui.tag_window")
local search_window = require("doit.ui.search_window")
local scratchpad = require("doit.ui.scratchpad")

local state = require("doit.state")
state.load_todos()

local M = {}

local win_id = nil
local buf_id = nil

function M.get_window_id()
    return win_id
end

-- smaller "quick keys" UI below main window (optional)
local function create_small_keys_window(main_win_pos)
	if not config.options.quick_keys then
		return nil
	end

	local keys = config.options.keymaps
	local small_buf = vim.api.nvim_create_buf(false, true)
	local width = config.options.window.width

	local lines_1 = {
		"",
		string.format("  %-6s - New to-do", keys.new_todo),
		string.format("  %-6s - Toggle status", keys.toggle_todo),
		string.format("  %-6s - Delete to-do", keys.delete_todo),
		string.format("  %-6s - Undo delete", keys.undo_delete),
		string.format("  %-6s - Add due date", keys.add_due_date),
		"",
	}

	local lines_2 = {
		"",
		string.format("  %-6s - Reorder to-do", keys.reorder_todo),
		string.format("  %-6s - Tags", keys.toggle_tags),
		string.format("  %-6s - Search", keys.search_todos),
		string.format("  %-6s - Import", keys.import_todos),
		string.format("  %-6s - Export", keys.export_todos),
		"",
	}

	local mid_point = math.floor(width / 2)
	local padding = 2
	local lines = {}
	for i = 1, #lines_1 do
		local line1 = lines_1[i] .. string.rep(" ", mid_point - #lines_1[i] - padding)
		local line2 = lines_2[i] or ""
		lines[i] = line1 .. line2
	end

	vim.api.nvim_buf_set_lines(small_buf, 0, -1, false, lines)
	vim.api.nvim_buf_set_option(small_buf, "modifiable", false)
	vim.api.nvim_buf_set_option(small_buf, "buftype", "nofile")

	local row = main_win_pos.row + main_win_pos.height + 1
	local small_win = vim.api.nvim_open_win(small_buf, false, {
		relative = "editor",
		row = row,
		col = main_win_pos.col,
		width = width,
		height = #lines,
		style = "minimal",
		border = "rounded",
		focusable = false,
		zindex = 45,
		footer = " Quick Keys ",
		footer_pos = "center",
	})

	-- Basic highlighting
	local ns = vim.api.nvim_create_namespace("doit_small_keys")
	for i = 1, #lines do
		-- you can highlight lines or columns here as needed
		-- e.g. vim.api.nvim_buf_add_highlight(small_buf, ns, "String", i-1, 0, -1)
	end

	return small_win
end

local function prompt_io(operation, on_render)
	local io_path = config.options.import_export_path or vim.fn.expand("~/todos.json")
	local is_import = operation == "import"
	local prompt_text = is_import and "Import todos from file: " or "Export todos to file: "
	local cancel_message = is_import and "Import cancelled" or "Export cancelled"

	vim.ui.input({
		prompt = prompt_text,
		default = io_path,
		completion = "file",
	}, function(file_path)
		if not file_path or file_path == "" then
			vim.notify(cancel_message, vim.log.levels.INFO)
			return
		end

		file_path = vim.fn.expand(file_path)
		local fn = is_import and state.import_todos or state.export_todos
		local success, message = fn(file_path)

		if success then
			vim.notify(message, vim.log.levels.INFO)
			if is_import and on_render then
				on_render()
			end
		else
			vim.notify(message, vim.log.levels.ERROR)
		end
	end)
end

local function prompt_export()
	prompt_io("export")
end

local function prompt_import(on_render)
	prompt_io("import", on_render)
end

function M.render_todos()
	if not buf_id or not vim.api.nvim_buf_is_valid(buf_id) then
		return
	end
	vim.api.nvim_buf_set_option(buf_id, "modifiable", true)

	local ns_id = highlights.get_namespace_id()
	vim.api.nvim_buf_clear_namespace(buf_id, ns_id, 0, -1)

	state.sort_todos()

	local lines = { "" }
	if state.active_filter then
		table.insert(lines, "")
		table.insert(lines, "  Filtered by: #" .. state.active_filter)
	end

	for _, todo in ipairs(state.todos) do
		if not state.active_filter or todo.text:match("#" .. state.active_filter) then
			table.insert(lines, "  " .. M.format_todo_line(todo))
		end
	end
	table.insert(lines, "")

	for i, line in ipairs(lines) do
		lines[i] = line:gsub("\n", " ")
	end

	vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)

	-- Now highlight each line
	local done_icon = config.options.formatting.done.icon
	local pending_icon = config.options.formatting.pending.icon
	local in_progress_icon = config.options.formatting.in_progress.icon

	for i, line in ipairs(lines) do
		local line_nr = i - 1
		if line:match("^%s+[" .. done_icon .. pending_icon .. in_progress_icon .. "]") then
			local todo_index = i - (state.active_filter and 3 or 1)
			local todo = state.todos[todo_index]
			if todo then
				if todo.done then
					vim.api.nvim_buf_add_highlight(buf_id, ns_id, "DoItDone", line_nr, 0, -1)
				else
					local hl_group = highlights.get_priority_highlight(todo.priorities, config)
					vim.api.nvim_buf_add_highlight(buf_id, ns_id, hl_group, line_nr, 0, -1)
				end

				-- Tag highlight
				for tag in line:gmatch("#(%w+)") do
					local start_idx = line:find("#" .. tag) - 1
					vim.api.nvim_buf_add_highlight(buf_id, ns_id, "Type", line_nr, start_idx, start_idx + #tag + 1)
				end

				-- Overdue highlight
				if line:match("%[OVERDUE%]") then
					local start_idx = line:find("%[OVERDUE%]")
					vim.api.nvim_buf_add_highlight(buf_id, ns_id, "ErrorMsg", line_nr, start_idx - 1, start_idx + 8)
				end

				-- Timestamp highlight
				if config.options.timestamp and config.options.timestamp.enabled then
					local timestamp_pattern = "@[%w%s]+ago"
					local start_idx = line:find(timestamp_pattern)
					if start_idx then
						vim.api.nvim_buf_add_highlight(
							buf_id,
							ns_id,
							"DoItTimestamp",
							line_nr,
							start_idx - 1,
							start_idx - 1 + #line:match(timestamp_pattern)
						)
					end
				end
			end
		elseif line:match("Filtered by:") then
			vim.api.nvim_buf_add_highlight(buf_id, ns_id, "WarningMsg", line_nr, 0, -1)
		end
	end

	vim.api.nvim_buf_set_option(buf_id, "modifiable", false)
end

function M.format_todo_line(todo)
	local formatting = config.options.formatting
	if not formatting or not formatting.pending or not formatting.done then
		error("Invalid 'formatting' configuration in config.lua")
	end

	local format = todo.done and formatting.done.format or formatting.pending.format
	if not format then
		format = { "icon", "text", "ect", "relative_time" } -- fallback
	end

	-- Visual indicator if this todo is being reordered
	local is_reordering = false
	if state.reordering_todo_index then
		for i, t in ipairs(state.todos) do
			if i == state.reordering_todo_index and t == todo then
				is_reordering = true
				break
			end
		end
	end

	local notes_icon = ""
	if todo.notes and todo.notes ~= "" then
		notes_icon = config.options.notes.icon or "✎"
	end

	local components = {}
	local function format_relative_time(timestamp)
		local now = os.time()
		local diff = now - timestamp
		if diff < 60 then
			return "just now"
		elseif diff < 3600 then
			return (math.floor(diff / 60)) .. "m ago"
		elseif diff < 86400 then
			return (math.floor(diff / 3600)) .. "h ago"
		elseif diff < 604800 then
			return (math.floor(diff / 86400)) .. "d ago"
		else
			return (math.floor(diff / 604800)) .. "w ago"
		end
	end

	local function format_due_date()
		if todo.due_at then
			local date = os.date("*t", todo.due_at)
			local lang = calendar and calendar.get_language() or "en"
			local month = calendar.MONTH_NAMES[lang][date.month]
			local formatted
			if lang == "pt" or lang == "es" then
				formatted = string.format("%d de %s de %d", date.day, month, date.year)
			elseif lang == "fr" or lang == "de" or lang == "it" then
				formatted = string.format("%d %s %d", date.day, month, date.year)
			elseif lang == "jp" then
				formatted = string.format("%d年%s%d日", date.year, month, date.day)
			else
				formatted = string.format("%s %d, %d", month, date.day, date.year)
			end

			local icon = config.options.calendar.icon or ""
			local due_date_str = (icon ~= "") and ("[" .. icon .. " " .. formatted .. "]") or ("[" .. formatted .. "]")
			if (not todo.done) and (todo.due_at < os.time()) then
				due_date_str = due_date_str .. " [OVERDUE]"
			end
			return due_date_str
		end
		return ""
	end

	for _, part in ipairs(format) do
		if part == "icon" then
			if is_reordering then
				table.insert(components, "> ")
			end

			if todo.done then
				table.insert(components, formatting.done.icon)
			elseif todo.in_progress then
				table.insert(components, formatting.in_progress.icon)
			else
				table.insert(components, formatting.pending.icon)
			end
		elseif part == "text" then
			table.insert(components, (todo.text:gsub("\n", " ")))
		elseif part == "notes_icon" then
			table.insert(components, notes_icon)
		elseif part == "relative_time" then
			if todo.created_at and config.options.timestamp and config.options.timestamp.enabled then
				table.insert(components, "@" .. format_relative_time(todo.created_at))
			end
		elseif part == "due_date" then
			local dd = format_due_date()
			if dd ~= "" then
				table.insert(components, dd)
			end
		elseif part == "priority" then
			local score = state.get_priority_score(todo)
			table.insert(components, string.format("Priority: %d", score))
		elseif part == "ect" then
			if todo.estimated_hours then
				local h = todo.estimated_hours
				if h >= 168 then
					local w = h / 168
					table.insert(components, string.format("[≈ %gw]", w))
				elseif h >= 24 then
					local d = h / 24
					table.insert(components, string.format("[≈ %gd]", d))
				elseif h >= 1 then
					table.insert(components, string.format("[≈ %gh]", h))
				else
					table.insert(components, string.format("[≈ %gm]", h * 60))
				end
			end
		end
	end

	return table.concat(components, " ")
end

local function create_window()
	local ui = vim.api.nvim_list_uis()[1]
	local width = config.options.window.width
	local height = config.options.window.height
	local position = config.options.window.position or "right"
	local padding = 2

	local col, row
	if position == "right" then
		col = ui.width - width - padding
		row = math.floor((ui.height - height) / 2)
	elseif position == "left" then
		col = padding
		row = math.floor((ui.height - height) / 2)
	elseif position == "top" then
		col = math.floor((ui.width - width) / 2)
		row = padding
	elseif position == "bottom" then
		col = math.floor((ui.width - width) / 2)
		row = ui.height - height - padding
	elseif position == "top-right" then
		col = ui.width - width - padding
		row = padding
	elseif position == "top-left" then
		col = padding
		row = padding
	elseif position == "bottom-right" then
		col = ui.width - width - padding
		row = ui.height - height - padding
	elseif position == "bottom-left" then
		col = padding
		row = ui.height - height - padding
	else
		col = math.floor((ui.width - width) / 2)
		row = math.floor((ui.height - height) / 2)
	end

	highlights.setup_highlights() -- initialize highlight groups

	buf_id = vim.api.nvim_create_buf(false, true)
	win_id = vim.api.nvim_open_win(buf_id, true, {
		relative = "editor",
		row = row,
		col = col,
		width = width,
		height = height,
		style = "minimal",
		border = "rounded",
		title = " to-dos ",
		title_pos = "center",
		footer = " [?] for help ",
		footer_pos = "center",
	})

	local small_win = create_small_keys_window({
		row = row,
		col = col,
		width = width,
		height = height,
	})

	if small_win then
		vim.api.nvim_create_autocmd("WinClosed", {
			pattern = tostring(win_id),
			callback = function()
				if vim.api.nvim_win_is_valid(small_win) then
					vim.api.nvim_win_close(small_win, true)
				end
			end,
		})
	end

	vim.api.nvim_win_set_option(win_id, "wrap", true)
	vim.api.nvim_win_set_option(win_id, "linebreak", true)
	vim.api.nvim_win_set_option(win_id, "breakindent", true)
	vim.api.nvim_win_set_option(win_id, "breakindentopt", "shift:2")
	vim.api.nvim_win_set_option(win_id, "showbreak", " ")

	local function setup_keymap(key_option, fn)
		local key = config.options.keymaps[key_option]
		if key then
			vim.keymap.set("n", key, fn, { buffer = buf_id, nowait = true })
		end
	end

	setup_keymap("new_todo", function()
		todo_actions.new_todo(function()
			M.render_todos()
		end)
	end)

	setup_keymap("toggle_todo", function()
		todo_actions.toggle_todo(win_id, function()
			M.render_todos()
		end)
	end)

	setup_keymap("delete_todo", function()
		todo_actions.delete_todo(win_id, function()
			M.render_todos()
		end)
	end)

	setup_keymap("delete_completed", function()
		todo_actions.delete_completed(function()
			M.render_todos()
		end)
	end)

	setup_keymap("undo_delete", function()
		if state.undo_delete() then
			M.render_todos()
			vim.notify("Todo restored", vim.log.levels.INFO)
		end
	end)

	setup_keymap("close_window", function()
		M.close_window()
	end)

	setup_keymap("toggle_help", function()
		help_window.create_help_window()
	end)

	setup_keymap("toggle_tags", function()
		tag_window.create_tag_window(win_id)
		M.render_todos()
	end)

	setup_keymap("clear_filter", function()
		state.set_filter(nil)
		M.render_todos()
	end)

	setup_keymap("edit_todo", function()
		todo_actions.edit_todo(win_id, function()
			M.render_todos()
		end)
	end)

	setup_keymap("edit_priorities", function()
		todo_actions.edit_priorities(win_id, function()
			M.render_todos()
		end)
	end)

	setup_keymap("add_due_date", function()
		todo_actions.add_due_date(win_id, function()
			M.render_todos()
		end)
	end)

	setup_keymap("remove_due_date", function()
		todo_actions.remove_due_date(win_id, function()
			M.render_todos()
		end)
	end)

	setup_keymap("add_time_estimation", function()
		todo_actions.add_time_estimation(win_id, function()
			M.render_todos()
		end)
	end)

	setup_keymap("remove_time_estimation", function()
		todo_actions.remove_time_estimation(win_id, function()
			M.render_todos()
		end)
	end)

	setup_keymap("reorder_todo", function()
		todo_actions.reorder_todo(win_id, function()
			M.render_todos()
		end)
	end)

	setup_keymap("open_todo_scratchpad", function()
		scratchpad.open_todo_scratchpad(win_id)
	end)

	setup_keymap("import_todos", function()
		prompt_import(function()
			M.render_todos()
		end)
	end)

	setup_keymap("export_todos", function()
		prompt_export()
	end)

	setup_keymap("import_todos", function()
		prompt_io("import", function()
			M.render_todos()
		end)
	end)

	setup_keymap("export_todos", function()
		prompt_io("export")
	end)
end

function M.toggle_todo_window()
	if win_id and vim.api.nvim_win_is_valid(win_id) then
		M.close_window()
	else
		create_window()
		M.render_todos()
	end
end

function M.close_window()
	-- sequence the closing to ensure that stray modals don't remain.
	help_window.close_help_window()

	if tag_window.close_tag_window then
		tag_window.close_tag_window()
	end

	if search_window.close_search_window then
		search_window.close_search_window()
	end

	-- Reset reordering state when closing the window
	if state.reordering_todo_index ~= nil then
		state.reordering_todo_index = nil
	end

	if win_id and vim.api.nvim_win_is_valid(win_id) then
		vim.api.nvim_win_close(win_id, true)
		win_id = nil
		buf_id = nil
	end
end

return M
