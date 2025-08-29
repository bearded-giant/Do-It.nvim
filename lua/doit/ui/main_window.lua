local vim = vim

local config = require("doit.config")
local calendar = require("doit.calendar")
local highlights = require("doit.ui.highlights")
local todo_actions = require("doit.ui.todo_actions")
local help_window = require("doit.ui.help_window")
local tag_window = require("doit.ui.tag_window")
local category_window = require("doit.ui.category_window")
local search_window = require("doit.ui.search_window")
local scratchpad = require("doit.ui.scratchpad")

local core = require("doit.core")

if not core.ui then
    core.ui = require("doit.core.ui").setup()
end

-- Lazy loading of todo module and state
local todo_module = nil
local state = nil

-- Function to get or load the todo module
local function get_todo_module()
    if not todo_module then
        -- Try multiple ways to get the module
        todo_module = core.get_module("todos")
        
        if not todo_module then
            local ok, doit = pcall(require, "doit")
            if ok then
                todo_module = doit.todos or (doit.modules and doit.modules.todos)
            end
        end
    end
    return todo_module
end

-- Function to ensure state is loaded - always get fresh reference for list switching
local function ensure_state_loaded()
    local module = get_todo_module()
    if module and module.state then
        -- Always update reference to get current list state
        state = module.state
        return state
    else
        -- Fallback only if module not available
        if not state then
            -- Use compatibility shim as fallback
            local ok, compat_state = pcall(require, "doit.state")
            if ok then
                state = compat_state
            else
                -- Initialize empty state as last resort
                state = {
                    todos = {},
                    active_filter = nil,
                    active_category = nil,
                    deleted_todos = {},
                    reordering_todo_index = nil,
                    todo_lists = { active = "default" }
                }
                
                -- Add stub functions
                state.load_todos = state.load_todos or function() end
                state.save_todos = state.save_todos or function() end
                state.add_todo = state.add_todo or function(text) 
                    table.insert(state.todos, { text = text, done = false, created_at = os.time() })
                end
                state.sort_todos = state.sort_todos or function() end
                state.set_filter = state.set_filter or function(f) state.active_filter = f end
                state.clear_category_filter = state.clear_category_filter or function() state.active_category = nil end
                state.undo_delete = state.undo_delete or function() return false end
                state.get_priority_score = state.get_priority_score or function() return 0 end
            end
            
            -- Try to load todos if the function exists
            if state and state.load_todos then
                state.load_todos()
            end
        end
        return state
    end
end

-- Don't load immediately - will load on first use
local function ensure_module_loaded()
    ensure_state_loaded()
    get_todo_module()
end

local M = {}

local win_id = nil
local buf_id = nil

function M.get_window_id()
    return win_id
end

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

	local ns = vim.api.nvim_create_namespace("doit_small_keys")
	for i = 1, #lines do
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
	
	-- Ensure state is loaded
	state = ensure_state_loaded()
	
	-- Update window title with current list name
	if win_id and vim.api.nvim_win_is_valid(win_id) then
		local list_name = "default"
		if state and state.todo_lists and state.todo_lists.active then
			list_name = state.todo_lists.active
		end
		vim.api.nvim_win_set_config(win_id, {
			title = string.format(" to-dos [%s] ", list_name),
			title_pos = "center",
		})
	end
	
	vim.api.nvim_buf_set_option(buf_id, "modifiable", true)

	local ns_id = highlights.get_namespace_id()
	vim.api.nvim_buf_clear_namespace(buf_id, ns_id, 0, -1)

	state.sort_todos()

	local lines = { "" }
	if state.active_filter then
		table.insert(lines, "")
		table.insert(lines, "  Filtered by tag: #" .. state.active_filter)
	end
	
	if state.active_category then
		table.insert(lines, "")
		
		local category_name = state.active_category
		local module = get_todo_module()
		if module and module.state and module.state.categories_by_id 
			and module.state.categories_by_id[state.active_category] then
			category_name = module.state.categories_by_id[state.active_category].name
		end
		
		table.insert(lines, "  Filtered by category: " .. category_name)
	end

	for _, todo in ipairs(state.todos) do
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
			local todo_index = i - M.calculate_line_offset()
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
				
				-- Note link highlight for [[note-title]] syntax
				for link in line:gmatch("%[%[([^%]]+)%]%]") do
					local link_pattern = "%[%[" .. link .. "%]%]"
					local start_idx = line:find(link_pattern, 1, true) - 1
					if start_idx then
						local end_idx = start_idx + #link_pattern
						vim.api.nvim_buf_add_highlight(
							buf_id,
							ns_id,
							"DoItNoteLink",
							line_nr,
							start_idx,
							end_idx
						)
					end
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
		elseif line:match("Filtered by tag:") or line:match("Filtered by category:") then
			vim.api.nvim_buf_add_highlight(buf_id, ns_id, "WarningMsg", line_nr, 0, -1)
		end
	end

	vim.api.nvim_buf_set_option(buf_id, "modifiable", false)
