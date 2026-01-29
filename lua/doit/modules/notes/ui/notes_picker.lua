-- notes picker window
local api = vim.api
local M = {}

local config
local state
local parent_module

local buf = nil
local win = nil

-- currently displayed notes (ordered), maps line -> note
local displayed_notes = {}

function M.setup(module)
    parent_module = module
    config = module.config
    state = module.state
    return M
end

function M.is_open()
    return win and api.nvim_win_is_valid(win)
end

local function scope_label()
    if state.notes.current_mode == "global" then
        return "Global"
    end
    return "Project"
end

local function build_header_lines()
    local lines = {}
    local keys = config.keymaps.picker
    table.insert(lines, string.format(
        " %s: New   %s: Delete   %s: Search   %s: Scope   %s: Sort (%s)",
        keys.new, keys.delete, keys.search, keys.scope_toggle,
        keys.sort, state.get_sort_label()
    ))
    table.insert(lines, string.rep("-", 50))
    return lines
end

-- header line count (used to calculate note index from cursor)
local HEADER_LINES = 2

local function pad_right(str, width)
    if #str >= width then return str:sub(1, width) end
    return str .. string.rep(" ", width - #str)
end

local function build_note_lines(notes)
    local lines = {}
    displayed_notes = {}

    if #notes == 0 then
        table.insert(lines, "  (no notes)")
        return lines
    end

    -- calculate available width for title (leave room for timestamp)
    local time_col_width = 12

    for i, note in ipairs(notes) do
        local title = note.title or "Untitled"
        if #title > 40 then
            title = title:sub(1, 37) .. "..."
        end
        local time_str = state.relative_time(note.updated_at or note.created_at)
        local line = "  " .. pad_right(title, 42) .. time_str
        table.insert(lines, line)
        displayed_notes[i] = note
    end

    return lines
end

function M.render()
    if not buf or not api.nvim_buf_is_valid(buf) then return end

    local notes = state.get_sorted_filtered_notes()

    local lines = {}
    local header = build_header_lines()
    for _, l in ipairs(header) do
        table.insert(lines, l)
    end
    local note_lines = build_note_lines(notes)
    for _, l in ipairs(note_lines) do
        table.insert(lines, l)
    end

    api.nvim_buf_set_option(buf, "modifiable", true)
    api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    api.nvim_buf_set_option(buf, "modifiable", false)

    M.update_title()

    -- place cursor on first note line if possible
    if win and api.nvim_win_is_valid(win) then
        local target = HEADER_LINES + 1
        local line_count = api.nvim_buf_line_count(buf)
        if target > line_count then target = line_count end
        pcall(api.nvim_win_set_cursor, win, { target, 2 })
    end
end

function M.get_selected_note()
    if not win or not api.nvim_win_is_valid(win) then return nil end
    local cursor = api.nvim_win_get_cursor(win)
    local idx = cursor[1] - HEADER_LINES
    if idx < 1 or not displayed_notes[idx] then return nil end
    return displayed_notes[idx]
end

function M.update_title()
    if not win or not api.nvim_win_is_valid(win) then return end
    local win_config = config.ui and config.ui.window or config.window
    local title = string.format(" Notes [%s] ", scope_label())
    pcall(api.nvim_win_set_config, win, {
        title = title,
        title_pos = win_config.title_pos or "center",
    })
end

function M.open()
    if M.is_open() then
        M.render()
        return
    end

    state.load_notes()

    -- create buffer
    buf = api.nvim_create_buf(false, true)
    api.nvim_buf_set_option(buf, "bufhidden", "wipe")
    api.nvim_buf_set_option(buf, "buftype", "nofile")
    api.nvim_buf_set_option(buf, "modifiable", false)

    -- window dimensions
    local win_config = config.ui and config.ui.window or config.window
    local width, height

    if win_config.use_relative then
        width = math.floor(vim.o.columns * (win_config.relative_width or 0.6))
        height = math.floor(vim.o.lines * (win_config.relative_height or 0.6))
    else
        width = type(win_config.width) == "number" and win_config.width > 1
            and win_config.width or math.floor(vim.o.columns * 0.6)
        height = type(win_config.height) == "number" and win_config.height > 1
            and win_config.height or math.floor(vim.o.lines * 0.6)
    end

    local row = math.floor((vim.o.lines - height) / 2)
    local col = math.floor((vim.o.columns - width) / 2)

    win = api.nvim_open_win(buf, true, {
        relative = "editor",
        width = width,
        height = height,
        row = row,
        col = col,
        style = "minimal",
        border = win_config.border or "rounded",
        title = string.format(" Notes [%s] ", scope_label()),
        title_pos = win_config.title_pos or "center",
    })

    api.nvim_win_set_option(win, "cursorline", true)
    api.nvim_win_set_option(win, "wrap", false)

    M.render()
    M.setup_keymaps()

    -- close on focus lost so the float doesn't persist across tmux panes
    local group = api.nvim_create_augroup("DoItNotesPickerFocus", { clear = true })
    api.nvim_create_autocmd("FocusLost", {
        group = group,
        callback = function()
            if M.is_open() then
                M.close()
            end
            pcall(api.nvim_del_augroup_by_name, "DoItNotesPickerFocus")
        end,
    })
end

function M.close()
    state.notes.search_filter = nil
    if win and api.nvim_win_is_valid(win) then
        api.nvim_win_close(win, true)
    end
    win = nil
    buf = nil
    displayed_notes = {}
end

function M.setup_keymaps()
    if not buf then return end

    local keys = config.keymaps.picker
    local function km(key, cb)
        if not key then return end
        api.nvim_buf_set_keymap(buf, "n", key, "", {
            noremap = true,
            silent = true,
            callback = cb,
        })
    end

    -- open selected note in editor
    km(keys.open, function()
        local note = M.get_selected_note()
        if not note then return end
        M.close()
        vim.schedule(function()
            parent_module.ui.notes_window.open_note(note)
        end)
    end)

    -- create new note
    km(keys.new, function()
        vim.ui.input({ prompt = "Note title: " }, function(title)
            if not title or title == "" then return end
            local note = state.create_note(title)
            if note then
                M.close()
                vim.schedule(function()
                    parent_module.ui.notes_window.open_note(note)
                end)
            end
        end)
    end)

    -- delete selected note
    km(keys.delete, function()
        local note = M.get_selected_note()
        if not note then return end
        vim.ui.input({
            prompt = string.format("Delete '%s'? (y/N): ", note.title or "Untitled"),
        }, function(answer)
            if not answer or answer:lower() ~= "y" then return end
            state.delete_note(note.id)
            vim.schedule(function()
                M.render()
            end)
        end)
    end)

    -- toggle scope
    km(keys.scope_toggle, function()
        state.switch_mode()
        M.render()
    end)

    -- cycle sort
    km(keys.sort, function()
        state.cycle_sort()
        M.render()
    end)

    -- search filter
    km(keys.search, function()
        vim.ui.input({ prompt = "Filter: " }, function(query)
            state.notes.search_filter = (query and query ~= "") and query or nil
            vim.schedule(function()
                M.render()
            end)
        end)
    end)

    -- close
    km(keys.close, function()
        M.close()
    end)
end

-- toggle picker open/close
function M.toggle()
    if M.is_open() then
        M.close()
    else
        M.open()
    end
end

return M
