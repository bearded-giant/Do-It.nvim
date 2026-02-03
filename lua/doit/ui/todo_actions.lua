local vim = vim

local config = require("doit.config")
local calendar = require("doit.calendar")
local multiline_input = require("doit.core.ui.multiline_input")

-- Lazy loading of todo module and state
local todo_module = nil
local state = nil

local function get_todo_module()
    if not todo_module then
        local core = require("doit.core")
        todo_module = core.get_module("todos")
        
        -- If not loaded, try to load it
        if not todo_module then
            local doit = require("doit")
            if doit.load_module then
                todo_module = doit.load_module("todos", {})
            end
        end
    end
    return todo_module
end

-- Function to ensure state is loaded - always get fresh reference
local function ensure_state_loaded()
    local module = get_todo_module()
    if module and module.state then
        -- Always update reference to get current list state
        state = module.state
        return state
    else
        -- Fallback only if module not available
        if not state then
            -- Initialize empty state as last resort
            state = {
                todos = {},
                active_filter = nil,
                deleted_todos = {},
                add_todo = function() end,
                save_to_disk = function() end,
                sort_todos = function() end,
                apply_filter = function(self) return self.todos end,
            }
        end
        return state
    end
end

local M = {}

local function get_todo_icon_pattern()
	local done_icon = config.options.formatting.done.icon
	local pending_icon = config.options.formatting.pending.icon
	local in_progress_icon = config.options.formatting.in_progress.icon
	-- pattern allows optional notes icon (any non-space chars) before status icon
	return "^%s+.-%s*[" .. done_icon .. pending_icon .. in_progress_icon .. "]"
end

local function find_bullet_line_for_cursor(buf_id, line_num)
	local icon_pattern = get_todo_icon_pattern()

	local current_line = line_num
	while current_line > 0 do
		local line_content = vim.api.nvim_buf_get_lines(buf_id, current_line - 1, current_line, false)[1]
		if not line_content then
			break
		end

		if line_content:match(icon_pattern) then
			return current_line
		end

		if line_content:match("^%s*$") then
			break
		end

		current_line = current_line - 1
	end

	return nil
end

local function get_real_todo_index(line_num, filter)
	ensure_state_loaded()

	-- Calculate header offset
	local line_offset = 1  -- blank line at top
	if state.active_filter then
		line_offset = line_offset + 2  -- blank line + filter text
	end
	if state.active_category then
		line_offset = line_offset + 2  -- blank line + category text
	end

	-- Check show_completed config (must match rendering logic)
	local show_completed = true
	if config.options and config.options.modules and config.options.modules.todos then
		if config.options.modules.todos.show_completed == false then
			show_completed = false
		end
	end

	-- First todo starts at line_offset + 1 (after all headers)
	local current_line = line_offset + 1

	for i, todo in ipairs(state.todos) do
		-- Skip completed todos if show_completed is false (must match rendering)
		if todo.done and not show_completed then
			goto continue
		end

		local show_by_tag = not filter or todo.text:match("#" .. filter)
		local show_by_category = true

		-- Check category filter
		if state.active_category then
			local module = get_todo_module()
			if module and module.state and module.state.get_todo_category then
				local todo_category_id = module.state.get_todo_category(todo.id)
				show_by_category = (todo_category_id == state.active_category) or
								  (state.active_category == "uncategorized" and
								   (todo_category_id == "uncategorized" or not todo_category_id))
			else
				show_by_category = (todo.category == state.active_category) or
								  (state.active_category == "Uncategorized" and
								   (not todo.category or todo.category == ""))
			end
		end

		if show_by_tag and show_by_category then
			local text_lines = vim.split(todo.text, "\n", { plain = true })
			local num_lines = #text_lines

			-- Check if line_num falls within this todo's line range
			if line_num >= current_line and line_num < current_line + num_lines then
				return i
			end

			current_line = current_line + num_lines
		end
		::continue::
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
	pcall(vim.keymap.del, "n", "<CR>", { buffer = select_buf })

	-- Defer window/buffer cleanup to avoid treesitter race condition
	vim.schedule(function()
		if select_win and vim.api.nvim_win_is_valid(select_win) then
			pcall(vim.api.nvim_win_close, select_win, true)
		end
		if select_buf and vim.api.nvim_buf_is_valid(select_buf) then
			pcall(vim.api.nvim_buf_delete, select_buf, { force = true })
		end
	end)