end

function M.format_todo_line(todo)
	-- Create default formatting if missing
	if not config.options.formatting then
		config.options.formatting = {
			pending = {
				icon = "○",
				format = { "notes_icon", "icon", "text", "due_date", "ect", "relative_time" }
			},
			in_progress = {
				icon = "◐",
				format = { "notes_icon", "icon", "text", "due_date", "ect", "relative_time" }
			},
			done = {
				icon = "✓",
				format = { "notes_icon", "icon", "text", "due_date", "ect", "relative_time" }
			}
		}
	end

	local formatting = config.options.formatting
	
	-- Still missing format keys? Create at least pending and done
	if not formatting.pending then
		formatting.pending = {
			icon = "○",
			format = { "icon", "text", "relative_time" }
		}
	end
	if not formatting.done then
		formatting.done = {
			icon = "✓",
			format = { "icon", "text", "relative_time" }
		}
	end
	if not formatting.in_progress then
		formatting.in_progress = {
			icon = "◐",
			format = { "icon", "text", "relative_time" }
		}
	end

	local format = todo.done and formatting.done.format or 
	               (todo.in_progress and formatting.in_progress.format or formatting.pending.format)
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
	if todo.note_id then
		notes_icon = config.options.notes and config.options.notes.linked_icon or "🔗"
	elseif todo.notes and todo.notes ~= "" then
		notes_icon = config.options.notes and config.options.notes.icon or "✎"
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

			local icon = config.options.calendar and config.options.calendar.icon or ""
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

-- Calculate the offset for todo indices based on filter headers in the rendered list
function M.calculate_line_offset()
	local offset = 1 -- Always have at least one blank line at the top
	if state.active_filter then
		offset = offset + 2 -- Add 2 more lines for tag filter header
	end
	if state.active_category then
		offset = offset + 2 -- Add 2 more lines for category filter header
	end
	return offset
end

