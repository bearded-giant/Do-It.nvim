-- Obsidian-sync module for DoIt.nvim
-- Provides integration between DoIt todos and Obsidian.nvim notes
local M = {}

-- Module version
M.version = "1.0.0"

-- Module metadata for registry
M.metadata = {
	name = "obsidian-sync",
	version = M.version,
	description = "Direct integration with obsidian.nvim vault",
	author = "bearded-giant",
	path = "doit.modules.obsidian-sync",
	dependencies = { "todos" },
	config_schema = {
		enabled = { type = "boolean", default = true },
		vault_path = { type = "string", default = "~/Recharge-Notes" },
		section_marker = { type = "string", default = "## TODO" },
		daily_note = { type = "table" },
		auto_import_on_open = { type = "boolean", default = false },
		sync_completions = { type = "boolean", default = true },
		default_list = { type = "string", default = "obsidian" },
		path_to_list = { type = "table" },
		list_mapping = { type = "table" },
		keymaps = { type = "table" },
	},
}

-- Session state (not persisted between sessions)
M.refs = {} -- todo_id -> {bufnr, lnum, file, date}
M.imported_lines = {} -- file:line -> todo_id (prevent duplicates)

-- Setup function
function M.setup(opts)
	-- Initialize module with core framework
	local core = require("doit.core")

	-- Setup module configuration
	M.config = vim.tbl_deep_extend("force", {
		vault_path = "~/Recharge-Notes",
		section_marker = "## TODO",
		daily_note = {
			path_template = "daily/%Y-%m-%d.md",
			lookback_days = 7,
		},
		auto_import_on_open = false,
		sync_completions = true,
		default_list = "obsidian",
		path_to_list = {
			{ pattern = "/daily/", list = "daily" },
			{ pattern = "/inbox/", list = "inbox" },
			{ pattern = "/projects/", list = "projects" },
		},
		list_mapping = {
			daily = "daily",
			inbox = "inbox",
			projects = "projects",
		},
		keymaps = {
			import_buffer = "<leader>ti",
			send_current = "<leader>tt",
		},
	}, opts or {})

	-- Check if obsidian.nvim is available
	local has_obsidian, obsidian = pcall(require, "obsidian")
	if not has_obsidian then
		return M
	end

	-- Store reference to obsidian client
	M.obsidian_client = obsidian.get_client and obsidian.get_client() or nil

	-- Initialize core functions
	M.setup_functions()

	-- Create user commands
	M.create_commands()

	-- Setup autocmds if configured
	if M.config.auto_import_on_open or M.config.sync_completions then
		M.setup_autocmds()
	end

	-- Setup integration hooks
	if M.config.sync_completions then
		M.setup_hooks()
	end

	-- Register module with core
	core.register_module("obsidian-sync", M)

	return M
end

