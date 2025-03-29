local vim = vim

local state = require("doit.state")
local config = require("doit.config")
local calendar = require("doit.calendar")

local M = {}

local function get_todo_icon_pattern()
	local done_icon = config.options.formatting.done.icon
	local pending_icon = config.options.formatting.pending.icon
	local in_progress_icon = config.options.formatting.in_progress.icon
	return "^%s+[" .. done_icon .. pending_icon .. in_progress_icon .. "]"
end

local function get_real_todo_index(line_num, filter)
	if not filter then
		return line_num - 1
	end

	local visible_index = 0
	for i, todo in ipairs(state.todos) do
		if todo.text:match("#" .. filter) then
			visible_index = visible_index + 1
			if visible_index == line_num - 2 then
				return i
			end
		end
	end
	return nil
end

local function maybe_render(on_render)
	if on_render then
		on_render()
	end
end

-- Local helper: parse time estimation (ex: "30m", "2h", "1.5d")
function M.parse_time_estimation(time_str)
	local number, unit = time_str:match("^(%d+%.?%d*)([mhdw])$")
	if not (number and unit) then
		return nil, "Invalid format. Use number followed by m/h/d/w (e.g. 30m, 2h, 1d, 0.5w)"
	end

	local hours = tonumber(number)
	if not hours then
		return nil, "Invalid number format"
	end

	if unit == "m" then
		hours = hours / 60
	elseif unit == "d" then
		hours = hours * 24
	elseif unit == "w" then
		hours = hours * 24 * 7
	end

	return hours
end

local function cleanup_priority_selection(select_buf, select_win, keymaps)
	for _, keymap in ipairs(keymaps) do
		pcall(vim.keymap.del, "n", keymap, { buffer = select_buf })
	end
	if select_win and vim.api.nvim_win_is_valid(select_win) then
		vim.api.nvim_win_close(select_win, true)
	end
	if select_buf and vim.api.nvim_buf_is_valid(select_buf) then
		vim.api.nvim_buf_delete(select_buf, { force = true })
	end
end

local function create_priority_selection_window(priorities, selected_priority, title)
	local priority_options = {}
	local keymaps = {
		config.options.keymaps.toggle_priority,
		"<CR>",
		"q",
		"<Esc>",
	}

	for i, priority in ipairs(priorities) do
		local is_selected = selected_priority == priority.name
		priority_options[i] = string.format("(%s) %s", is_selected and "•" or " ", priority.name)
	end

	local select_buf = vim.api.nvim_create_buf(false, true)
	local ui = vim.api.nvim_list_uis()[1]
	local width = 40
	local height = #priority_options + 2
	local row = math.floor((ui.height - height) / 2)
	local col = math.floor((ui.width - width) / 2)

	local select_win = vim.api.nvim_open_win(select_buf, true, {
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		style = "minimal",
		border = "rounded",
		title = " " .. title .. " ",
		title_pos = "center",
		footer = string.format(" %s: select | <Enter>: confirm ", config.options.keymaps.toggle_priority),
		footer_pos = "center",
	})

	vim.api.nvim_buf_set_lines(select_buf, 0, -1, false, priority_options)
	vim.api.nvim_buf_set_option(select_buf, "modifiable", false)

	vim.api.nvim_create_autocmd("BufLeave", {
		buffer = select_buf,
		callback = function()
			cleanup_priority_selection(select_buf, select_win, keymaps)
			return true
		end,
		once = true,
	})

	return select_buf, select_win, keymaps, priority_options
end