end

local function create_priority_selection_window(priorities, selected_priority, title)
	local priority_options = {}
	local keymaps = {
		config.options.keymaps.toggle_priority,
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
	vim.api.nvim_buf_set_option(select_buf, "buftype", "nofile")

	vim.api.nvim_create_autocmd("BufLeave", {
		buffer = select_buf,
		callback = function()
			cleanup_priority_selection(select_buf, select_win, keymaps)
			return true
		end,
		once = true,
	})

	vim.cmd("startinsert!")
	vim.cmd("stopinsert")

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
	ensure_state_loaded()

	multiline_input.create({
		prompt = "New to-do",
		on_submit = function(input)
			vim.cmd("echo ''")

			if input and input ~= "" then
				if config.options.priorities and #config.options.priorities > 0 then
					vim.schedule(function()
						local priorities = config.options.priorities
						local selected_priority = { value = nil }

						local select_buf, select_win, keymaps, priority_options =
							create_priority_selection_window(priorities, selected_priority.value, "Select Priority")

						setup_priority_toggle(select_buf, select_win, selected_priority, priorities, priority_options)

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
					end)
				else
					state.add_todo(input)
					maybe_render(on_render)
				end
			end
		end,
		on_cancel = function()
			vim.cmd("echo ''")
		end
	})
end

function M.toggle_todo(win_id, on_render)
	ensure_state_loaded()
	if not win_id or not vim.api.nvim_win_is_valid(win_id) then
		return
	end

	local cursor = vim.api.nvim_win_get_cursor(win_id)
	local line_num = cursor[1]

	local buf_id = vim.api.nvim_win_get_buf(win_id)

	local bullet_line = find_bullet_line_for_cursor(buf_id, line_num)
	if not bullet_line then
		return
	end

	local todo_index = get_real_todo_index(bullet_line, state.active_filter)
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

			local total_lines = vim.api.nvim_buf_line_count(buf_id)
			if first_line > total_lines then
				first_line = total_lines
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
				-- Calculate the new line number accounting for multiline todos
				local new_line_num
				local line_offset = 1
				if state.active_filter then
					line_offset = line_offset + 2
				end
				if state.active_category then
					line_offset = line_offset + 2
				end

				local current_line = line_offset
				for i, todo in ipairs(state.todos) do
					if i == new_position then
						new_line_num = current_line
						break
					end
					local show_by_tag = not state.active_filter or todo.text:match("#" .. state.active_filter)
					if show_by_tag then
						local text_lines = vim.split(todo.text, "\n", { plain = true })
						current_line = current_line + #text_lines
					end
				end

				-- Validate cursor position
				if new_line_num then
					local total_lines = vim.api.nvim_buf_line_count(buf_id)
					if new_line_num > total_lines then
						new_line_num = total_lines
					elseif new_line_num < 1 then
						new_line_num = 1
					end

					if vim.api.nvim_win_is_valid(win_id) then
						vim.api.nvim_win_set_cursor(win_id, { new_line_num, 0 })
					end
				end
			end
		end
	end
end

function M.revert_to_pending(win_id, on_render)
	ensure_state_loaded()
	if not win_id or not vim.api.nvim_win_is_valid(win_id) then
		return
	end

	local cursor = vim.api.nvim_win_get_cursor(win_id)
	local line_num = cursor[1]

	local buf_id = vim.api.nvim_win_get_buf(win_id)

	local bullet_line = find_bullet_line_for_cursor(buf_id, line_num)
	if not bullet_line then
		return
	end

	local todo_index = get_real_todo_index(bullet_line, state.active_filter)
	if todo_index then
		local todo = state.todos[todo_index]
		if todo.in_progress or todo.done then
			state.revert_to_pending(todo_index)
			maybe_render(on_render)
			vim.notify("Todo reverted to pending", vim.log.levels.INFO)
		else
			vim.notify("Todo is already pending", vim.log.levels.INFO)
		end
	end
end

function M.delete_todo(win_id, on_render)
	ensure_state_loaded()
	if not win_id or not vim.api.nvim_win_is_valid(win_id) then
		return
	end

	local cursor = vim.api.nvim_win_get_cursor(win_id)
	local line_num = cursor[1]

	local buf_id = vim.api.nvim_win_get_buf(win_id)

	local bullet_line = find_bullet_line_for_cursor(buf_id, line_num)
	if not bullet_line then
		return
	end

	local todo_index = get_real_todo_index(bullet_line, state.active_filter)
	if todo_index then
		-- Check if confirmation is needed (for todos with calendar events)
		local todo = state.todos[todo_index]
		local needs_confirmation = todo and todo.calendar_event_id

		local function do_delete()
			state.delete_todo(todo_index)
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

			-- Validate cursor position
			local total_lines = vim.api.nvim_buf_line_count(buf_id)
			if first_line > total_lines then
				first_line = total_lines
			elseif first_line < 1 then
				first_line = 1
			end

			if vim.api.nvim_win_is_valid(win_id) then
				vim.api.nvim_win_set_cursor(win_id, { first_line, 0 })
			end
		end

		-- If confirmation is needed, show a prompt
		if needs_confirmation then
			vim.ui.select({ "Yes", "No" }, {
				prompt = "Delete todo with calendar event?"
			}, function(choice)
				if choice == "Yes" then
					-- Also delete calendar event if module is available
					if calendar and calendar.delete_event then
						pcall(calendar.delete_event, todo.calendar_event_id)
					end
					do_delete()
				end
			end)
		else
			-- No confirmation needed, delete directly
			do_delete()
		end
	end
end

function M.delete_completed(on_render)
	ensure_state_loaded()  -- Ensure state is loaded
	local win_id = vim.api.nvim_get_current_win()

	if state.delete_completed_with_confirmation then
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

			-- Validate cursor position
			local total_lines = vim.api.nvim_buf_line_count(buf_id)
			if first_line > total_lines then
				first_line = total_lines
			elseif first_line < 1 then
				first_line = 1
			end

			vim.api.nvim_win_set_cursor(win_id, { first_line, 0 })
		end
	end)
	end