local function create_window()
	-- Ensure state is loaded before creating window
	state = ensure_state_loaded()
	
	-- Get the active list name for the window title
	local list_name = "default"
	if state and state.todo_lists and state.todo_lists.active then
		list_name = state.todo_lists.active
	end
	
	local ui = vim.api.nvim_list_uis()[1]
	if not ui then
		-- In headless mode or when no UI is available, use defaults
		ui = { width = 80, height = 24 }
	end
	
	-- Set default window options if they're missing
	if not config.options then
		config.options = {}
	end
	if not config.options.window then
		config.options.window = {
			width = 55,
			height = 20,
			border = "rounded",
			position = "center"
		}
	end
	-- Ensure formatting exists
	if not config.options.formatting then
		config.options.formatting = {
			pending = {
				icon = "○",
				format = { "notes_icon", "icon", "text", "due_date", "ect", "relative_time" }
			},
			in_progress = {
				icon = "◐",
				format = { "notes_icon", "icon", "text", "due_date", "ect", "relative_time" }
			},
			done = {
				icon = "✓",
				format = { "notes_icon", "icon", "text", "due_date", "ect", "relative_time" }
			}
		}
	end
	
	-- Check for relative sizing first (from modules.todos.ui.window config)
	local window_config = nil
	
	-- First try to get from the modular config structure
	if config.options.modules and config.options.modules.todos and config.options.modules.todos.ui and config.options.modules.todos.ui.window then
		window_config = config.options.modules.todos.ui.window
	elseif config.options.window then
		-- Fallback to legacy config structure
		window_config = config.options.window
	else
		-- Last resort defaults
		window_config = {
			width = 55,
			height = 20,
			use_relative = false
		}
	end
	
	local width, height
	if window_config.use_relative then
		-- Use relative sizing based on screen percentage
		width = math.floor(ui.width * (window_config.relative_width or 0.5))
		height = math.floor(ui.height * (window_config.relative_height or 0.5))
	else
		-- Use absolute sizing
		width = window_config.width or 55
		height = window_config.height or 20
	end
	
	local position = window_config.position or "center"
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
		title = string.format(" to-dos [%s] ", list_name),
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
		-- Default keymaps
		local default_keymaps = {
			new_todo = "i",
			toggle_todo = "x",
			delete_todo = "d",
			delete_completed = "D",
			close_window = "q",
			undo_delete = "u",
			toggle_help = "?",
			toggle_tags = "t",
			toggle_categories = "C",
			clear_filter = "c",
			edit_todo = "e",
			edit_priorities = "p",
			add_due_date = "H",
			remove_due_date = "r",
			add_time_estimation = "T",
			remove_time_estimation = "R",
			reorder_todo = "r",
			open_linked_note = "o",
			open_todo_scratchpad = "<leader>p",
			toggle_list_manager = "L",
			import_todos = "I",
			export_todos = "E",
			search_todos = "/",
			move_todo_up = "k",
			move_todo_down = "j",
		}
		
		-- Try to get key from config, fall back to default
		local key = nil
		
		-- First try: config.options.keymaps
		if config.options and config.options.keymaps then
			key = config.options.keymaps[key_option]
		end
		
		-- Second try: Look for module config
		if not key then
			local module = get_todo_module()
			if module and module.config and module.config.keymaps then
				key = module.config.keymaps[key_option]
			end
		end
		
		-- Third try: Use default
		if not key then
			key = default_keymaps[key_option]
		end
		
		-- Set the keymap if we found a key
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
	
	setup_keymap("toggle_categories", function()
		local module = get_todo_module()
		if module and module.ui and module.ui.category_window then
			module.ui.category_window.toggle_window()
		else
			category_window.create_category_window(win_id)
		end
		M.render_todos()
	end)

	setup_keymap("clear_filter", function()
		state.set_filter(nil)
		state.clear_category_filter()
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
	
	-- Add keymap for opening linked notes
	setup_keymap("open_linked_note", function()
		M.open_linked_note()
	end)
	
	-- Add keymap for linking to notes
	-- Since this might not be in config.options.keymaps yet, add it manually
	vim.keymap.set("n", "n", function()
		todo_actions.link_to_note(win_id, function()
			M.render_todos()
		end)
	end, { buffer = buf_id, nowait = true, desc = "Link todo to note" })

	setup_keymap("open_todo_scratchpad", function()
		scratchpad.open_todo_scratchpad(win_id)
	end)
	
	setup_keymap("toggle_list_manager", function()
		local module = get_todo_module()
		if module and module.ui and module.ui.list_manager_window then
			module.ui.list_manager_window.toggle_window()
		else
			vim.notify("List manager window not available", vim.log.levels.WARN)
		end
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
	
	-- Always allow Esc to close the window, in addition to the configured close key
	vim.keymap.set("n", "<Esc>", function()
		M.close_window()
	end, { buffer = buf_id, nowait = true, desc = "Close todo window" })
end

-- Open linked note for a todo
function M.open_linked_note()
	if not win_id or not vim.api.nvim_win_is_valid(win_id) then
		return
	end

	local cursor_pos = vim.api.nvim_win_get_cursor(win_id)
	local line_nr = cursor_pos[1]
	local todo_index = line_nr - M.calculate_line_offset()
	local todo = state.todos[todo_index]

	if not todo then
		vim.notify("No todo selected", vim.log.levels.WARN)
		return
	end

	-- First check if there's a direct note_id link
	if todo.note_id then
		-- Try to get a reference to the notes module
		local notes_module = core.get_module("notes")
		if notes_module then
			-- Make sure the UI is initialized
			if not notes_module.ui then
				vim.notify("Notes UI not initialized", vim.log.levels.WARN)
				return
			end
			
			-- Make sure notes_window is available
			if not notes_module.ui.notes_window then
				vim.notify("Notes window not available", vim.log.levels.WARN)
				return
			end

			-- Close todos window
			M.close_window()
			-- Open notes window
			notes_module.ui.notes_window.toggle_notes_window()
			-- TODO: Ideally we would jump to the specific note, but that's handled by the notes module
			return
		end
	end

	-- If there's no direct link, check for [[]] links in the text
	if not todo.text:match("%[%[.+%]%]") then
		vim.notify("No linked note found", vim.log.levels.WARN)
		return
	end

	-- Try to get a reference to the notes module
	local notes_module = core.get_module("notes")
	if not notes_module or not notes_module.state then
		vim.notify("Notes module not available", vim.log.levels.WARN)
		return
	end

	-- Extract the first link
	local links = notes_module.state.parse_note_links(todo.text)
	if #links == 0 then
		vim.notify("No note links found", vim.log.levels.WARN)
		return
	end

	-- Try to find the note by title pattern
	local note = notes_module.state.find_note_by_title(links[1])
	if not note then
		vim.notify("Linked note not found: " .. links[1], vim.log.levels.WARN)
		return
	end

	-- Open the notes window
	M.close_window()
	
	-- Make sure the notes UI is initialized
	if not notes_module.ui or not notes_module.ui.notes_window then
		vim.notify("Notes window not available", vim.log.levels.WARN)
		return
	end
	
	notes_module.ui.notes_window.toggle_notes_window()
	-- The notes window will open with the current note mode
	-- TODO: Ideally we would jump to the specific note
end

function M.toggle_todo_window()
	-- Ensure state is loaded before toggle
	state = ensure_state_loaded()
	
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