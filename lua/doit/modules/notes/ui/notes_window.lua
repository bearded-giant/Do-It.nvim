-- notes editor window
local api = vim.api
local M = {}

local config
local state
local parent_module

local buf = nil
local win = nil
local current_note = nil

function M.setup(module)
    parent_module = module
    config = module.config
    state = module.state
    return M
end

function M.is_open()
    return win and api.nvim_win_is_valid(win)
end

local function create_buf()
    buf = api.nvim_create_buf(false, true)
    api.nvim_buf_set_option(buf, "bufhidden", "wipe")
    api.nvim_buf_set_option(buf, "modifiable", true)
    api.nvim_buf_set_option(buf, "filetype", config.markdown.syntax or "markdown")

    if config.markdown.highlight then
        if config.markdown.conceallevel then
            pcall(api.nvim_buf_set_option, buf, "conceallevel", config.markdown.conceallevel)
        end
        if config.markdown.concealcursor then
            pcall(api.nvim_buf_set_option, buf, "concealcursor", config.markdown.concealcursor)
        end
    end

    return buf
end

local function create_win()
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

    local title = " Note: " .. (current_note and current_note.title or "Untitled") .. " "

    win = api.nvim_open_win(buf, true, {
        relative = "editor",
        width = width,
        height = height,
        row = row,
        col = col,
        style = "minimal",
        border = win_config.border or "rounded",
        title = title,
        title_pos = win_config.title_pos or "center",
    })

    api.nvim_win_set_option(win, "wrap", true)
    api.nvim_win_set_option(win, "linebreak", true)
    api.nvim_win_set_option(win, "number", true)

    if config.markdown and config.markdown.highlight then
        api.nvim_win_set_option(win, "spell", true)
        api.nvim_win_set_option(win, "list", false)
        api.nvim_win_set_option(win, "textwidth", 80)
    end

    return win
end

local function render_note()
    if not buf or not win then return end

    local body = (current_note and current_note.body) or ""
    local lines = {}

    if body ~= "" then
        for line in body:gmatch("([^\r\n]*)") do
            table.insert(lines, line)
        end
        -- gmatch on empty capture produces trailing empty; trim doubled trailing
        while #lines > 1 and lines[#lines] == "" and lines[#lines - 1] == "" do
            table.remove(lines)
        end
    end

    if #lines == 0 then
        table.insert(lines, "")
    end

    api.nvim_buf_set_option(buf, "modifiable", true)
    api.nvim_buf_set_lines(buf, 0, -1, false, lines)

    if config.markdown and config.markdown.highlight then
        pcall(function()
            api.nvim_buf_set_option(buf, "syntax", "markdown")
        end)
    end

    if body == "" then
        pcall(api.nvim_win_set_cursor, win, { 1, 0 })
    end
end

local function get_buffer_content()
    if not buf or not api.nvim_buf_is_valid(buf) then return "" end
    local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
    while #lines > 0 and lines[#lines] == "" do
        table.remove(lines)
    end
    return table.concat(lines, "\n")
end

local function save_current_note()
    if not current_note then return end
    current_note.body = get_buffer_content()
    current_note.updated_at = os.time()
    state.save_note(current_note)
end

local function return_to_picker()
    save_current_note()

    if win and api.nvim_win_is_valid(win) then
        api.nvim_win_close(win, true)
    end
    win = nil
    buf = nil
    current_note = nil

    vim.schedule(function()
        parent_module.ui.notes_picker.open()
    end)
end