end

-- Link a todo to a note (UI for note selection)
function M.link_to_note(win_id, on_render)
    ensure_state_loaded()
    if not win_id or not vim.api.nvim_win_is_valid(win_id) then
        return
    end

    local cursor = vim.api.nvim_win_get_cursor(win_id)
    local line_num = cursor[1]

    local buf_id = vim.api.nvim_win_get_buf(win_id)

    local bullet_line = find_bullet_line_for_cursor(buf_id, line_num)
    if not bullet_line then
        return
    end

    local todo_index = get_real_todo_index(bullet_line, state.active_filter)
    if todo_index then
            -- Try to get a reference to the notes module
            local core = package.loaded["doit.core"]
            local notes_module = core and core.get_module and core.get_module("notes")
            
            if not notes_module or not notes_module.state then
                vim.notify("Notes module not available", vim.log.levels.WARN)
                return
            end
            
            -- Get all available notes
            local available_notes = notes_module.state.get_all_notes_titles()
            
            if #available_notes == 0 then
                vim.notify("No notes available. Create some notes first.", vim.log.levels.WARN)
                return
            end
            
            -- Create a selection list for notes
            local note_options = {}
            for _, note_data in ipairs(available_notes) do
                table.insert(note_options, {
                    text = note_data.title .. " (" .. (note_data.mode or "unknown") .. ")",
                    data = note_data
                })
            end
            
            -- Add option to create a new link using [[]] syntax
            table.insert(note_options, {
                text = "--- Add a new [[note-title]] link ---",
                data = { custom = true }
            })
            
            -- Show the selection menu
            vim.ui.select(note_options, {
                prompt = "Select a note to link:",
                format_item = function(item)
                    return item.text
                end
            }, function(choice)
                if not choice then
                    return -- User cancelled
                end
                
                if choice.data.custom then
                    -- Ask for link text
                    vim.ui.input({ prompt = "Enter note title for [[title]] link:" }, function(title)
                        -- Clear the command line after input
                        vim.cmd("echo ''")
                        if title and title ~= "" then
                            -- Append to the todo text
                            local todo = state.todos[todo_index]
                            local new_text = todo.text
                            
                            -- Check if the text already has a link
                            if not new_text:match("%[%[.+%]%]") then
                                new_text = new_text .. " [[" .. title .. "]]"
                                state.todos[todo_index].text = new_text
                                state.save_to_disk()
                                maybe_render(on_render)
                                
                                vim.notify("Added link to note: " .. title, vim.log.levels.INFO)
                            else
                                vim.notify("Todo already has a link. Edit the todo text directly.", vim.log.levels.WARN)
                            end
                        end
                    end)
                else
                    -- Link directly to an existing note
                    local note_data = choice.data
                    local todo_module = core.get_module("todos")
                    
                    if todo_module and todo_module.state and todo_module.state.link_todo_to_note then
                        todo_module.state.link_todo_to_note(todo_index, note_data.id, note_data.title)
                        maybe_render(on_render)
                        vim.notify("Linked to note: " .. note_data.title, vim.log.levels.INFO)
                    else
                        -- Fallback to updating the text with the [[]] syntax
                        local todo = state.todos[todo_index]
                        local new_text = todo.text
                        
                        -- Check if the text already has a link
                        if not new_text:match("%[%[.+%]%]") then
                            new_text = new_text .. " [[" .. note_data.title .. "]]"
                            state.todos[todo_index].text = new_text
                            state.save_to_disk()
                            maybe_render(on_render)
                            
                            vim.notify("Added link to note: " .. note_data.title, vim.log.levels.INFO)
                        else
                            vim.notify("Todo already has a link. Edit the todo text directly.", vim.log.levels.WARN)
                        end
                    end
                end
            end)
    end
