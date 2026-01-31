local M = {}

M.buf = nil
M.win = nil

function M.is_open()
	return M.win and vim.api.nvim_win_is_valid(M.win)
end

function M.close()
	-- Check if we can safely close the window
	local win_count = #vim.api.nvim_list_wins()

	if M.win and vim.api.nvim_win_is_valid(M.win) then
		if win_count > 1 then
			-- Safe to close the window
			vim.api.nvim_win_close(M.win, true)
		else
			-- This is the last window, switch to a scratch buffer instead
			local scratch = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_win_set_buf(M.win, scratch)
		end
	end

	if M.buf and vim.api.nvim_buf_is_valid(M.buf) then
		vim.api.nvim_buf_delete(M.buf, { force = true })
	end

	M.win = nil
	M.buf = nil
end

function M.open()
	if M.is_open() then
		return
	end

	M.buf = vim.api.nvim_create_buf(false, true)

	vim.api.nvim_buf_set_option(M.buf, "bufhidden", "wipe")
	vim.api.nvim_buf_set_option(M.buf, "filetype", "doit_dashboard")
	vim.api.nvim_buf_set_option(M.buf, "buftype", "nofile")
	vim.api.nvim_buf_set_option(M.buf, "swapfile", false)
	vim.api.nvim_buf_set_option(M.buf, "modifiable", false)

	M.win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(M.win, M.buf)

	vim.api.nvim_win_set_option(M.win, "number", false)
	vim.api.nvim_win_set_option(M.win, "relativenumber", false)
	vim.api.nvim_win_set_option(M.win, "cursorline", false)
	vim.api.nvim_win_set_option(M.win, "signcolumn", "no")
	vim.api.nvim_win_set_option(M.win, "foldcolumn", "0")

	M.render()

	vim.keymap.set("n", "q", function()
		M.close()
	end, { buffer = M.buf, nowait = true, silent = true })

	vim.keymap.set("n", "<Esc>", function()
		M.close()
	end, { buffer = M.buf, nowait = true, silent = true })

	vim.api.nvim_create_autocmd("BufLeave", {
		buffer = M.buf,
		callback = function()
			vim.defer_fn(function()
				-- Only close if the dashboard buffer is no longer displayed in any window
				if M.buf and vim.api.nvim_buf_is_valid(M.buf) then
					local wins = vim.fn.win_findbuf(M.buf)
					if #wins == 0 then
						M.close()
					end
				end
			end, 0)
		end,
	})
end