local function setup_priority_toggle(select_buf, select_win, selected_priority, priorities, priority_options)
	vim.keymap.set("n", config.options.keymaps.toggle_priority, function()
		if not (select_win and vim.api.nvim_win_is_valid(select_win)) then
			return
		end
		local cursor = vim.api.nvim_win_get_cursor(select_win)
		local line_num = cursor[1]

		-- Update selected priority
		if priorities[line_num] then
			selected_priority.value = priorities[line_num].name
		end

		-- Update all lines to show the current selection
		vim.api.nvim_buf_set_option(select_buf, "modifiable", true)
		for i, priority in ipairs(priorities) do
			local is_selected = selected_priority.value == priority.name
			priority_options[i] = string.format("(%s) %s", is_selected and "•" or " ", priority.name)
		end
		vim.api.nvim_buf_set_lines(select_buf, 0, -1, false, priority_options)
		vim.api.nvim_buf_set_option(select_buf, "modifiable", false)
	end, { buffer = select_buf, nowait = true })
end

local function setup_priority_confirm(select_buf, select_win, keymaps, priorities, selected_priority, callback)
	vim.keymap.set("n", "<CR>", function()
		if not (select_win and vim.api.nvim_win_is_valid(select_win)) then
			return
		end

		cleanup_priority_selection(select_buf, select_win, keymaps)
		callback(selected_priority.value)
	end, { buffer = select_buf, nowait = true })
end

local function setup_priority_close_buttons(select_buf, select_win, keymaps)
	local function close_window()
		cleanup_priority_selection(select_buf, select_win, keymaps)
	end

	vim.keymap.set("n", "q", close_window, { buffer = select_buf, nowait = true })
	vim.keymap.set("n", "<Esc>", close_window, { buffer = select_buf, nowait = true })
end

function M.new_todo(on_render)
	vim.ui.input({ prompt = "New to-do: " }, function(input)
		if input then
			input = input:gsub("\n", " ")
			if input ~= "" then
				-- If user has priority config, ask for priority
				if config.options.priorities and #config.options.priorities > 0 then
					local priorities = config.options.priorities
					local selected_priority = { value = nil }

					local select_buf, select_win, keymaps, priority_options =
						create_priority_selection_window(priorities, selected_priority.value, "Select Priority")

					setup_priority_toggle(select_buf, select_win, selected_priority, priorities, priority_options)

					-- Setup confirmation handling
					setup_priority_confirm(
						select_buf,
						select_win,
						keymaps,
						priorities,
						selected_priority,
						function(selected_priority_name)
							state.add_todo(input, selected_priority_name)
							maybe_render(on_render)
						end
					)

					setup_priority_close_buttons(select_buf, select_win, keymaps)
				else
					-- No priorities configured so just add the todo
					state.add_todo(input)
					maybe_render(on_render)
				end
			end
		end
	end)
end

function M.toggle_todo(win_id, on_render)
	if not win_id or not vim.api.nvim_win_is_valid(win_id) then
		return
	end

	local cursor = vim.api.nvim_win_get_cursor(win_id)
	local line_num = cursor[1]

	local buf_id = vim.api.nvim_win_get_buf(win_id)
	local line_content = vim.api.nvim_buf_get_lines(buf_id, line_num - 1, line_num, false)[1]

	if line_content and line_content:match(get_todo_icon_pattern()) then
		local todo_index = get_real_todo_index(line_num, state.active_filter)
		if todo_index then
			-- Store the current status of the todo
			local was_done = state.todos[todo_index].done
			local will_be_done = state.todos[todo_index].in_progress -- if in_progress, it will become done

			state.toggle_todo(todo_index)

			maybe_render(on_render)

			if was_done == false and will_be_done == true then
				-- Move cursor to first incomplete item
				local first_line = state.active_filter and 3 or 1

				-- Find the first non-empty line with a todo
				local buf_lines = vim.api.nvim_buf_get_lines(buf_id, 0, -1, false)
				for i, line in ipairs(buf_lines) do
					if line:match(get_todo_icon_pattern()) then
						first_line = i
						break
					end
				end

				if vim.api.nvim_win_is_valid(win_id) then
					vim.api.nvim_win_set_cursor(win_id, { first_line, 0 })
				end
			else
				-- For other status changes (pending → in_progress), keep tracking the item
				local todo_ref = state.todos[todo_index]

				-- Find the new position of the todo after sorting
				local new_position
				for i, todo in ipairs(state.todos) do
					if todo == todo_ref then
						new_position = i
						break
					end
				end

				if new_position then
					-- Calculate the new line number based on filtering
					local new_line_num
					if state.active_filter then
						local visible_count = 0
						for i, todo in ipairs(state.todos) do
							if todo.text:match("#" .. state.active_filter) then
								visible_count = visible_count + 1
								if i == new_position then
									new_line_num = visible_count + 2 -- 2 extra lines for filter header
									break
								end
							end
						end
					else
						new_line_num = new_position + 1 -- +1 for the empty line at the top
					end

					-- Update cursor position to the new location
					if new_line_num and vim.api.nvim_win_is_valid(win_id) then
						vim.api.nvim_win_set_cursor(win_id, { new_line_num, 0 })
					end
				end
			end
		end
	end
