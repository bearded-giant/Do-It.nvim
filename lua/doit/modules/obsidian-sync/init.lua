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
    dependencies = {"todos"},
    config_schema = {
        enabled = { type = "boolean", default = true },
        vault_path = { type = "string", default = "~/Recharge-Notes" },
        auto_import_on_open = { type = "boolean", default = false },
        sync_completions = { type = "boolean", default = true },
        default_list = { type = "string", default = "obsidian" },
        list_mapping = { type = "table" },
        keymaps = { type = "table" }
    }
}

-- Session state (not persisted between sessions)
M.refs = {}  -- todo_id -> {bufnr, lnum, file, date}
M.imported_lines = {}  -- file:line -> todo_id (prevent duplicates)

-- Setup function
function M.setup(opts)
    -- Initialize module with core framework
    local core = require("doit.core")

    -- Setup module configuration
    M.config = vim.tbl_deep_extend("force", {
        vault_path = "~/Recharge-Notes",
        auto_import_on_open = false,
        sync_completions = true,
        default_list = "obsidian",
        list_mapping = {
            daily = "daily",
            inbox = "inbox",
            projects = "projects"
        },
        keymaps = {
            import_buffer = "<leader>ti",
            send_current = "<leader>tt"
        }
    }, opts or {})

    -- Check if obsidian.nvim is available
    local has_obsidian, obsidian = pcall(require, "obsidian")
    if not has_obsidian then
        vim.notify("obsidian.nvim not found, obsidian-sync disabled", vim.log.levels.WARN)
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
    -- Helper: Find a todo by ID across all lists
    function M.find_todo_by_id(todo_id, target_list)
        local core = require("doit.core")
        local todos_module = core.get_module("todos")
        if not todos_module or not todos_module.state then
        --             vim.notify("[ObsidianSync] Todos module not available", vim.log.levels.DEBUG)
            return nil
        end

        local state = todos_module.state
        local current_list = state.todo_lists.active

        vim.notify(string.format("[ObsidianSync] Searching for todo %s in list %s (current: %s)",
            todo_id, target_list or "current", current_list), vim.log.levels.DEBUG)

        -- First try current list to avoid switching
        for _, t in ipairs(state.todos or {}) do
            if t.id == todo_id then
        --                 vim.notify("[ObsidianSync] Found todo in current list", vim.log.levels.DEBUG)
                return t
            end
        end

        -- If not found and we have a target list different from current
        if target_list and target_list ~= current_list then
        --             vim.notify(string.format("[ObsidianSync] Todo not in current list, checking %s", target_list), vim.log.levels.DEBUG)

            -- Save current state
            local original_todos = state.todos
            local original_list = current_list

            -- Load target list
            local success = state.load_list(target_list)
            if not success then
                vim.notify(string.format("[ObsidianSync] Failed to load list %s", target_list), vim.log.levels.WARN)
                return nil
            end

            -- Search for the todo
            local found_todo = nil
            for _, t in ipairs(state.todos or {}) do
                if t.id == todo_id then
                    -- Create a deep copy to preserve the state
                    found_todo = vim.deepcopy(t)
        --                     vim.notify(string.format("[ObsidianSync] Found todo in list %s", target_list), vim.log.levels.DEBUG)
                    break
                end
            end

            -- Restore original list
            state.load_list(original_list)

            return found_todo
        end

        -- If still not found, try searching all available lists
        --         vim.notify("[ObsidianSync] Todo not found in expected lists, searching all lists", vim.log.levels.DEBUG)
        local lists = state.get_available_lists()
        for _, list_info in ipairs(lists) do
            if list_info.name ~= current_list and list_info.name ~= target_list then
                state.load_list(list_info.name)
                for _, t in ipairs(state.todos or {}) do
                    if t.id == todo_id then
                        local found_todo = vim.deepcopy(t)
                        state.load_list(current_list)
                        vim.notify(string.format("[ObsidianSync] Found todo in unexpected list: %s", list_info.name), vim.log.levels.WARN)

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

        vim.notify(string.format("[ObsidianSync] Todo %s not found in any list", todo_id), vim.log.levels.WARN)
        return nil
    end

    -- Helper: Determine which list a todo should go into
    function M.determine_list(file, text)
        -- Check file path patterns
        if file:match("/daily/") then
            return M.config.list_mapping.daily or "daily"
        elseif file:match("/inbox/") then
            return M.config.list_mapping.inbox or "inbox"
        elseif file:match("/projects/") then
            return M.config.list_mapping.projects or "projects"
        end

        -- Check for tags in text
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

                    -- Track reference
                    M.refs[new_todo.id] = {
                        bufnr = bufnr,
                        lnum = lnum,
                        file = file,
                        date = file:match("(%d%d%d%d%-%d%d%-%d%d)"),
                        list = list
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
                        list = todo_list
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
        --             vim.notify("[ObsidianSync] No ref found for todo " .. todo_id, vim.log.levels.DEBUG)
            return false
        end

        -- Map DoIt states to checkbox states
        -- DoIt has 3 states: not started, in_progress, done
        -- Obsidian has 2 states: [ ] and [x]
        -- We keep [ ] for both not started and in_progress, [x] only for completed
        local checkbox = (todo_state.done and not todo_state.in_progress) and "[x]" or "[ ]"

        vim.notify(string.format("[ObsidianSync] Syncing todo %s: done=%s, in_progress=%s -> checkbox=%s",
            todo_id, tostring(todo_state.done), tostring(todo_state.in_progress), checkbox), vim.log.levels.INFO)

        vim.notify(string.format("[ObsidianSync] Ref details - File: %s, Line: %d, Buffer: %s",
            ref.file, ref.lnum, tostring(ref.bufnr)), vim.log.levels.DEBUG)

        -- Try buffer first (more efficient if open)
        if ref.bufnr and vim.api.nvim_buf_is_valid(ref.bufnr) then
            local lines = vim.api.nvim_buf_get_lines(ref.bufnr, ref.lnum - 1, ref.lnum, false)
            if lines and #lines > 0 then
                local line = lines[1]
        --                 vim.notify("[ObsidianSync] Current buffer line: " .. line, vim.log.levels.DEBUG)

                -- Try multiple patterns to match different checkbox formats
                local patterns = {
                    -- Standard format: "- [ ] text" or "- [x] text"
                    { pattern = "^(%s*%-%s*)%[[%sxX]%](%s*)", replacement = "%1" .. checkbox .. "%2" },
                    -- Format with dash after: "- [ ] - text"
                    { pattern = "^(%s*%-%s*)%[[%sxX]%](%s*%-%s*)", replacement = "%1" .. checkbox .. "%2" },
                    -- Indented format
                    { pattern = "^(%s+%-%s*)%[[%sxX]%](%s*)", replacement = "%1" .. checkbox .. "%2" }
                }

                local new_line = line
                local matched = false
                for _, p in ipairs(patterns) do
                    local test_line = line:gsub(p.pattern, p.replacement)
                    if test_line ~= line then
                        new_line = test_line
                        matched = true
        --                         vim.notify("[ObsidianSync] Matched pattern: " .. p.pattern, vim.log.levels.DEBUG)
                        break
                    end
                end

                if matched then
        --                     vim.notify("[ObsidianSync] Updated buffer line: " .. new_line, vim.log.levels.DEBUG)
                    vim.api.nvim_buf_set_lines(ref.bufnr, ref.lnum - 1, ref.lnum, false, {new_line})

                    -- If the buffer has a file name, mark it as modified
                    if vim.api.nvim_buf_get_name(ref.bufnr) ~= "" then
                        vim.api.nvim_buf_set_option(ref.bufnr, 'modified', true)
                    end
                    return true
                else
                    vim.notify("[ObsidianSync] Buffer line did not match any checkbox pattern", vim.log.levels.WARN)
                    vim.notify("[ObsidianSync] Expected format: '- [ ] text' or similar", vim.log.levels.WARN)
                end
            else
                vim.notify("[ObsidianSync] Could not get line from buffer", vim.log.levels.WARN)
            end
        else
        --             vim.notify("[ObsidianSync] Buffer not valid, trying file directly", vim.log.levels.DEBUG)
        end

        -- Fallback to file
        if vim.fn.filereadable(ref.file) == 1 then
            local lines = vim.fn.readfile(ref.file)
            if lines and ref.lnum > 0 and ref.lnum <= #lines then
                vim.notify(string.format("[ObsidianSync] Reading file %s, line %d of %d",
                    ref.file, ref.lnum, #lines), vim.log.levels.DEBUG)

                local old_line = lines[ref.lnum]
        --                 vim.notify("[ObsidianSync] Current file line: " .. old_line, vim.log.levels.DEBUG)

                -- Try multiple patterns
                local patterns = {
                    { pattern = "^(%s*%-%s*)%[[%sxX]%](%s*)", replacement = "%1" .. checkbox .. "%2" },
                    { pattern = "^(%s*%-%s*)%[[%sxX]%](%s*%-%s*)", replacement = "%1" .. checkbox .. "%2" },
                    { pattern = "^(%s+%-%s*)%[[%sxX]%](%s*)", replacement = "%1" .. checkbox .. "%2" }
                }

                local new_line = old_line
                local matched = false
                for _, p in ipairs(patterns) do
                    local test_line = old_line:gsub(p.pattern, p.replacement)
                    if test_line ~= old_line then
                        new_line = test_line
                        matched = true
        --                         vim.notify("[ObsidianSync] Matched pattern in file: " .. p.pattern, vim.log.levels.DEBUG)
                        break
                    end
                end

                if matched then
                    lines[ref.lnum] = new_line
                    vim.fn.writefile(lines, ref.file)
                    -- vim.notify("[ObsidianSync] File updated successfully: " .. new_line, vim.log.levels.INFO)

                    -- Reload buffer if it's open to reflect changes
                    if ref.bufnr and vim.api.nvim_buf_is_valid(ref.bufnr) then
                        vim.api.nvim_buf_call(ref.bufnr, function()
                            vim.cmd('checktime')
                        end)
                    end
                    return true
                else
                    vim.notify("[ObsidianSync] File line did not match any checkbox pattern", vim.log.levels.WARN)
                end
            else
                vim.notify(string.format("[ObsidianSync] Invalid line number %d for file with %d lines",
                    ref.lnum, #lines), vim.log.levels.ERROR)
            end
        else
            vim.notify("[ObsidianSync] File not readable: " .. ref.file, vim.log.levels.ERROR)
        end

        vim.notify("[ObsidianSync] Could not sync - exhausted all options", vim.log.levels.WARN)
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
            local checkbox, text = line:match("^%s*%- %[(%s?)%]%s+(.+)")
            if checkbox and text then
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
                        list = todo_list
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

    -- Get current todo index (helper for hooks)
    function M.get_current_todo_index(win_id)
        if not win_id or not vim.api.nvim_win_is_valid(win_id) then
            return nil
        end

        local cursor = vim.api.nvim_win_get_cursor(win_id)
        local line_num = cursor[1]
        local buf_id = vim.api.nvim_win_get_buf(win_id)

        -- This is a simplified version - you may need to adjust based on DoIt's actual implementation
        local core = require("doit.core")
        local todos_module = core.get_module("todos")
        if not todos_module then return nil end

        local state = todos_module.state

        -- Calculate header offset
        local line_offset = 1  -- blank line at top
        if state.active_filter then
            line_offset = line_offset + 2  -- blank line + filter text
        end
        if state.active_category then
            line_offset = line_offset + 2  -- blank line + category text
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
        local today = os.date("%Y-%m-%d")
        local file = vim.fn.expand(M.config.vault_path .. "/daily/" .. today .. ".md")

        if vim.fn.filereadable(file) == 1 then
            vim.cmd("edit " .. file)
            local count = M.import_current_buffer()
            vim.notify("Imported " .. count .. " todos from today's note", vim.log.levels.INFO)
        else
            vim.notify("Today's daily note not found", vim.log.levels.WARN)
        end
    end, { desc = "Import todos from today's daily note" })

    -- Show sync status
    vim.api.nvim_create_user_command("DoItSyncStatus", function()
        local ref_count = vim.tbl_count(M.refs)
        local buffer_count = 0

        for _, ref in pairs(M.refs) do
            if vim.api.nvim_buf_is_valid(ref.bufnr) then
                buffer_count = buffer_count + 1
            end
        end

        vim.notify(string.format(
            "Tracking %d todos\n%d with open buffers\n%d total references",
            ref_count, buffer_count, vim.tbl_count(M.imported_lines)
        ), vim.log.levels.INFO)
    end, { desc = "Show DoIt-Obsidian sync status" })

    -- Debug: Test sync for a specific todo
    vim.api.nvim_create_user_command("DoItTestSync", function(opts)
        local todo_id = opts.args
        if todo_id == "" then
            -- Try to get the first todo with a ref
            todo_id = next(M.refs)
            if not todo_id then
                vim.notify("No todos with Obsidian references found", vim.log.levels.WARN)
                return
            end
        end

        vim.notify("Testing sync for todo: " .. todo_id, vim.log.levels.INFO)

        local ref = M.refs[todo_id]
        if not ref then
            vim.notify("No reference found for todo: " .. todo_id, vim.log.levels.ERROR)
            return
        end

        vim.notify(string.format("Reference: File=%s, Line=%d, List=%s",
            ref.file, ref.lnum, ref.list or "unknown"), vim.log.levels.INFO)

        -- Find the todo
        local todo = M.find_todo_by_id(todo_id, ref.list)
        if not todo then
            vim.notify("Todo not found in DoIt", vim.log.levels.ERROR)
            return
        end

        vim.notify(string.format("Todo state: done=%s, in_progress=%s, text=%s",
            tostring(todo.done), tostring(todo.in_progress),
            string.sub(todo.text, 1, 50)), vim.log.levels.INFO)

        -- Try to sync
        local success = M.sync_completion(todo_id, todo)
        if success then
            vim.notify("Sync completed successfully!", vim.log.levels.INFO)
        else
            vim.notify("Sync failed - check debug messages", vim.log.levels.ERROR)
        end
    end, { nargs = "?", desc = "Test sync for a specific todo ID" })

    -- Debug: List all references
    vim.api.nvim_create_user_command("DoItListRefs", function()
        if vim.tbl_count(M.refs) == 0 then
            vim.notify("No Obsidian references tracked", vim.log.levels.INFO)
            return
        end

        local output = {}
        for todo_id, ref in pairs(M.refs) do
            table.insert(output, string.format("ID: %s -> File: %s, Line: %d, List: %s",
                todo_id, vim.fn.fnamemodify(ref.file, ":t"), ref.lnum, ref.list or "unknown"))
        end

        vim.notify("Obsidian References:\n" .. table.concat(output, "\n"), vim.log.levels.INFO)
    end, { desc = "List all Obsidian-DoIt references" })
end

-- Setup autocmds
function M.setup_autocmds()
    local group = vim.api.nvim_create_augroup("DoItObsidianSync", { clear = true })

    -- Auto-import on daily note open
    if M.config.auto_import_on_open then
        vim.api.nvim_create_autocmd({"BufReadPost"}, {
            group = group,
            pattern = "**/Recharge-Notes/daily/*.md",
            callback = function(ev)
                vim.defer_fn(function()
                    local count = M.import_current_buffer()
                    if count > 0 then
                        -- vim.notify("Auto-imported " .. count .. " todos from daily note", vim.log.levels.INFO)
                    end
                end, 100)
            end
        })
    end

    -- Refresh references when entering Obsidian buffers
    vim.api.nvim_create_autocmd({"BufEnter"}, {
        group = group,
        pattern = "**/Recharge-Notes/**/*.md",
        callback = function(ev)
            M.refresh_buffer_refs(ev.buf)
        end
    })

    -- Setup keymaps in Obsidian buffers
    vim.api.nvim_create_autocmd("BufEnter", {
        group = group,
        pattern = "**/Recharge-Notes/**/*.md",
        callback = function()
            vim.keymap.set("n", M.config.keymaps.import_buffer, ":DoItImportBuffer<CR>",
                { buffer = true, desc = "Import todos to DoIt" })

            vim.keymap.set("n", M.config.keymaps.send_current, function()
                -- Send current line to DoIt
                local line = vim.api.nvim_get_current_line()
                local lnum = vim.fn.line(".")
                local checkbox, text = line:match("^%s*%- %[(%s?)%]%s+(.+)")

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
                        vim.api.nvim_buf_set_lines(0, lnum - 1, lnum, false, {line})

                        -- Track reference
                        M.refs[todo.id] = {
                            bufnr = vim.api.nvim_get_current_buf(),
                            lnum = lnum,
                            file = file,
                            date = os.date("%Y-%m-%d"),
                            list = target_list
                        }

                        -- vim.notify("Added to DoIt (" .. target_list .. ")", vim.log.levels.INFO)
                    end
                end
            end, { buffer = true, desc = "Send current todo to DoIt" })
        end
    })
end

-- Setup integration hooks
function M.setup_hooks()
    -- Hook into DoIt's toggle action for completion sync
    vim.defer_fn(function()
        local todo_actions = require("doit.ui.todo_actions")
        if not todo_actions then
            vim.notify("[ObsidianSync] todo_actions not found", vim.log.levels.WARN)
            return
        end

        local original_toggle = todo_actions.toggle_todo

        todo_actions.toggle_todo = function(win_id, on_render)
            -- Get todo info before toggle
            local todo_index = M.get_current_todo_index(win_id)

            local core = require("doit.core")
            local todos_module = core.get_module("todos")

            local todo_before = nil
            local todo_id = nil

            if todos_module and todos_module.state and todo_index then
                todo_before = todos_module.state.todos[todo_index]
                if todo_before then
                    todo_id = todo_before.id
                    vim.notify(string.format("[ObsidianSync] Before toggle - ID: %s, done: %s, in_progress: %s",
                        todo_id, tostring(todo_before.done), tostring(todo_before.in_progress)), vim.log.levels.DEBUG)
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
                    vim.notify(string.format("[ObsidianSync] After toggle - ID: %s, done: %s, in_progress: %s",
                        todo_id, tostring(updated_todo.done), tostring(updated_todo.in_progress)), vim.log.levels.DEBUG)

                    local success = M.sync_completion(todo_id, updated_todo)
                    if success then
                        local state_str = updated_todo.done and "completed" or
                                        updated_todo.in_progress and "in progress" or
                                        "not started"
                        -- vim.notify("[ObsidianSync] Successfully synced to Obsidian: " .. state_str, vim.log.levels.INFO)
                    else
                        vim.notify("[ObsidianSync] Failed to sync to Obsidian", vim.log.levels.WARN)
                    end
                else
                    vim.notify("[ObsidianSync] Could not find updated todo after toggle", vim.log.levels.WARN)
                end
            elseif todo_id and not M.refs[todo_id] then
        --                 vim.notify("[ObsidianSync] No Obsidian reference for todo: " .. todo_id, vim.log.levels.DEBUG)
            end
        end

        -- vim.notify("[ObsidianSync] Hook registered successfully", vim.log.levels.INFO)
    end, 500)  -- Delay to ensure DoIt is fully loaded

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
        --                     vim.notify("Updated Obsidian ref for moved todo", vim.log.levels.DEBUG)
                end
            end)
        end
    end, 500)
end

return M