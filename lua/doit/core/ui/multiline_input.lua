local M = {}

function M.create(opts)
    local vim = vim
    local api = vim.api

    opts = vim.tbl_deep_extend("force", {
        prompt = "Input: ",
        default = "",
        on_submit = function() end,
        on_cancel = function() end,
        width_ratio = 0.6,
        min_height = 3,
        max_height = 20,
        border = "rounded",
    }, opts or {})

    local ui = api.nvim_list_uis()[1]
    local width = math.min(80, math.floor(ui.width * opts.width_ratio))

    local buf = api.nvim_create_buf(false, true)
    api.nvim_buf_set_option(buf, "bufhidden", "wipe")
    api.nvim_buf_set_option(buf, "buftype", "nofile")
    api.nvim_buf_set_option(buf, "modifiable", true)

    if opts.default and opts.default ~= "" then
        local lines = vim.split(opts.default, "\n", { plain = true })
        api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    end

    local function calculate_height()
        local line_count = api.nvim_buf_line_count(buf)
        return math.max(opts.min_height, math.min(line_count, opts.max_height))
    end

    local function get_window_config(height)
        local row = math.floor(ui.height * 0.05)
        local col = math.floor((ui.width - width) / 2)
        return {
            relative = "editor",
            row = row,
            col = col,
            width = width,
            height = height,
            style = "minimal",
            border = opts.border,
            title = " " .. opts.prompt .. " ",
            title_pos = "center",
            footer = " <Enter>: new line | <C-s>: submit | <Esc>: cancel ",
            footer_pos = "center",
        }
    end

    local initial_height = calculate_height()
    local win = api.nvim_open_win(buf, true, get_window_config(initial_height))

    api.nvim_win_set_option(win, "wrap", true)
    api.nvim_win_set_option(win, "scrolloff", 1)

    local function resize_window()
        if win and api.nvim_win_is_valid(win) then
            local new_height = calculate_height()
            api.nvim_win_set_config(win, get_window_config(new_height))
        end
    end

    local resize_autocmd = api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
        buffer = buf,
        callback = resize_window,
    })

    vim.cmd("startinsert")

    local function close_and_cleanup()
        -- Clear autocmd first
        pcall(api.nvim_del_autocmd, resize_autocmd)

        -- Defer window close to avoid treesitter race condition
        vim.schedule(function()
            if win and api.nvim_win_is_valid(win) then
                pcall(api.nvim_win_close, win, true)
            end
        end)
    end

    local function submit()
        local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
        local text = table.concat(lines, "\n")
        close_and_cleanup()
        opts.on_submit(text)
    end

    local function cancel()
        close_and_cleanup()
        opts.on_cancel()
    end

    api.nvim_buf_set_keymap(buf, "i", "<C-s>", "", {
        nowait = true,
        noremap = true,
        silent = true,
        callback = submit
    })

    api.nvim_buf_set_keymap(buf, "n", "<CR>", "", {
        nowait = true,
        noremap = true,
        silent = true,
        callback = submit
    })

    api.nvim_buf_set_keymap(buf, "i", "<Esc>", "", {
        nowait = true,
        noremap = true,
        silent = true,
        callback = cancel
    })

    api.nvim_buf_set_keymap(buf, "n", "<Esc>", "", {
        nowait = true,
        noremap = true,
        silent = true,
        callback = cancel
    })

    api.nvim_buf_set_keymap(buf, "n", "q", "", {
        nowait = true,
        noremap = true,
        silent = true,
        callback = cancel
    })

    vim.api.nvim_create_autocmd("BufLeave", {
        buffer = buf,
        callback = function()
            cancel()
            return true
        end,
        once = true,
    })

    return {
        buf = buf,
        win = win,
        close = close_and_cleanup,
    }
end

return M