end

function M.delete_todo(win_id, on_render)
	if not win_id or not vim.api.nvim_win_is_valid(win_id) then
		return
	end

	local cursor = vim.api.nvim_win_get_cursor(win_id)
	local line_num = cursor[1]

	local buf_id = vim.api.nvim_win_get_buf(win_id)
	local line_content = vim.api.nvim_buf_get_lines(buf_id, line_num - 1, line_num, false)[1]

	if line_content and line_content:match(get_todo_icon_pattern()) then
		local todo_index = get_real_todo_index(line_num, state.active_filter)
		if todo_index then
			state.delete_todo_with_confirmation(todo_index, win_id, calendar, function()
				maybe_render(on_render)

				-- Move cursor to first item in the list
				local first_line = state.active_filter and 3 or 1

				-- Find the first non-empty line with a todo
				local buf_lines = vim.api.nvim_buf_get_lines(buf_id, 0, -1, false)
				for i, line in ipairs(buf_lines) do
					if line:match(get_todo_icon_pattern()) then
						first_line = i
						break
					end
				end

				if vim.api.nvim_win_is_valid(win_id) then
					vim.api.nvim_win_set_cursor(win_id, { first_line, 0 })
				end
			end)
		end
	end
end

function M.delete_completed(on_render)
	local win_id = vim.api.nvim_get_current_win()

	state.delete_completed_with_confirmation(win_id, calendar, function()
		maybe_render(on_render)

		-- Find the currently active window
		if win_id and vim.api.nvim_win_is_valid(win_id) then
			local buf_id = vim.api.nvim_win_get_buf(win_id)

			-- Move cursor to first item in the list
			local first_line = state.active_filter and 3 or 1

			-- Find the first non-empty line with a todo
			local buf_lines = vim.api.nvim_buf_get_lines(buf_id, 0, -1, false)
			for i, line in ipairs(buf_lines) do
				if line:match(get_todo_icon_pattern()) then
					first_line = i
					break
				end
			end

			vim.api.nvim_win_set_cursor(win_id, { first_line, 0 })
		end
	end)
end

function M.remove_duplicates(on_render)
	local dups = state.remove_duplicates()
	vim.notify("Removed " .. dups .. " duplicates.", vim.log.levels.INFO)
	maybe_render(on_render)
end

function M.edit_todo(win_id, on_render)
	local cursor = vim.api.nvim_win_get_cursor(win_id)
	local line_num = cursor[1]

	local buf_id = vim.api.nvim_win_get_buf(win_id)
	local line_content = vim.api.nvim_buf_get_lines(buf_id, line_num - 1, line_num, false)[1]

	if line_content:match(get_todo_icon_pattern()) then
		local todo_index = get_real_todo_index(line_num, state.active_filter)
		if todo_index then
			vim.ui.input(
				{ zindex = 300, prompt = "Edit to-do: ", default = state.todos[todo_index].text },
				function(input)
					if input and input ~= "" then
						state.todos[todo_index].text = input
						state.save_to_disk()
						maybe_render(on_render)
					end
				end
			)
		end
	end
