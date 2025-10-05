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
                        date = file:match("(%d%d%d%d%-%d%d%-%d%d)")
                    }

                    -- Mark line as imported
                    M.imported_lines[file .. ":" .. lnum] = new_todo.id

                    -- Add marker to line
                    line = line .. " <!-- doit:" .. new_todo.id .. " -->"
                    imported = imported + 1

                elseif existing_id then
                    -- Already imported - refresh reference
                    M.refs[existing_id] = {
                        bufnr = bufnr,
                        lnum = lnum,
                        file = file,
                        date = file:match("(%d%d%d%d%-%d%d%-%d%d)")
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
        if not ref then return false end

        -- Only mark checkbox as done when todo is completed (not in_progress)
        local checkbox = (todo_state.done and not todo_state.in_progress) and "[x]" or "[ ]"

        -- Try buffer first (more efficient if open)
        if vim.api.nvim_buf_is_valid(ref.bufnr) then
            local line = vim.api.nvim_buf_get_lines(ref.bufnr, ref.lnum - 1, ref.lnum, false)[1]
            if line then
                line = line:gsub("%[.%]", checkbox)
                vim.api.nvim_buf_set_lines(ref.bufnr, ref.lnum - 1, ref.lnum, false, {line})
                return true
            end
        end

        -- Fallback to file
        local lines = vim.fn.readfile(ref.file)
        if lines[ref.lnum] then
            lines[ref.lnum] = lines[ref.lnum]:gsub("%[.%]", checkbox)
            vim.fn.writefile(lines, ref.file)
            return true
        end

        return false
    end

    -- Refresh references for a buffer
    function M.refresh_buffer_refs(bufnr)
        local file = vim.api.nvim_buf_get_name(bufnr)
        local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

        for lnum, line in ipairs(lines) do
            local checkbox, text = line:match("^%s*%- %[(%s?)%]%s+(.+)")
            if checkbox and text then
                local existing_id = text:match("<!%-%- doit:(%S+) %-%->")
                if existing_id then
                    M.refs[existing_id] = {
                        bufnr = bufnr,
                        lnum = lnum,
                        file = file,
                        date = file:match("(%d%d%d%d%-%d%d%-%d%d)")
                    }
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
                        vim.notify("Auto-imported " .. count .. " todos from daily note", vim.log.levels.INFO)
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

                    local core = require("doit.core")
                    local todos_module = core.get_module("todos")
                    if todos_module and todos_module.state then
                        local todo = todos_module.state.add_todo(clean_text, "quick")

                        -- Add marker
                        line = line .. " <!-- doit:" .. todo.id .. " -->"
                        vim.api.nvim_buf_set_lines(0, lnum - 1, lnum, false, {line})

                        -- Track reference
                        M.refs[todo.id] = {
                            bufnr = vim.api.nvim_get_current_buf(),
                            lnum = lnum,
                            file = vim.api.nvim_buf_get_name(0),
                            date = os.date("%Y-%m-%d")
                        }

                        vim.notify("Added to DoIt", vim.log.levels.INFO)
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
        if not todo_actions then return end

        local original_toggle = todo_actions.toggle_todo

        todo_actions.toggle_todo = function(win_id, on_render)
            -- Get todo info before toggle
            local todo_index = M.get_current_todo_index(win_id)

            local core = require("doit.core")
            local todos_module = core.get_module("todos")

            local todo = nil
            if todos_module and todos_module.state and todo_index then
                todo = todos_module.state.todos[todo_index]
            end

            -- Execute original toggle
            original_toggle(win_id, on_render)

            -- Sync to Obsidian if we have a reference
            if todo and M.refs[todo.id] and M.config.sync_completions then
                vim.defer_fn(function()
                    -- Get the updated todo state after toggle
                    local updated_todo = todos_module.state.todos[todo_index]
                    if updated_todo then
                        M.sync_completion(todo.id, updated_todo)
                    end
                end, 50)
            end
        end
    end, 500)  -- Delay to ensure DoIt is fully loaded
end

return M