end

function M.remove_duplicates(on_render)
	ensure_state_loaded()  -- Ensure state is loaded
	local dups = 0
	if state.remove_duplicates then
		dups = state.remove_duplicates()
	end
	vim.notify("Removed " .. dups .. " duplicates.", vim.log.levels.INFO)
	maybe_render(on_render)
end

function M.edit_todo(win_id, on_render)
	ensure_state_loaded()
	if not win_id or not vim.api.nvim_win_is_valid(win_id) then
		return
	end

	local cursor = vim.api.nvim_win_get_cursor(win_id)
	local line_num = cursor[1]

	local buf_id = vim.api.nvim_win_get_buf(win_id)

	local bullet_line = find_bullet_line_for_cursor(buf_id, line_num)
	if not bullet_line then
		return
	end

	local todo_index = get_real_todo_index(bullet_line, state.active_filter)
	if todo_index then
		multiline_input.create({
			prompt = "Edit to-do",
			default = state.todos[todo_index].text,
			on_submit = function(input)
				vim.cmd("echo ''")
				if input and input ~= "" then
					state.todos[todo_index].text = input
					state.save_to_disk()
					maybe_render(on_render)
				end
			end,
			on_cancel = function()
				vim.cmd("echo ''")
			end
		})
	end
end

function M.edit_priorities(win_id, on_render)
	ensure_state_loaded()
	if not win_id or not vim.api.nvim_win_is_valid(win_id) then
		return
	end

	local cursor = vim.api.nvim_win_get_cursor(win_id)
	local line_num = cursor[1]

	local buf_id = vim.api.nvim_win_get_buf(win_id)

	local bullet_line = find_bullet_line_for_cursor(buf_id, line_num)
	if not bullet_line then
		return
	end

	local todo_index = get_real_todo_index(bullet_line, state.active_filter)
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