end

function M.edit_priorities(win_id, on_render)
	local cursor = vim.api.nvim_win_get_cursor(win_id)
	local line_num = cursor[1]

	local buf_id = vim.api.nvim_win_get_buf(win_id)
	local line_content = vim.api.nvim_buf_get_lines(buf_id, line_num - 1, line_num, false)[1]

	if line_content:match(get_todo_icon_pattern()) then
		local todo_index = get_real_todo_index(line_num, state.active_filter)
		if todo_index then
			if config.options.priorities and #config.options.priorities > 0 then
				local priorities = config.options.priorities
				local current_todo = state.todos[todo_index]
				local selected_priority = { value = current_todo.priorities }

				-- Save a reference to the todo before changing it
				local todo_ref = current_todo

				local select_buf, select_win, keymaps, priority_options =
					create_priority_selection_window(priorities, selected_priority.value, "Edit Priority")

				setup_priority_toggle(select_buf, select_win, selected_priority, priorities, priority_options)

				setup_priority_confirm(
					select_buf,
					select_win,
					keymaps,
					priorities,
					selected_priority,
					function(selected_priority_name)
						-- Update the priority
						state.todos[todo_index].priorities = selected_priority_name
						state.save_to_disk()

						-- Render the updated list
						maybe_render(on_render)

						-- Find the new position of the todo after sorting
						local new_position
						for i, todo in ipairs(state.todos) do
							if todo == todo_ref then
								new_position = i
								break
							end
						end

						if new_position then
							-- Calculate the new line number based on filtering
							local new_line_num
							if state.active_filter then
								local visible_count = 0
								for i, todo in ipairs(state.todos) do
									if todo.text:match("#" .. state.active_filter) then
										visible_count = visible_count + 1
										if i == new_position then
											new_line_num = visible_count + 2 -- 2 extra lines for filter header
											break
										end
									end
								end
							else
								new_line_num = new_position + 1 -- +1 for the empty line at the top
							end

							-- Update cursor position to the new location
							vim.notify("New line number: " .. new_line_num, vim.log.levels.INFO)
							if new_line_num and vim.api.nvim_win_is_valid(win_id) then
								vim.notify("Setting cursor to line number: " .. new_line_num, vim.log.levels.INFO)
								vim.api.nvim_win_set_cursor(win_id, { new_line_num, 0 })
							end
						end
					end
				)

				setup_priority_close_buttons(select_buf, select_win, keymaps)
			end
		end
	end
end

function M.add_time_estimation(win_id, on_render)
	local line_num = vim.api.nvim_win_get_cursor(win_id)[1]
	local todo_index = get_real_todo_index(line_num, state.active_filter)

	if not todo_index then
		return
	end

	vim.ui.input({
		prompt = "Estimated completion time (e.g., 15m, 2h, 1d, 0.5w): ",
		default = "",
	}, function(input)
		if input and input ~= "" then
			local hours, err = M.parse_time_estimation(input)
			if hours then
				state.todos[todo_index].estimated_hours = hours
				state.save_to_disk()
				vim.notify("Time estimation added successfully", vim.log.levels.INFO)
			else
				vim.notify("Error adding time estimation: " .. (err or "Unknown error"), vim.log.levels.ERROR)
			end
			maybe_render(on_render)
		end
	end)
end

function M.remove_time_estimation(win_id, on_render)
	local line_num = vim.api.nvim_win_get_cursor(win_id)[1]
	local todo_index = get_real_todo_index(line_num, state.active_filter)

	if todo_index and state.todos[todo_index] then
		state.todos[todo_index].estimated_hours = nil
		state.save_to_disk()
		vim.notify("Time estimation removed successfully", vim.log.levels.INFO)
		maybe_render(on_render)
	else
		vim.notify("Error removing time estimation", vim.log.levels.ERROR)
	end