-- Core functions setup
function M.setup_functions()
	-- resolve a daily note path for a specific time value (no lookback)
	function M.resolve_daily_note_path(time)
		local daily_note = M.config.daily_note or {}
		if daily_note.resolve and type(daily_note.resolve) == "function" then
			return daily_note.resolve(vim.fn.expand(M.config.vault_path), time)
		end
		local template = daily_note.path_template or "daily/%Y-%m-%d.md"
		local expanded = os.date(template, time)
		return vim.fn.expand(M.config.vault_path) .. "/" .. expanded
	end

	-- resolve daily note path with lookback: tries today, then walks backwards
	-- up to lookback_days. returns today's path if nothing found (for creation).
	function M.resolve_daily_path(time)
		local today_path = M.resolve_daily_note_path(time)
		if vim.fn.filereadable(today_path) == 1 then
			return today_path
		end

		local daily_note = M.config.daily_note or {}
		local lookback = daily_note.lookback_days or 7
		if lookback == 0 then
			return today_path
		end

		local base_time = time or os.time()
		for i = 1, lookback do
			local past_time = base_time - (i * 86400)
			local past_path = M.resolve_daily_note_path(past_time)
			if vim.fn.filereadable(past_path) == 1 then
				return past_path
			end
		end

		-- nothing found, return today's path so caller gets a useful error
		return today_path
	end

	-- Helper: Find a todo by ID across all lists
	function M.find_todo_by_id(todo_id, target_list)
		local core = require("doit.core")
		local todos_module = core.get_module("todos")
		if not todos_module or not todos_module.state then
			return nil
		end

		local state = todos_module.state
		local current_list = state.todo_lists.active

		vim.notify(
			string.format(
				"[ObsidianSync] Searching for todo %s in list %s (current: %s)",
				todo_id,
				target_list or "current",
				current_list
			),
			vim.log.levels.DEBUG
		)

		-- First try current list to avoid switching
		for _, t in ipairs(state.todos or {}) do
			if t.id == todo_id then
				return t
			end
		end

		-- If not found and we have a target list different from current
		if target_list and target_list ~= current_list then
			-- Save current state
			local original_list = current_list

			-- Load target list
			local success = state.load_list(target_list)
			if not success then
				return nil
			end

			-- Search for the todo
			local found_todo = nil
			for _, t in ipairs(state.todos or {}) do
				if t.id == todo_id then
					found_todo = vim.deepcopy(t)
					break
				end
			end

			-- Restore original list
			state.load_list(original_list)

			return found_todo
		end

		-- If still not found, try searching all available lists
		local lists = state.get_available_lists()
		for _, list_info in ipairs(lists) do
			if list_info.name ~= current_list and list_info.name ~= target_list then
				state.load_list(list_info.name)
				for _, t in ipairs(state.todos or {}) do
					if t.id == todo_id then
						local found_todo = vim.deepcopy(t)
						state.load_list(current_list)

						-- Update the ref with the correct list
						if M.refs[todo_id] then
							M.refs[todo_id].list = list_info.name
						end

						return found_todo
					end
				end
			end
		end

		-- Restore original list if we didn't find anything
		state.load_list(current_list)

		return nil
	end

	-- Helper: Determine which list a todo should go into
	function M.determine_list(file, text)
		-- check configurable path patterns
		for _, mapping in ipairs(M.config.path_to_list or {}) do
			if file:find(mapping.pattern, 1, true) then
				return mapping.list
			end
		end

		-- check for tags in text
		local tag = text:match("#(%w+)")
		if tag and M.config.list_mapping[tag] then
			return M.config.list_mapping[tag]
		end

		return M.config.default_list
	end

	-- Import todos from current buffer
	function M.import_current_buffer()
		local bufnr = vim.api.nvim_get_current_buf()
		local file = vim.api.nvim_buf_get_name(bufnr)

		-- Validate it's in Obsidian vault
		local vault_path = vim.fn.expand(M.config.vault_path)
		if not file:match(vim.pesc(vault_path)) then
			return 0, "Not in Obsidian vault"
		end

		local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
		local imported = 0
		local updated_lines = {}

		-- Get todos module
		local core = require("doit.core")
		local todos_module = core.get_module("todos")
		if not todos_module or not todos_module.state then
			vim.notify("Todos module not available", vim.log.levels.ERROR)
			return 0, "Todos module not available"
		end

		for lnum, line in ipairs(lines) do
			local checkbox, text = line:match("^%s*%- %[(%s?)%]%s+(.+)")

			if checkbox and text then
				-- Check if already imported (has doit marker)
				local existing_id = text:match("<!%-%- doit:(%S+) %-%->")

				if not existing_id and checkbox == " " then
					-- Clean up the text
					local clean_text = text:gsub(" <!%-%- doit:%S+ %-%->", "")

					-- Handle format: "- [ ] - actual text" by removing leading "- "
					clean_text = clean_text:gsub("^%-%s*", "")

					-- Skip empty todos (just placeholders)
					if clean_text == "" or clean_text == "-" then
						-- Don't import empty placeholders
						goto continue
					end

					local list = M.determine_list(file, clean_text)

					-- Ensure the list exists
					local lists = todos_module.state.get_available_lists()
					local list_exists = false
					for _, l in ipairs(lists) do
						if l.name == list then
							list_exists = true
							break
						end
					end

					-- Create list if it doesn't exist
					if not list_exists then
						todos_module.state.create_list(list, {})
					end

					-- Switch to the target list if different from current
					local current_list = todos_module.state.todo_lists.active
					if current_list ~= list then
						todos_module.state.load_list(list)
					end

					-- Create todo in the target list (don't pass list as second param)
					local new_todo = todos_module.state.add_todo(clean_text)

					-- persist obsidian ref on the todo for visual indicator
					new_todo.obsidian_ref = {
						file = file,
						date = file:match("(%d%d%d%d%-%d%d%-%d%d)") or os.date("%Y-%m-%d"),
						lnum = lnum,
					}

					-- Track reference
					M.refs[new_todo.id] = {
						bufnr = bufnr,
						lnum = lnum,
						file = file,
						date = file:match("(%d%d%d%d%-%d%d%-%d%d)"),
						list = list,
					}

					-- Mark line as imported
					M.imported_lines[file .. ":" .. lnum] = new_todo.id

					-- Add marker to line
					line = line .. " <!-- doit:" .. new_todo.id .. " -->"
					imported = imported + 1
				elseif existing_id then
					-- Already imported - refresh reference
					-- Try to find which list this todo is in
					local todo_list = M.refs[existing_id] and M.refs[existing_id].list
					if not todo_list then
						todo_list = M.determine_list(file, text)
					end

					M.refs[existing_id] = {
						bufnr = bufnr,
						lnum = lnum,
						file = file,
						date = file:match("(%d%d%d%d%-%d%d%-%d%d)"),
						list = todo_list,
					}
					M.imported_lines[file .. ":" .. lnum] = existing_id
				end
			end

			::continue::
			table.insert(updated_lines, line)
		end

		-- Update buffer with markers
		if imported > 0 then
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, updated_lines)
		end

		return imported
	end

	-- Sync completion status back to Obsidian
	function M.sync_completion(todo_id, todo_state)
		local ref = M.refs[todo_id]
		if not ref then
			return false
		end

		-- Map DoIt states to checkbox states
		-- DoIt has 3 states: not started, in_progress, done
		-- Obsidian has 2 states: [ ] and [x]
		-- We keep [ ] for both not started and in_progress, [x] only for completed
		local checkbox = (todo_state.done and not todo_state.in_progress) and "[x]" or "[ ]"

		vim.notify(
			string.format(
				"[ObsidianSync] Syncing todo %s: done=%s, in_progress=%s -> checkbox=%s",
				todo_id,
				tostring(todo_state.done),
				tostring(todo_state.in_progress),
				checkbox
			),
			vim.log.levels.DEBUG
		)

		vim.notify(
			string.format(
				"[ObsidianSync] Ref details - File: %s, Line: %d, Buffer: %s",
				ref.file,
				ref.lnum,
				tostring(ref.bufnr)
			),
			vim.log.levels.DEBUG
		)

		-- Try buffer first (more efficient if open)
		if ref.bufnr and vim.api.nvim_buf_is_valid(ref.bufnr) then
			local lines = vim.api.nvim_buf_get_lines(ref.bufnr, ref.lnum - 1, ref.lnum, false)
			if lines and #lines > 0 then
				local line = lines[1]

				-- Try multiple patterns to match different checkbox formats
				local patterns = {
					-- Standard format: "- [ ] text" or "- [x] text"
					{ pattern = "^(%s*%-%s*)%[[%sxX]%](%s*)", replacement = "%1" .. checkbox .. "%2" },
					-- Format with dash after: "- [ ] - text"
					{ pattern = "^(%s*%-%s*)%[[%sxX]%](%s*%-%s*)", replacement = "%1" .. checkbox .. "%2" },
					-- Indented format
					{ pattern = "^(%s+%-%s*)%[[%sxX]%](%s*)", replacement = "%1" .. checkbox .. "%2" },
				}

				local new_line = line
				local matched = false
				for _, p in ipairs(patterns) do
					local test_line = line:gsub(p.pattern, p.replacement)
					if test_line ~= line then
						new_line = test_line
						matched = true
						break
					end
				end

				if matched then
					vim.api.nvim_buf_set_lines(ref.bufnr, ref.lnum - 1, ref.lnum, false, { new_line })

					-- If the buffer has a file name, mark it as modified
					if vim.api.nvim_buf_get_name(ref.bufnr) ~= "" then
						vim.api.nvim_buf_set_option(ref.bufnr, "modified", true)
					end
					return true
				end
			end
		end

		-- Fallback to file
		if vim.fn.filereadable(ref.file) == 1 then
			local lines = vim.fn.readfile(ref.file)
			if lines and ref.lnum > 0 and ref.lnum <= #lines then
				vim.notify(
					string.format("[ObsidianSync] Reading file %s, line %d of %d", ref.file, ref.lnum, #lines),
					vim.log.levels.DEBUG
				)

				local old_line = lines[ref.lnum]

				-- Try multiple patterns
				local patterns = {
					{ pattern = "^(%s*%-%s*)%[[%sxX]%](%s*)", replacement = "%1" .. checkbox .. "%2" },
					{ pattern = "^(%s*%-%s*)%[[%sxX]%](%s*%-%s*)", replacement = "%1" .. checkbox .. "%2" },
					{ pattern = "^(%s+%-%s*)%[[%sxX]%](%s*)", replacement = "%1" .. checkbox .. "%2" },
				}

				local new_line = old_line
				local matched = false
				for _, p in ipairs(patterns) do
					local test_line = old_line:gsub(p.pattern, p.replacement)
					if test_line ~= old_line then
						new_line = test_line
						matched = true
						break
					end
				end

				if matched then
					lines[ref.lnum] = new_line
					vim.fn.writefile(lines, ref.file)

					-- Reload buffer if it's open to reflect changes
					if ref.bufnr and vim.api.nvim_buf_is_valid(ref.bufnr) then
						vim.api.nvim_buf_call(ref.bufnr, function()
							vim.cmd("checktime")
						end)
					end
					return true
				end
			else
				vim.notify(
					string.format("[ObsidianSync] Invalid line number %d for file with %d lines", ref.lnum, #lines),
					vim.log.levels.ERROR
				)
			end
		else
			vim.notify("[ObsidianSync] File not readable: " .. ref.file, vim.log.levels.ERROR)
		end

		return false
	end

	-- Refresh references for a buffer
	function M.refresh_buffer_refs(bufnr)
		local file = vim.api.nvim_buf_get_name(bufnr)
		local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

		-- Get todos module to sync states
		local core = require("doit.core")
		local todos_module = core.get_module("todos")
		local should_sync = M.config.sync_completions and todos_module and todos_module.state

		for lnum, line in ipairs(lines) do
			local _, text = line:match("^%s*%- %[(%s?)%]%s+(.+)")
			if text then
				local existing_id = text:match("<!%-%- doit:(%S+) %-%->")
				if existing_id then
					-- Determine which list this todo belongs to
					local todo_list = M.refs[existing_id] and M.refs[existing_id].list
					if not todo_list then
						local clean_text = text:gsub(" <!%-%- doit:%S+ %-%->", "")
						todo_list = M.determine_list(file, clean_text)
					end

					M.refs[existing_id] = {
						bufnr = bufnr,
						lnum = lnum,
						file = file,
						date = file:match("(%d%d%d%d%-%d%d%-%d%d)"),
						list = todo_list,
					}

					-- Sync current DoIt state back to Obsidian checkbox
					if should_sync then
						-- Find the todo in DoIt by ID, searching in the correct list
						local todo = M.find_todo_by_id(existing_id, todo_list)

						-- If we found the todo, sync its state
						if todo then
							M.sync_completion(existing_id, todo)
						end
					end
				end
			end
		end
	end

	-- export a single todo to today's daily note
	function M.export_to_daily(todo)
		if not todo or not todo.text or not todo.id then
			vim.notify("No valid todo to export", vim.log.levels.WARN)
			return false
		end

		-- check if already exported (persisted ref or session ref)
		if todo.obsidian_ref then
			vim.notify("Todo already linked to daily note", vim.log.levels.WARN)
			return false
		end
		local today = os.date("%Y-%m-%d")
		local daily_path = M.resolve_daily_path()

		if M.refs[todo.id] then
			local ref = M.refs[todo.id]
			if ref.file and ref.file == daily_path then
				vim.notify("Todo already linked to daily note", vim.log.levels.WARN)
				return false
			end
		end

		if vim.fn.filereadable(daily_path) ~= 1 then
			vim.notify("Today's daily note not found: " .. daily_path, vim.log.levels.ERROR)
			return false
		end

		local lines = vim.fn.readfile(daily_path)
		local insert_at = nil

		-- find the section heading and insert immediately after it
		for i, line in ipairs(lines) do
			if line:match("^" .. vim.pesc(M.config.section_marker)) then
				insert_at = i + 1
				break
			end
		end

		if not insert_at then
			vim.notify("No " .. M.config.section_marker .. " section found in daily note", vim.log.levels.ERROR)
			return false
		end

		local new_line = "- [ ] - " .. todo.text .. " <!-- doit:" .. todo.id .. " -->"
		table.insert(lines, insert_at, new_line)
		vim.fn.writefile(lines, daily_path)

		-- track the reference
		M.refs[todo.id] = {
			bufnr = nil,
			lnum = insert_at,
			file = daily_path,
			date = today,
			list = todo.list_name or (M.config.list_mapping.daily or "daily"),
		}
		M.imported_lines[daily_path .. ":" .. insert_at] = todo.id

		-- reload buffer if it's open
		for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
			if vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_get_name(bufnr) == daily_path then
				vim.api.nvim_buf_call(bufnr, function()
					vim.cmd("checktime")
				end)
				M.refs[todo.id].bufnr = bufnr
				break
			end
		end

		-- persist the reference on the todo so it survives across sessions
		todo.obsidian_ref = { file = daily_path, date = today, lnum = insert_at }
		local core = require("doit.core")
		local todos_module = core.get_module("todos")
		if todos_module and todos_module.state and todos_module.state.save_todos then
			todos_module.state.save_todos()
		end

		local short_text = #todo.text > 40 and todo.text:sub(1, 40) .. "..." or todo.text
		vim.notify("Exported to daily: " .. short_text, vim.log.levels.INFO)
		return true
	end

	-- update a single todo's done state directly in the json file on disk
	function M.update_todo_in_json(lists_dir, todo_id, is_done)
		local json_files = vim.fn.glob(lists_dir .. "/*.json", false, true)

		for _, json_path in ipairs(json_files) do
			local f = io.open(json_path, "r")
			if f then
				local content = f:read("*all")
				f:close()

				local ok, data = pcall(vim.fn.json_decode, content)
				if ok and data and data.todos then
					for _, todo in ipairs(data.todos) do
						if todo.id == todo_id then
							if todo.done ~= is_done then
								todo.done = is_done
								if is_done then
									todo.in_progress = false
								end
								data._metadata = data._metadata or {}
								data._metadata.updated_at = os.time()

								local wf = io.open(json_path, "w")
								if wf then
									wf:write(vim.fn.json_encode(data))
									wf:close()
									return true
								end
							end
							return false
						end
					end
				end
			end
		end

		return false
	end

	-- reload in-memory doit state from disk and refresh ui if open
	function M.refresh_doit_state()
		local core = require("doit.core")
		local todos_module = core.get_module("todos")
		if not todos_module or not todos_module.state then
			return
		end

		local active = todos_module.state.todo_lists.active
		if active then
			todos_module.state.load_list(active)
		end

		local ok, main_window = pcall(require, "doit.ui.main_window")
		if ok and main_window and main_window.render_todos then
			pcall(main_window.render_todos)
		end
	end

	-- reverse sync: read checkbox states from an obsidian buffer, update doit json
	function M.sync_completions_from_buffer(bufnr)
		bufnr = bufnr or vim.api.nvim_get_current_buf()
		local file = vim.api.nvim_buf_get_name(bufnr)

		local vault_path = vim.fn.expand(M.config.vault_path)
		if not file:match(vim.pesc(vault_path)) then
			return 0
		end

		local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
		local updated = 0

		local core = require("doit.core")
		local todos_config = core.get_module_config and core.get_module_config("todos")
		local lists_dir = (todos_config and todos_config.lists_dir)
			or vim.fn.stdpath("data") .. "/doit/lists"

		for _, line in ipairs(lines) do
			local checkbox_char, todo_id = line:match("^%s*%- %[([^%]]-)%].-<!%-%- doit:(%S+) %-%->")
			if todo_id then
				local is_done = (checkbox_char == "x" or checkbox_char == "X")
				if M.update_todo_in_json(lists_dir, todo_id, is_done) then
					updated = updated + 1
				end
			end
		end

		if updated > 0 then
			M.refresh_doit_state()
			vim.notify(
				string.format("[ObsidianSync] Synced %d completion%s from buffer", updated, updated > 1 and "s" or ""),
				vim.log.levels.INFO
			)
		end

		return updated
	end

	-- Get current todo index (helper for hooks)
	function M.get_current_todo_index(win_id)
		if not win_id or not vim.api.nvim_win_is_valid(win_id) then
			return nil
		end

		local cursor = vim.api.nvim_win_get_cursor(win_id)
		local line_num = cursor[1]

		local core = require("doit.core")
		local todos_module = core.get_module("todos")
		if not todos_module then
			return nil
		end

		local state = todos_module.state

		-- Calculate header offset
		local line_offset = 1 -- blank line at top
		if state.active_filter then
			line_offset = line_offset + 2 -- blank line + filter text
		end
		if state.active_category then
			line_offset = line_offset + 2 -- blank line + category text
		end

		-- Calculate which todo we're on
		local todo_line = line_num - line_offset
		if todo_line > 0 and todo_line <= #state.todos then
			return todo_line
		end

		return nil
	end
end

-- Create user commands
function M.create_commands()
	-- Import from current buffer
	vim.api.nvim_create_user_command("DoItImportBuffer", function()
		local count = M.import_current_buffer()
		vim.notify("Imported " .. count .. " todos", vim.log.levels.INFO)
	end, { desc = "Import todos from current Obsidian buffer" })

	-- Import today's daily note
	vim.api.nvim_create_user_command("DoItImportToday", function()
		local file = M.resolve_daily_path()

		if vim.fn.filereadable(file) == 1 then
			vim.cmd("edit " .. file)
			local count = M.import_current_buffer()
			vim.notify("Imported " .. count .. " todos from today's note", vim.log.levels.INFO)
		end
	end, { desc = "Import todos from today's daily note" })

	-- Export current todo to today's daily note
	vim.api.nvim_create_user_command("DoItExportToDaily", function()
		local core = require("doit.core")
		local todos_module = core.get_module("todos")
		if not todos_module or not todos_module.state then
			vim.notify("Todos module not available", vim.log.levels.ERROR)
			return
		end

		-- try to get the todo at cursor from main window
		local main_window = require("doit.ui.main_window")
		local todo_actions = require("doit.ui.todo_actions")
		if main_window.win_id and vim.api.nvim_win_is_valid(main_window.win_id) then
			local todo = todo_actions.get_todo_at_cursor(main_window.win_id)
			if todo then
				M.export_to_daily(todo)
				return
			end
		end

		vim.notify("No todo selected - open the DoIt window and select a todo", vim.log.levels.WARN)
	end, { desc = "Export current todo to today's Obsidian daily note" })

	-- Show sync status
	vim.api.nvim_create_user_command("DoItSyncStatus", function()
		local ref_count = vim.tbl_count(M.refs)
		local buffer_count = 0

		for _, ref in pairs(M.refs) do
			if vim.api.nvim_buf_is_valid(ref.bufnr) then
				buffer_count = buffer_count + 1
			end
		end

		vim.notify(
			string.format(
				"Tracking %d todos\n%d with open buffers\n%d total references",
				ref_count,
				buffer_count,
				vim.tbl_count(M.imported_lines)
			),
			vim.log.levels.INFO
		)
	end, { desc = "Show DoIt-Obsidian sync status" })

	-- Debug: Test sync for a specific todo
	vim.api.nvim_create_user_command("DoItTestSync", function(opts)
		local todo_id = opts.args
		if todo_id == "" then
			-- Try to get the first todo with a ref
			todo_id = next(M.refs)
			if not todo_id then
				return
			end
		end

		vim.notify("Testing sync for todo: " .. todo_id, vim.log.levels.DEBUG)

		local ref = M.refs[todo_id]
		if not ref then
			vim.notify("No reference found for todo: " .. todo_id, vim.log.levels.ERROR)
			return
		end

		vim.notify(
			string.format("Reference: File=%s, Line=%d, List=%s", ref.file, ref.lnum, ref.list or "unknown"),
			vim.log.levels.DEBUG
		)

		-- Find the todo
		local todo = M.find_todo_by_id(todo_id, ref.list)
		if not todo then
			vim.notify("Todo not found in DoIt", vim.log.levels.ERROR)
			return
		end

		vim.notify(
			string.format(
				"Todo state: done=%s, in_progress=%s, text=%s",
				tostring(todo.done),
				tostring(todo.in_progress),
				string.sub(todo.text, 1, 50)
			),
			vim.log.levels.DEBUG
		)

		-- Try to sync
		local success = M.sync_completion(todo_id, todo)
		if success then
			vim.notify("Sync completed successfully!", vim.log.levels.DEBUG)
		else
			vim.notify("Sync failed - check debug messages", vim.log.levels.ERROR)
		end
	end, { nargs = "?", desc = "Test sync for a specific todo ID" })

	-- Reverse sync: pull completions from obsidian buffer into doit json
	vim.api.nvim_create_user_command("DoItSyncFromObsidian", function()
		local count = M.sync_completions_from_buffer()
		if count == 0 then
			vim.notify("No completion changes to sync", vim.log.levels.INFO)
		end
	end, { desc = "Sync checkbox completions from Obsidian buffer to DoIt" })

	-- Debug: List all references
	vim.api.nvim_create_user_command("DoItListRefs", function()
		if vim.tbl_count(M.refs) == 0 then
			vim.notify("No Obsidian references tracked", vim.log.levels.INFO)
			return
		end

		local output = {}
		for todo_id, ref in pairs(M.refs) do
			table.insert(
				output,
				string.format(
					"ID: %s -> File: %s, Line: %d, List: %s",
					todo_id,
					vim.fn.fnamemodify(ref.file, ":t"),
					ref.lnum,
					ref.list or "unknown"
				)
			)
		end

		vim.notify("Obsidian References:\n" .. table.concat(output, "\n"), vim.log.levels.INFO)
	end, { desc = "List all Obsidian-DoIt references" })
end

-- Setup autocmds
function M.setup_autocmds()
	local group = vim.api.nvim_create_augroup("DoItObsidianSync", { clear = true })

	local vault_expanded = vim.fn.expand(M.config.vault_path)
	local vault_pattern = vault_expanded .. "/**/*.md"
	local template = (M.config.daily_note or {}).path_template or "daily/%Y-%m-%d.md"
	local daily_glob = template:gsub("%%[A-Za-z]", "*")
	local daily_pattern = vault_expanded .. "/" .. daily_glob

	-- Auto-import on daily note open
	if M.config.auto_import_on_open then
		vim.api.nvim_create_autocmd({ "BufReadPost" }, {
			group = group,
			pattern = daily_pattern,
			callback = function(ev)
				vim.defer_fn(function()
					M.import_current_buffer()
				end, 100)
			end,
		})
	end

	-- Reverse sync: on save, pull checkbox states back into doit json
	vim.api.nvim_create_autocmd("BufWritePost", {
		group = group,
		pattern = vault_pattern,
		callback = function(ev)
			M.sync_completions_from_buffer(ev.buf)
		end,
	})

	-- Refresh references when entering Obsidian buffers
	vim.api.nvim_create_autocmd({ "BufEnter" }, {
		group = group,
		pattern = vault_pattern,
		callback = function(ev)
			M.refresh_buffer_refs(ev.buf)
		end,
	})

	-- Setup keymaps in Obsidian buffers
	vim.api.nvim_create_autocmd("BufEnter", {
		group = group,
		pattern = vault_pattern,
		callback = function()
			vim.keymap.set(
				"n",
				M.config.keymaps.import_buffer,
				":DoItImportBuffer<CR>",
				{ buffer = true, desc = "Import todos to DoIt" }
			)

			vim.keymap.set("n", M.config.keymaps.send_current, function()
				-- Send current line to DoIt
				local line = vim.api.nvim_get_current_line()
				local lnum = vim.fn.line(".")
				local _, text = line:match("^%s*%- %[(%s?)%]%s+(.+)")

				if text then
					local clean_text = text:gsub(" <!%-%- doit:%S+ %-%->", "")
					local file = vim.api.nvim_buf_get_name(0)

					local core = require("doit.core")
					local todos_module = core.get_module("todos")
					if todos_module and todos_module.state then
						-- Determine which list to use based on file path
						local target_list = M.determine_list(file, clean_text)

						local todo = todos_module.state.add_todo(clean_text, target_list)

						-- Add marker
						line = line .. " <!-- doit:" .. todo.id .. " -->"
						vim.api.nvim_buf_set_lines(0, lnum - 1, lnum, false, { line })

						-- Track reference
						M.refs[todo.id] = {
							bufnr = vim.api.nvim_get_current_buf(),
							lnum = lnum,
							file = file,
							date = os.date("%Y-%m-%d"),
							list = target_list,
						}
					end
				end
			end, { buffer = true, desc = "Send current todo to DoIt" })
		end,
	})
end

-- Setup integration hooks
function M.setup_hooks()
	-- Hook into DoIt's toggle action for completion sync
	vim.defer_fn(function()
		local todo_actions = require("doit.ui.todo_actions")
		if not todo_actions then
			return
		end

		local original_toggle = todo_actions.toggle_todo

		todo_actions.toggle_todo = function(win_id, on_render)
			-- Get todo info before toggle
			local todo_index = M.get_current_todo_index(win_id)

			local core = require("doit.core")
			local todos_module = core.get_module("todos")

			local todo_id = nil

			if todos_module and todos_module.state and todo_index then
				local todo_before = todos_module.state.todos[todo_index]
				if todo_before then
					todo_id = todo_before.id
					vim.notify(
						string.format(
							"[ObsidianSync] Before toggle - ID: %s, done: %s, in_progress: %s",
							todo_id,
							tostring(todo_before.done),
							tostring(todo_before.in_progress)
						),
						vim.log.levels.DEBUG
					)
				end
			end

			-- Execute original toggle
			original_toggle(win_id, on_render)

			-- Sync to Obsidian if we have a reference
			if todo_id and M.refs[todo_id] and M.config.sync_completions then
				local ref = M.refs[todo_id]

				-- Get the updated todo state directly after toggle
				-- No need for defer since the toggle is synchronous
				local updated_todo = nil

				-- First try to get from current state if still same list
				if todos_module and todos_module.state and todo_index then
					local current_todo = todos_module.state.todos[todo_index]
					if current_todo and current_todo.id == todo_id then
						updated_todo = current_todo
					end
				end

				-- If not found in current position, search for it
				if not updated_todo then
					updated_todo = M.find_todo_by_id(todo_id, ref.list)
				end

				if updated_todo then
					vim.notify(
						string.format(
							"[ObsidianSync] After toggle - ID: %s, done: %s, in_progress: %s",
							todo_id,
							tostring(updated_todo.done),
							tostring(updated_todo.in_progress)
						),
						vim.log.levels.DEBUG
					)

					M.sync_completion(todo_id, updated_todo)
				end
			end
		end
	end, 500) -- Delay to ensure DoIt is fully loaded

	-- Hook into todo:moved event to update refs when todos move between lists
	vim.defer_fn(function()
		local core = require("doit.core")
		if core and core.on then
			core.on("todo:moved", function(event_data)
				local todo = event_data.todo
				local to_list = event_data.to_list

				-- Update the ref if this todo has an obsidian linkback
				if M.refs[todo.id] then
					M.refs[todo.id].list = to_list
				end
			end)
		end
	end, 500)
end

return M