function M.add_time_estimation(win_id, on_render)
	ensure_state_loaded()
	if not win_id or not vim.api.nvim_win_is_valid(win_id) then
		return
	end

	local line_num = vim.api.nvim_win_get_cursor(win_id)[1]
	local buf_id = vim.api.nvim_win_get_buf(win_id)

	local bullet_line = find_bullet_line_for_cursor(buf_id, line_num)
	if not bullet_line then
		return
	end

	local todo_index = get_real_todo_index(bullet_line, state.active_filter)

	if not todo_index then
		return
	end

	vim.ui.input({
		prompt = "Estimated completion time (e.g., 15m, 2h, 1d, 0.5w): ",
		default = "",
	}, function(input)
		-- Clear the command line after input
		vim.cmd("echo ''")
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
	ensure_state_loaded()
	if not win_id or not vim.api.nvim_win_is_valid(win_id) then
		return
	end

	local line_num = vim.api.nvim_win_get_cursor(win_id)[1]
	local buf_id = vim.api.nvim_win_get_buf(win_id)

	local bullet_line = find_bullet_line_for_cursor(buf_id, line_num)
	if not bullet_line then
		return
	end

	local todo_index = get_real_todo_index(bullet_line, state.active_filter)

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
	ensure_state_loaded()
	if not win_id or not vim.api.nvim_win_is_valid(win_id) then
		return
	end

	local line_num = vim.api.nvim_win_get_cursor(win_id)[1]
	local buf_id = vim.api.nvim_win_get_buf(win_id)

	local bullet_line = find_bullet_line_for_cursor(buf_id, line_num)
	if not bullet_line then
		return
	end

	local todo_index = get_real_todo_index(bullet_line, state.active_filter)

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
	ensure_state_loaded()
	if not win_id or not vim.api.nvim_win_is_valid(win_id) then
		return
	end

	local line_num = vim.api.nvim_win_get_cursor(win_id)[1]
	local buf_id = vim.api.nvim_win_get_buf(win_id)

	local bullet_line = find_bullet_line_for_cursor(buf_id, line_num)
	if not bullet_line then
		return
	end

	local todo_index = get_real_todo_index(bullet_line, state.active_filter)

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
	ensure_state_loaded()
	if not win_id or not vim.api.nvim_win_is_valid(win_id) then
		return
	end

	local cursor = vim.api.nvim_win_get_cursor(win_id)
	local line_num = cursor[1]

	local buf_id = vim.api.nvim_win_get_buf(win_id)

	local bullet_line = find_bullet_line_for_cursor(buf_id, line_num)
	if not bullet_line then
		return
	end

	-- Now use bullet_line instead of line_num for the rest
	line_num = bullet_line

	-- Calculate offset based on filters (consistent with move_todo)
	local line_offset = 1 -- default offset for blank line at top
	if state.active_filter then
		line_offset = line_offset + 2 -- add 2 for filter header
	end
	if state.active_category then
		line_offset = line_offset + 2 -- add 2 for category header
	end

	-- Get the current todo index
	local todo_index = line_num - line_offset
	if todo_index < 1 or todo_index > #state.todos then
		return
	end

	vim.api.nvim_buf_set_option(buf_id, "modifiable", true)

	-- Determine the actual index in todos array if using filter
	local real_index
	if state.active_filter or state.active_category then
		local visible_count = 0
		for i, todo in ipairs(state.todos) do
			local show_by_tag = not state.active_filter or todo.text:match("#" .. state.active_filter)
			local show_by_category = true
			
			if state.active_category then
				local module = get_todo_module()
				if module and module.state and module.state.get_todo_category then
					local todo_category_id = module.state.get_todo_category(todo.id)
					show_by_category = (todo_category_id == state.active_category) or
									  (state.active_category == "uncategorized" and 
									   (todo_category_id == "uncategorized" or not todo_category_id))
				else
					show_by_category = (todo.category == state.active_category) or
									  (state.active_category == "Uncategorized" and 
									   (not todo.category or todo.category == ""))
				end
			end
			
			if show_by_tag and show_by_category then
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
		safe_del_keymap("j")
		safe_del_keymap("k")
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

		-- Calculate offset based on filters
		local line_offset = 1 -- default offset for blank line at top
		if state.active_filter then
			line_offset = line_offset + 2 -- add 2 for filter header
		end
		if state.active_category then
			line_offset = line_offset + 2 -- add 2 for category header
		end

		local current_index = line_num - line_offset

		if direction == "up" and current_index <= 1 then
			return
		end

		-- Get the real index in state.todos
		local real_index
		if state.active_filter or state.active_category then
			local visible_count = 0
			for i, todo in ipairs(state.todos) do
				local show_by_tag = not state.active_filter or todo.text:match("#" .. state.active_filter)
				local show_by_category = true
				
				if state.active_category then
					local module = get_todo_module()
					if module and module.state and module.state.get_todo_category then
						local todo_category_id = module.state.get_todo_category(todo.id)
						show_by_category = (todo_category_id == state.active_category) or
										  (state.active_category == "uncategorized" and 
										   (todo_category_id == "uncategorized" or not todo_category_id))
					else
						show_by_category = (todo.category == state.active_category) or
										  (state.active_category == "Uncategorized" and 
										   (not todo.category or todo.category == ""))
					end
				end
				
				if show_by_tag and show_by_category then
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
				local show_by_tag = not state.active_filter or state.todos[i].text:match("#" .. state.active_filter)
				local show_by_category = true
				
				if state.active_category then
					local module = get_todo_module()
					if module and module.state and module.state.get_todo_category then
						local todo_category_id = module.state.get_todo_category(state.todos[i].id)
						show_by_category = (todo_category_id == state.active_category) or
										  (state.active_category == "uncategorized" and 
										   (todo_category_id == "uncategorized" or not todo_category_id))
					else
						show_by_category = (state.todos[i].category == state.active_category) or
										  (state.active_category == "Uncategorized" and 
										   (not state.todos[i].category or state.todos[i].category == ""))
					end
				end
				
				if show_by_tag and show_by_category then
					target_index = i
					break
				end
			end

			if not target_index then
				return -- No visible todo to swap with
			end
		else -- up
			for i = real_index - 1, 1, -1 do
				local show_by_tag = not state.active_filter or state.todos[i].text:match("#" .. state.active_filter)
				local show_by_category = true
				
				if state.active_category then
					local module = get_todo_module()
					if module and module.state and module.state.get_todo_category then
						local todo_category_id = module.state.get_todo_category(state.todos[i].id)
						show_by_category = (todo_category_id == state.active_category) or
										  (state.active_category == "uncategorized" and 
										   (todo_category_id == "uncategorized" or not todo_category_id))
					else
						show_by_category = (state.todos[i].category == state.active_category) or
										  (state.active_category == "Uncategorized" and 
										   (not state.todos[i].category or state.todos[i].category == ""))
					end
				end
				
				if show_by_tag and show_by_category then
					target_index = i
					break
				end
			end

			if not target_index then
				return -- No visible todo to swap with
			end
		end

		-- Swap order indices for reordering
		local current_order = state.todos[real_index].order_index or real_index
		local target_order = state.todos[target_index].order_index or target_index

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

		if state.active_filter or state.active_category then
			-- Recalculate the cursor position when filtered
			local visible_count = 0
			for i, todo in ipairs(state.todos) do
				local show_by_tag = not state.active_filter or todo.text:match("#" .. state.active_filter)
				local show_by_category = true
				
				if state.active_category then
					local module = get_todo_module()
					if module and module.state and module.state.get_todo_category then
						local todo_category_id = module.state.get_todo_category(todo.id)
						show_by_category = (todo_category_id == state.active_category) or
										  (state.active_category == "uncategorized" and 
										   (todo_category_id == "uncategorized" or not todo_category_id))
					else
						show_by_category = (todo.category == state.active_category) or
										  (state.active_category == "Uncategorized" and 
										   (not todo.category or todo.category == ""))
					end
				end
				
				if show_by_tag and show_by_category then
					visible_count = visible_count + 1
					if i == new_position then
						new_line_num = visible_count + line_offset
						break
					end
				end
			end
		else
			-- Unfiltered view is simpler
			new_line_num = new_position + line_offset
		end

		if new_line_num > 0 then
			vim.api.nvim_win_set_cursor(win_id, { new_line_num, 0 })
			vim.api.nvim_buf_clear_namespace(buf_id, ns_id, 0, -1)
			vim.api.nvim_buf_add_highlight(buf_id, ns_id, "IncSearch", new_line_num - 1, 0, -1)
		end
	end

	-- Arrow keys for movement
	vim.keymap.set("n", "<Down>", function()
		move_todo(buf_id, win_id, vim.api.nvim_win_get_cursor(win_id)[1], ns_id, "down", on_render)
	end, { buffer = buf_id, nowait = true })

	vim.keymap.set("n", "<Up>", function()
		move_todo(buf_id, win_id, vim.api.nvim_win_get_cursor(win_id)[1], ns_id, "up", on_render)
	end, { buffer = buf_id, nowait = true })

	-- Also support j/k vim keys for movement
	vim.keymap.set("n", "j", function()
		move_todo(buf_id, win_id, vim.api.nvim_win_get_cursor(win_id)[1], ns_id, "down", on_render)
	end, { buffer = buf_id, nowait = true })

	vim.keymap.set("n", "k", function()
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

-- Export helper functions for use in other modules
M.get_todo_at_cursor = function(win_id)
	ensure_state_loaded()
	if not win_id or not vim.api.nvim_win_is_valid(win_id) then
		return nil
	end

	local cursor = vim.api.nvim_win_get_cursor(win_id)
	local line_num = cursor[1]
	local buf_id = vim.api.nvim_win_get_buf(win_id)

	local bullet_line = find_bullet_line_for_cursor(buf_id, line_num)
	if not bullet_line then
		return nil
	end

	local todo_index = get_real_todo_index(bullet_line, state.active_filter)
	if todo_index and state.todos[todo_index] then
		return state.todos[todo_index], todo_index
	end

	return nil
end

return M
