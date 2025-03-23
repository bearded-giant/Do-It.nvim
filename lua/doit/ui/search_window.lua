local vim = vim

local state = require("doit.state")
local config = require("doit.config")

local M = {}

local search_win_id = nil
local search_buf_id = nil
local ns_id = vim.api.nvim_create_namespace("doit_search")

function M.is_search_window_open()
	return search_win_id ~= nil and vim.api.nvim_win_is_valid(search_win_id)
end

function M.close_search_window()
	if M.is_search_window_open() then
		vim.api.nvim_win_close(search_win_id, true)
		search_win_id = nil
		search_buf_id = nil
		return true
	end
	return false
end

local function handle_search_query(query, main_win_id)
	if not search_buf_id or not vim.api.nvim_buf_is_valid(search_buf_id) then
		return
	end

	vim.api.nvim_buf_set_option(search_buf_id, "modifiable", true)
	vim.api.nvim_buf_clear_namespace(search_buf_id, ns_id, 0, -1)

	if not query or query == "" then
		if search_win_id and vim.api.nvim_win_is_valid(search_win_id) then
			vim.api.nvim_win_close(search_win_id, true)
			search_win_id = nil
			search_buf_id = nil
			if main_win_id and vim.api.nvim_win_is_valid(main_win_id) then
				vim.api.nvim_set_current_win(main_win_id)
			end
		end
		return
	end

	local results = state.search_todos(query)
	local lines = {
		"  Search Results for: " .. query,
		"",
	}

	local done_icon = config.options.formatting.done.icon
	local pending_icon = config.options.formatting.pending.icon

	local valid_lines = {}
	if #results > 0 then
		for _, result in ipairs(results) do
			local icon = result.todo.done and done_icon or pending_icon
			local line = string.format("  %s %s", icon, result.todo.text)
			table.insert(lines, line)
			table.insert(valid_lines, { line_index = #lines, result = result })
		end
	else
		table.insert(lines, "  No results found")
	end

	vim.api.nvim_buf_set_lines(search_buf_id, 0, -1, false, lines)

	-- apply highlight
	for i, line in ipairs(lines) do
		local line_nr = i - 1
		if line:match("^%s+[" .. done_icon .. pending_icon .. "]") then
			local hl_group = line:match(done_icon) and "DoItDone" or "DoItPending"
			vim.api.nvim_buf_add_highlight(search_buf_id, ns_id, hl_group, line_nr, 0, -1)

			-- tag highlight
			for tag in line:gmatch("#(%w+)") do
				local start_idx = line:find("#" .. tag) - 1
				vim.api.nvim_buf_add_highlight(search_buf_id, ns_id, "Type", line_nr, start_idx, start_idx + #tag + 1)
			end
		elseif line:match("Search Results") then
			vim.api.nvim_buf_add_highlight(search_buf_id, ns_id, "WarningMsg", line_nr, 0, -1)
		end
	end

	vim.api.nvim_buf_set_option(search_buf_id, "modifiable", false)

	-- confirm config and keymaps exist
	local close_key = "q"
	if config and config.options and config.options.keymaps and config.options.keymaps.close_window then
		close_key = config.options.keymaps.close_window
	end

	vim.keymap.set("n", close_key, function()
		M.close_search_window()
		if main_win_id and vim.api.nvim_win_is_valid(main_win_id) then
			vim.api.nvim_set_current_win(main_win_id)
		end
	end, { buffer = search_buf_id, nowait = true })

	vim.keymap.set("n", "<CR>", function()
		local current_line = vim.api.nvim_win_get_cursor(search_win_id)[1]
		local matched_result = nil
		for _, item in ipairs(valid_lines) do
			if item.line_index == current_line then
				matched_result = item.result
				break
			end
		end
		if matched_result then
			vim.api.nvim_win_close(search_win_id, true)
			search_win_id = nil
			search_buf_id = nil
			if main_win_id and vim.api.nvim_win_is_valid(main_win_id) then
				vim.api.nvim_set_current_win(main_win_id)
				vim.api.nvim_win_set_cursor(main_win_id, { matched_result.lnum + 1, 3 })
			end
		end
	end, { buffer = search_buf_id, nowait = true })
end

function M.create_search_window(main_win_id)
	if search_win_id and vim.api.nvim_win_is_valid(search_win_id) then
		vim.api.nvim_set_current_win(search_win_id)
		vim.ui.input({ prompt = "Search todos: " }, function(query)
			handle_search_query(query, main_win_id)
		end)
		return
	end

	if search_win_id and not vim.api.nvim_win_is_valid(search_win_id) then
		search_win_id = nil
		search_buf_id = nil
	end

	search_buf_id = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_option(search_buf_id, "buflisted", true)
	vim.api.nvim_buf_set_option(search_buf_id, "modifiable", false)
	vim.api.nvim_buf_set_option(search_buf_id, "filetype", "todo_search")

	local width = 40
	local height = 10
	local ui = vim.api.nvim_list_uis()[1]
	local main_width = 40
	local main_col = math.floor((ui.width - main_width) / 2)
	local col = main_col - width - 2
	local row = math.floor((ui.height - height) / 2)

	search_win_id = vim.api.nvim_open_win(search_buf_id, true, {
		relative = "editor",
		row = row,
		col = col,
		width = width,
		height = height,
		style = "minimal",
		border = "rounded",
		title = " Search Todos ",
		title_pos = "center",
	})

	vim.ui.input({ prompt = "Search todos: " }, function(query)
		handle_search_query(query, main_win_id)
	end)

	vim.api.nvim_create_autocmd("WinClosed", {
		pattern = tostring(main_win_id),
		callback = function()
			if search_win_id and vim.api.nvim_win_is_valid(search_win_id) then
				vim.api.nvim_win_close(search_win_id, true)
				search_win_id = nil
				search_buf_id = nil
			end
		end,
	})
end

return M

