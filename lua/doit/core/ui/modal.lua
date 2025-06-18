local M = {}

-- Modal types: 'list', 'list_with_preview', 'form', 'confirm'
local function create_modal(opts)
    local vim = vim
    local api = vim.api
    
    opts = vim.tbl_deep_extend("force", {
        type = "list",
        title = " Modal ",
        width_ratio = 0.6,
        height_ratio = 0.6,
        preview_enabled = false,
        list_panel_ratio = 0.4,
        border = "rounded",
        on_select = function() end,
        on_close = function() end,
        keymaps = {},
    }, opts or {})
    
    local ui = api.nvim_list_uis()[1]
    local total_width = math.min(120, math.floor(ui.width * opts.width_ratio))
    local total_height = math.min(50, math.floor(ui.height * opts.height_ratio))
    
    local main_width = opts.preview_enabled and math.floor(total_width * opts.list_panel_ratio) or total_width
    local preview_width = total_width - main_width - 3
    
    local row = math.floor((ui.height - total_height) / 2)
    local col = math.floor((ui.width - total_width) / 2)
    
    local modal = {
        opts = opts,
        main_buf = nil,
        main_win = nil,
        preview_buf = nil,
        preview_win = nil,
        selected_index = 1,
        items = {},
    }
    
    function modal:create_windows()
        -- Main buffer
        self.main_buf = api.nvim_create_buf(false, true)
        api.nvim_buf_set_option(self.main_buf, "bufhidden", "wipe")
        api.nvim_buf_set_option(self.main_buf, "modifiable", true)
        
        -- Main window
        self.main_win = api.nvim_open_win(self.main_buf, true, {
            relative = "editor",
            row = row,
            col = col,
            width = main_width,
            height = total_height,
            style = "minimal",
            border = opts.border,
            title = opts.title,
            title_pos = "center"
        })
        
        api.nvim_win_set_option(self.main_win, "wrap", false)
        api.nvim_win_set_option(self.main_win, "number", false)
        api.nvim_win_set_option(self.main_win, "cursorline", true)
        
        if opts.preview_enabled then
            -- Preview buffer
            self.preview_buf = api.nvim_create_buf(false, true)
            api.nvim_buf_set_option(self.preview_buf, "bufhidden", "wipe")
            api.nvim_buf_set_option(self.preview_buf, "modifiable", true)
            
            -- Preview window
            self.preview_win = api.nvim_open_win(self.preview_buf, false, {
                relative = "editor",
                row = row,
                col = col + main_width + 2,
                width = preview_width,
                height = total_height,
                style = "minimal",
                border = opts.border,
                title = " Preview ",
                title_pos = "center"
            })
            
            api.nvim_win_set_option(self.preview_win, "wrap", true)
            api.nvim_win_set_option(self.preview_win, "number", false)
        end
    end
    
    function modal:close()
        if self.preview_win and api.nvim_win_is_valid(self.preview_win) then
            api.nvim_win_close(self.preview_win, true)
        end
        if self.main_win and api.nvim_win_is_valid(self.main_win) then
            api.nvim_win_close(self.main_win, true)
        end
        self.main_buf = nil
        self.main_win = nil
        self.preview_buf = nil
        self.preview_win = nil
        
        if self.opts.on_close then
            self.opts.on_close()
        end
    end
    
    function modal:set_items(items)
        self.items = items
        self.selected_index = 1
    end
    
    function modal:render_list(lines)
        if not self.main_buf or not api.nvim_buf_is_valid(self.main_buf) then
            return
        end
        
        api.nvim_buf_set_option(self.main_buf, "modifiable", true)
        api.nvim_buf_set_lines(self.main_buf, 0, -1, false, lines)
        api.nvim_buf_set_option(self.main_buf, "modifiable", false)
    end
    
    function modal:render_preview(content)
        if not self.preview_buf or not api.nvim_buf_is_valid(self.preview_buf) then
            return
        end
        
        local lines = type(content) == "table" and content or vim.split(content, "\n")
        
        api.nvim_buf_set_option(self.preview_buf, "modifiable", true)
        api.nvim_buf_set_lines(self.preview_buf, 0, -1, false, lines)
        api.nvim_buf_set_option(self.preview_buf, "modifiable", false)
    end
    
    function modal:setup_keymaps()
        local function set_keymap(key, callback)
            api.nvim_buf_set_keymap(self.main_buf, "n", key, "", {
                nowait = true,
                noremap = true,
                silent = true,
                callback = callback
            })
        end
        
        -- Default keymaps
        set_keymap("q", function() self:close() end)
        set_keymap("<Esc>", function() self:close() end)
        
        -- Navigation
        set_keymap("j", function()
            if self.selected_index < #self.items then
                self.selected_index = self.selected_index + 1
                if self.opts.on_selection_change then
                    self.opts.on_selection_change(self.selected_index, self.items[self.selected_index])
                end
            end
        end)
        
        set_keymap("k", function()
            if self.selected_index > 1 then
                self.selected_index = self.selected_index - 1
                if self.opts.on_selection_change then
                    self.opts.on_selection_change(self.selected_index, self.items[self.selected_index])
                end
            end
        end)
        
        -- Selection
        set_keymap("<CR>", function()
            if self.items[self.selected_index] then
                self.opts.on_select(self.selected_index, self.items[self.selected_index])
            end
        end)
        
        set_keymap("<Space>", function()
            if self.items[self.selected_index] then
                self.opts.on_select(self.selected_index, self.items[self.selected_index])
            end
        end)
        
        -- Number keys for quick selection (if applicable)
        if opts.type == "list" or opts.type == "list_with_preview" then
            for i = 1, 9 do
                set_keymap(tostring(i), function()
                    if i <= #self.items then
                        self.selected_index = i
                        if self.opts.on_selection_change then
                            self.opts.on_selection_change(self.selected_index, self.items[self.selected_index])
                        end
                    end
                end)
            end
            
            set_keymap("0", function()
                if 10 <= #self.items then
                    self.selected_index = 10
                    if self.opts.on_selection_change then
                        self.opts.on_selection_change(self.selected_index, self.items[self.selected_index])
                    end
                end
            end)
        end
        
        -- Custom keymaps
        for key, callback in pairs(opts.keymaps) do
            set_keymap(key, function()
                callback(self)
            end)
        end
    end
    
    function modal:show()
        self:create_windows()
        self:setup_keymaps()
    end
    
    return modal
end

-- Helper function to create a list selection modal
function M.select_list(opts)
    opts = vim.tbl_deep_extend("force", {
        type = "list_with_preview",
        preview_enabled = true,
    }, opts or {})
    
    return create_modal(opts)
end

-- Helper function to create a simple list modal
function M.list(opts)
    opts = vim.tbl_deep_extend("force", {
        type = "list",
        preview_enabled = false,
    }, opts or {})
    
    return create_modal(opts)
end

-- Helper function to create a confirmation modal
function M.confirm(opts)
    opts = vim.tbl_deep_extend("force", {
        type = "confirm",
        width_ratio = 0.4,
        height_ratio = 0.2,
        preview_enabled = false,
    }, opts or {})
    
    return create_modal(opts)
end

return M