end

function M.add_due_date(win_id, on_render)
	local line_num = vim.api.nvim_win_get_cursor(win_id)[1]
	local todo_index = get_real_todo_index(line_num, state.active_filter)

	if not todo_index then
		return
	end

	calendar.create(function(date_str)
		if date_str and date_str ~= "" then
			local success, err = state.add_due_date(todo_index, date_str)
			if success then
				vim.notify("Due date added successfully", vim.log.levels.INFO)
			else
				vim.notify("Error adding due date: " .. (err or "Unknown error"), vim.log.levels.ERROR)
			end
			maybe_render(on_render)
		end
	end, { language = "en" })
end

function M.remove_due_date(win_id, on_render)
	local line_num = vim.api.nvim_win_get_cursor(win_id)[1]
	local todo_index = get_real_todo_index(line_num, state.active_filter)

	if todo_index then
		local success = state.remove_due_date(todo_index)
		if success then
			vim.notify("Due date removed successfully", vim.log.levels.INFO)
		else
			vim.notify("Error removing due date", vim.log.levels.ERROR)
		end
		maybe_render(on_render)
	else
		vim.notify("Error: Could not find todo item", vim.log.levels.ERROR)
	end
end

function M.reorder_todo(win_id, on_render)
	if not win_id or not vim.api.nvim_win_is_valid(win_id) then
		return
	end

	local cursor = vim.api.nvim_win_get_cursor(win_id)
	local line_num = cursor[1]

	-- Get the current todo index
	local todo_index = line_num - (state.active_filter and 3 or 1)
	if todo_index < 1 or todo_index > #state.todos then
		return
	end

	local buf_id = vim.api.nvim_win_get_buf(win_id)

	vim.api.nvim_buf_set_option(buf_id, "modifiable", true)

	-- Determine the actual index in todos array if using filter
	local real_index
	if state.active_filter then
		local visible_count = 0
		for i, todo in ipairs(state.todos) do
			if todo.text:match("#" .. state.active_filter) then
				visible_count = visible_count + 1
				if visible_count == todo_index then
					real_index = i
					break
				end
			end
		end
	else
		real_index = todo_index
	end

	state.reordering_todo_index = real_index

	-- Highlight the current line
	local ns_id = vim.api.nvim_create_namespace("doit_reorder")
	vim.api.nvim_buf_clear_namespace(buf_id, ns_id, 0, -1)
	vim.api.nvim_buf_add_highlight(buf_id, ns_id, "IncSearch", line_num - 1, 0, -1)

	local reorder_key = config.options.keymaps.reorder_todo

	local old_r_keymap = vim.fn.maparg(reorder_key, "n", false, true)

	local function exit_reorder_mode()
		vim.api.nvim_buf_set_option(buf_id, "modifiable", true)
		vim.api.nvim_buf_clear_namespace(buf_id, ns_id, 0, -1)

		state.reordering_todo_index = nil

		-- Safely remove keymaps with pcall to prevent errors if mapping doesn't exist
		local function safe_del_keymap(key)
			pcall(function()
				vim.keymap.del("n", key, { buffer = buf_id })
			end)
		end

		safe_del_keymap("<Down>")
		safe_del_keymap("<Up>")
		safe_del_keymap(reorder_key)
		safe_del_keymap("<Esc>")

		-- Always restore the reorder keybinding to ensure it can be re-entered
		pcall(function()
			vim.keymap.set("n", reorder_key, function()
				M.reorder_todo(win_id, on_render)
			end, { buffer = buf_id, nowait = true })
		end)

		if config.options.development_mode then
			vim.notify("Reordering mode exited and saved", vim.log.levels.INFO)
		end
	end

	local function update_order_indices()
		-- Reset all todos' order_index property to match their position in the array
		for i, todo in ipairs(state.todos) do
			todo.order_index = i
		end
		state.save_to_disk()
	end

	local function move_todo(buf_id, win_id, line_num, ns_id, direction, on_render)
		vim.api.nvim_buf_set_option(buf_id, "modifiable", true)

		local current_index = line_num - (state.active_filter and 3 or 1)

		if direction == "up" and current_index <= 1 then
			return
		end

		-- Get the real index in state.todos
		local real_index
		if state.active_filter then
			local visible_count = 0
			for i, todo in ipairs(state.todos) do
				if todo.text:match("#" .. state.active_filter) then
					visible_count = visible_count + 1
					if visible_count == current_index then
						real_index = i
						break
					end
				end
			end
		else
			real_index = current_index
		end

		-- Additional validation
		if not real_index then
			return
		end
		if direction == "down" and real_index >= #state.todos then
			return
		end
		if direction == "up" and real_index <= 1 then
			return
		end

		-- Store the current todo for tracking
		local current_todo = state.todos[real_index]

		-- Find next/previous todo within filter
		local target_index
		if direction == "down" then
			for i = real_index + 1, #state.todos do
				if not state.active_filter or state.todos[i].text:match("#" .. state.active_filter) then
					target_index = i
					break
				end
			end

			if not target_index then
				return -- No visible todo to swap with
			end
		else -- up
			for i = real_index - 1, 1, -1 do
				if not state.active_filter or state.todos[i].text:match("#" .. state.active_filter) then
					target_index = i
					break
				end
			end

			if not target_index then
				return -- No visible todo to swap with
			end
		end

		-- Swap order indices for reordering
		local current_order = state.todos[real_index].order_index
		local target_order = state.todos[target_index].order_index

		-- Swap the order indices
		state.todos[real_index].order_index = target_order
		state.todos[target_index].order_index = current_order

		state.sort_todos()

		-- Find the new position of our todo after sorting
		local new_position
		for i, todo in ipairs(state.todos) do
			if todo == current_todo then
				new_position = i
				break
			end
		end

		if not new_position then
			return -- Something went wrong, couldn't find the todo
		end

		state.reordering_todo_index = new_position

		if on_render then
			on_render()
		end

		-- Update cursor position to follow the moved todo
		local new_line_num = 0

		if state.active_filter then
			-- Recalculate the cursor position when filtered
			local visible_count = 0
			for i, todo in ipairs(state.todos) do
				if todo.text:match("#" .. state.active_filter) then
					visible_count = visible_count + 1
					if i == new_position then
						new_line_num = visible_count + (state.active_filter and 3 or 1)
						break
					end
				end
			end
		else
			-- Unfiltered view is simpler
			new_line_num = new_position + 1
		end

		if new_line_num > 0 then
			vim.api.nvim_win_set_cursor(win_id, { new_line_num, 0 })
			vim.api.nvim_buf_clear_namespace(buf_id, ns_id, 0, -1)
			vim.api.nvim_buf_add_highlight(buf_id, ns_id, "IncSearch", new_line_num - 1, 0, -1)
		end
	end

	vim.keymap.set("n", "<Down>", function()
		move_todo(buf_id, win_id, vim.api.nvim_win_get_cursor(win_id)[1], ns_id, "down", on_render)
	end, { buffer = buf_id, nowait = true })

	vim.keymap.set("n", "<Up>", function()
		move_todo(buf_id, win_id, vim.api.nvim_win_get_cursor(win_id)[1], ns_id, "up", on_render)
	end, { buffer = buf_id, nowait = true })

	local reorder_key = config.options.keymaps and config.options.keymaps.reorder_todo or "r"
	vim.keymap.set("n", reorder_key, function()
		update_order_indices()
		exit_reorder_mode()
		if on_render then
			on_render()
		end
	end, { buffer = buf_id, nowait = true })

	vim.keymap.set("n", "<Esc>", function()
		update_order_indices()
		exit_reorder_mode()
		if on_render then
			on_render()
		end
	end, { buffer = buf_id, nowait = true })
end

return M