function M.render()
	if not M.buf or not vim.api.nvim_buf_is_valid(M.buf) then
		return
	end

	local doit = require("doit")
	local content = {}

	local function center(text, width)
		local padding = math.floor((width - #text) / 2)
		return string.rep(" ", padding) .. text
	end

	local function pad_right(text, width)
		return text .. string.rep(" ", width - #text)
	end

	local width = vim.api.nvim_win_get_width(M.win or 0)
	local max_content_width = 100 -- Maximum width for content
	local content_width = math.min(width, max_content_width)
	local left_margin = math.floor((width - content_width) / 2)
	local col_width = math.floor(content_width / 2) - 4

	table.insert(content, "")
	table.insert(content, "")
	table.insert(content, center("    ____        ______ ", width))
	table.insert(content, center("   / __ \\____  /  _/ /_", width))
	table.insert(content, center("  / / / / __ \\ / // __/", width))
	table.insert(content, center(" / /_/ / /_/ // // /_  ", width))
	table.insert(content, center("/_____/\\____/___/\\__/  ", width))
	table.insert(content, "")
	table.insert(content, center("v" .. (doit.version or "2.0.0"), width))
	table.insert(content, "")
	table.insert(content, "")

	-- Build left and right columns
	local left_col = {}
	local right_col = {}

	-- Left column: Todos
	table.insert(left_col, "T O D O S")
	table.insert(left_col, "──────────")
	if doit.todos then
		if doit.todos.state.todo_lists then
			local active_list = doit.todos.state.todo_lists.active or "daily"
			-- Count only active todos (exclude completed)
			local todo_count = 0
			local todos = doit.todos.state.todos or {}
			for _, todo in ipairs(todos) do
				if not todo.done then
					todo_count = todo_count + 1
				end
			end
			local lists = doit.todos.state.get_available_lists()
			local list_count = #lists

			table.insert(left_col, "Lists: " .. list_count)
			table.insert(left_col, "Active: " .. active_list)
			table.insert(left_col, "Count: " .. todo_count)
		else
			-- Count only active todos
			local todo_count = 0
			local todos = doit.todos.state.todos or {}
			for _, todo in ipairs(todos) do
				if not todo.done then
					todo_count = todo_count + 1
				end
			end
			table.insert(left_col, "Count: " .. todo_count)
		end
	else
		table.insert(left_col, "No todos module")
	end
	table.insert(left_col, "")

	-- Left column: Events
	table.insert(left_col, "T O D A Y")
	table.insert(left_col, "─────────────")
	if doit.calendar then
		local today = os.date("%Y-%m-%d")
		local end_date = today

		local ok, icalbuddy = pcall(require, "doit.modules.calendar.icalbuddy")
		local events = {}
		if ok then
			local success, result = pcall(
				icalbuddy.get_events,
				today,
				end_date,
				doit.calendar.config and doit.calendar.config.icalbuddy or {}
			)
			if success then
				events = result or {}
			end
		end

		local upcoming = {}
		for _, event in ipairs(events) do
			if not event.all_day and event.start_time then
				table.insert(upcoming, event)
			end
		end

		table.sort(upcoming, function(a, b)
			if a.date == b.date then
				return (a.start_time or "") < (b.start_time or "")
			end
			return a.date < b.date
		end)

		local count = 0
		for _, event in ipairs(upcoming) do
			local time_str = event.start_time or ""
			if event.end_time then
				time_str = time_str .. "-" .. event.end_time
			end

			local event_line = string.format("%s: %s", time_str, event.title)
			if #event_line > col_width - 2 then
				event_line = event_line:sub(1, col_width - 5) .. "..."
			end

			table.insert(left_col, event_line)
			count = count + 1
		end

		if count == 0 then
			table.insert(left_col, "No events today")
		end
	else
		table.insert(left_col, "No calendar module")
	end

	-- Right column: Commands
	table.insert(right_col, "C O M M A N D S")
	table.insert(right_col, "                    ────────────────")
	table.insert(right_col, ":DoIt - Main todo window")

	if doit.todos then
		table.insert(right_col, ":DoItList - Quick todo list")
		table.insert(right_col, ":DoItLists - Manage lists")
	end

	if doit.notes then
		table.insert(right_col, ":DoItNotes - Notes interface")
	end

	if doit.calendar then
		table.insert(right_col, ":DoItCalendar - Calendar view")
	end

	table.insert(right_col, "")
	table.insert(right_col, "P L U G I N S")
	table.insert(right_col, "─────────────────")

	if doit.core and doit.core.registry then
		table.insert(right_col, ":DoItPlugins list")
		table.insert(right_col, ":DoItPlugins info <name>")
		table.insert(right_col, ":DoItPlugins install <name>")
		table.insert(right_col, ":DoItPlugins discover")
	else
		table.insert(right_col, "No plugin system")
	end

	-- Merge left and right columns
	local max_lines = math.max(#left_col, #right_col)
	local gutter = 6 -- Space between columns
	local margin = string.rep(" ", left_margin)

	for i = 1, max_lines do
		local left = left_col[i] or ""
		local right = right_col[i] or ""

		-- Truncate left if too long
		if #left > col_width then
			left = left:sub(1, col_width - 3) .. "..."
		end

		-- Pad left column to col_width
		local left_padded = left .. string.rep(" ", col_width - #left)

		local line = margin .. "  " .. left_padded .. string.rep(" ", gutter) .. right
		table.insert(content, line)
	end

	-- Modules section (at bottom)
	table.insert(content, "")
	table.insert(content, "")

	local registry_modules = {}
	if doit.core and doit.core.registry then
		registry_modules = doit.core.registry.list()
	end

	if #registry_modules > 0 then
		table.insert(content, center("MODULES", width))
		table.insert(
			content,
			center("                                    ────────────────", width)
		)
		for _, module in ipairs(registry_modules) do
			local version = module.version and (" v" .. module.version) or ""
			local custom = module.custom and " [custom]" or ""
			table.insert(content, center(module.name .. version .. custom, width))
		end
	end

	vim.api.nvim_buf_set_option(M.buf, "modifiable", true)
	vim.api.nvim_buf_set_lines(M.buf, 0, -1, false, content)
	vim.api.nvim_buf_set_option(M.buf, "modifiable", false)
end

return M