local function setup_keymaps()
    if not buf then return end

    local keys = config.keymaps.editor

    local function km(key, cb, mode)
        if not key then return end
        api.nvim_buf_set_keymap(buf, mode or "n", key, "", {
            noremap = true,
            silent = true,
            callback = cb,
        })
    end

    -- q: save and return to picker
    km(keys.close, function()
        return_to_picker()
    end)

    if config.markdown and config.markdown.highlight then
        km(keys.format, function()
            vim.cmd("normal! gqip")
        end)

        km(keys.heading1, function()
            local cursor = api.nvim_win_get_cursor(win)
            local line_nr = cursor[1] - 1
            local line = api.nvim_buf_get_lines(buf, line_nr, line_nr + 1, false)[1]
            line = line:gsub("^%s*#+%s*", "")
            api.nvim_buf_set_lines(buf, line_nr, line_nr + 1, false, { "# " .. line })
        end)

        km(keys.heading2, function()
            local cursor = api.nvim_win_get_cursor(win)
            local line_nr = cursor[1] - 1
            local line = api.nvim_buf_get_lines(buf, line_nr, line_nr + 1, false)[1]
            line = line:gsub("^%s*#+%s*", "")
            api.nvim_buf_set_lines(buf, line_nr, line_nr + 1, false, { "## " .. line })
        end)

        km(keys.heading3, function()
            local cursor = api.nvim_win_get_cursor(win)
            local line_nr = cursor[1] - 1
            local line = api.nvim_buf_get_lines(buf, line_nr, line_nr + 1, false)[1]
            line = line:gsub("^%s*#+%s*", "")
            api.nvim_buf_set_lines(buf, line_nr, line_nr + 1, false, { "### " .. line })
        end)

        km(keys.bold, function()
            local start_pos = vim.fn.getpos("'<")
            local end_pos = vim.fn.getpos("'>")
            local lines = api.nvim_buf_get_lines(buf, start_pos[2] - 1, end_pos[2], false)
            if #lines == 1 then
                local selected = lines[1]:sub(start_pos[3], end_pos[3])
                local new_line = lines[1]:sub(1, start_pos[3] - 1) .. "**" .. selected .. "**" .. lines[1]:sub(end_pos[3] + 1)
                api.nvim_buf_set_lines(buf, start_pos[2] - 1, start_pos[2], false, { new_line })
            end
        end, "v")

        km(keys.italic, function()
            local start_pos = vim.fn.getpos("'<")
            local end_pos = vim.fn.getpos("'>")
            local lines = api.nvim_buf_get_lines(buf, start_pos[2] - 1, end_pos[2], false)
            if #lines == 1 then
                local selected = lines[1]:sub(start_pos[3], end_pos[3])
                local new_line = lines[1]:sub(1, start_pos[3] - 1) .. "*" .. selected .. "*" .. lines[1]:sub(end_pos[3] + 1)
                api.nvim_buf_set_lines(buf, start_pos[2] - 1, start_pos[2], false, { new_line })
            end
        end, "v")

        km(keys.link, function()
            vim.ui.input({ prompt = "Enter URL: " }, function(url)
                if not url or url == "" then return end
                vim.ui.input({ prompt = "Enter link text (optional): " }, function(text)
                    text = text or url
                    local cursor = api.nvim_win_get_cursor(win)
                    local line_nr = cursor[1] - 1
                    local line = api.nvim_buf_get_lines(buf, line_nr, line_nr + 1, false)[1]
                    local col = cursor[2]
                    local link_text = "[" .. text .. "](" .. url .. ")"
                    local new_line = line:sub(1, col) .. link_text .. line:sub(col + 1)
                    api.nvim_buf_set_lines(buf, line_nr, line_nr + 1, false, { new_line })
                    pcall(api.nvim_win_set_cursor, win, { cursor[1], col + #link_text })
                end)
            end)
        end)

        km(keys.list_item, function()
            local cursor = api.nvim_win_get_cursor(win)
            local line_nr = cursor[1] - 1
            local line = api.nvim_buf_get_lines(buf, line_nr, line_nr + 1, false)[1]
            if line:match("^%s*$") then
                api.nvim_buf_set_lines(buf, line_nr, line_nr + 1, false, { "- " })
                api.nvim_win_set_cursor(win, { cursor[1], 2 })
            else
                api.nvim_buf_set_lines(buf, line_nr + 1, line_nr + 1, false, { "- " })
                api.nvim_win_set_cursor(win, { cursor[1] + 1, 2 })
            end
        end)
    end

    -- auto-save on leave
    local group = api.nvim_create_augroup("DoItNotesEditorSave", { clear = true })
    api.nvim_create_autocmd({ "BufLeave", "WinLeave" }, {
        group = group,
        buffer = buf,
        callback = function()
            save_current_note()
        end,
    })

    -- close on focus lost so the float doesn't persist across tmux panes
    local focus_group = api.nvim_create_augroup("DoItNotesEditorFocus", { clear = true })
    api.nvim_create_autocmd("FocusLost", {
        group = focus_group,
        callback = function()
            if M.is_open() then
                save_current_note()
                api.nvim_win_close(win, true)
                win = nil
                buf = nil
                current_note = nil
            end
            pcall(api.nvim_del_augroup_by_name, "DoItNotesEditorFocus")
        end,
    })
end

-- open a specific note in the editor
function M.open_note(note)
    if not note then return end
    current_note = note

    create_buf()
    create_win()
    render_note()
    setup_keymaps()
end

-- close editor (used externally)
function M.close()
    if M.is_open() then
        save_current_note()
        api.nvim_win_close(win, true)
    end
    win = nil
    buf = nil
    current_note = nil
end

-- legacy toggle (opens picker now)
function M.toggle_notes_window()
    parent_module.ui.notes_picker.toggle()
end

return M
