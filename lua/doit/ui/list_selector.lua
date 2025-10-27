local M = {}

local function create_list_selector_window(lists, current_list, callback)
    local vim = vim
    local api = vim.api

    -- Filter out the current list
    local available_lists = {}
    for _, list in ipairs(lists) do
        if list.name ~= current_list then
            table.insert(available_lists, list)
        end
    end

    if #available_lists == 0 then
        vim.notify("No other lists available to move to", vim.log.levels.WARN)
        return
    end

    local selected_index = 1
    local buf_id = api.nvim_create_buf(false, true)
    api.nvim_buf_set_option(buf_id, "bufhidden", "wipe")
    api.nvim_buf_set_option(buf_id, "modifiable", false)

    local ui = api.nvim_list_uis()[1]
    local width = math.min(50, math.floor(ui.width * 0.4))
    local height = math.min(#available_lists + 4, math.floor(ui.height * 0.5))

    local row = math.floor((ui.height - height) / 2)
    local col = math.floor((ui.width - width) / 2)

    local win_id = api.nvim_open_win(buf_id, true, {
        relative = "editor",
        row = row,
        col = col,
        width = width,
        height = height,
        style = "minimal",
        border = "rounded",
        title = " Move to List ",
        title_pos = "center",
        footer = " <Enter> to select | <Esc> to cancel ",
        footer_pos = "center"
    })

    api.nvim_win_set_option(win_id, "wrap", false)
    api.nvim_win_set_option(win_id, "number", false)
    api.nvim_win_set_option(win_id, "cursorline", true)

    local function render()
        local lines = { "" }

        for i, list in ipairs(available_lists) do
            local prefix = (i == selected_index) and "> " or "  "
            local todo_count_str = ""
            if list.metadata and list.metadata.todo_count then
                todo_count_str = string.format(" (%d)", list.metadata.todo_count)
            end
            table.insert(lines, prefix .. list.name .. todo_count_str)
        end

        table.insert(lines, "")

        api.nvim_buf_set_option(buf_id, "modifiable", true)
        api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)
        api.nvim_buf_set_option(buf_id, "modifiable", false)

        -- Set cursor position
        pcall(api.nvim_win_set_cursor, win_id, { selected_index + 1, 0 })
    end

    local function close_window()
        if win_id and api.nvim_win_is_valid(win_id) then
            api.nvim_win_close(win_id, true)
        end
    end

    local function select_list()
        if available_lists[selected_index] then
            local selected_list = available_lists[selected_index].name
            close_window()
            if callback then
                callback(selected_list)
            end
        end
    end

    -- Navigation keymaps
    local keymap_opts = { buffer = buf_id, nowait = true }

    vim.keymap.set("n", "j", function()
        selected_index = math.min(selected_index + 1, #available_lists)
        render()
    end, keymap_opts)

    vim.keymap.set("n", "k", function()
        selected_index = math.max(selected_index - 1, 1)
        render()
    end, keymap_opts)

    vim.keymap.set("n", "<Down>", function()
        selected_index = math.min(selected_index + 1, #available_lists)
        render()
    end, keymap_opts)

    vim.keymap.set("n", "<Up>", function()
        selected_index = math.max(selected_index - 1, 1)
        render()
    end, keymap_opts)

    vim.keymap.set("n", "<CR>", select_list, keymap_opts)

    vim.keymap.set("n", "<Esc>", function()
        close_window()
    end, keymap_opts)

    vim.keymap.set("n", "q", function()
        close_window()
    end, keymap_opts)

    render()
end

function M.show_list_selector(current_list, callback)
    -- Get the todo module to access state
    local core = require("doit.core")
    local todo_module = core.get_module("todos")

    if not todo_module or not todo_module.state then
        vim.notify("Todo module not available", vim.log.levels.ERROR)
        return
    end

    -- Get available lists
    local lists = todo_module.state.get_available_lists()

    if not lists or #lists <= 1 then
        vim.notify("No other lists available to move to", vim.log.levels.WARN)
        return
    end

    create_list_selector_window(lists, current_list, callback)
end

return M
