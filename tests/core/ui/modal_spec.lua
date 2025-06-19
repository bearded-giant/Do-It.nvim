describe("Core UI Modal", function()
    local modal
    local api = vim.api
    local original_nvim_list_uis
    
    before_each(function()
        -- Mock nvim_list_uis to return a valid UI object for headless tests
        original_nvim_list_uis = vim.api.nvim_list_uis
        vim.api.nvim_list_uis = function()
            return {{
                width = 120,
                height = 40
            }}
        end
        
        package.loaded["doit.core.ui.modal"] = nil
        modal = require("doit.core.ui.modal")
    end)
    
    after_each(function()
        -- Restore original function
        vim.api.nvim_list_uis = original_nvim_list_uis
        
        -- Clean up any open windows
        for _, win in ipairs(api.nvim_list_wins()) do
            if api.nvim_win_get_config(win).relative ~= "" then
                pcall(api.nvim_win_close, win, true)
            end
        end
    end)
    
    it("should create a basic list modal", function()
        local m = modal.list({
            title = "Test List",
            width_ratio = 0.5,
            height_ratio = 0.5
        })
        
        assert.is_not_nil(m)
        assert.equals("list", m.opts.type)
        assert.equals("Test List", m.opts.title)
        assert.is_false(m.opts.preview_enabled)
    end)
    
    it("should create a list with preview modal", function()
        local m = modal.select_list({
            title = "Test Select",
            on_select = function() end
        })
        
        assert.is_not_nil(m)
        assert.equals("list_with_preview", m.opts.type)
        assert.is_true(m.opts.preview_enabled)
    end)
    
    it("should show and close modal windows", function()
        local m = modal.list({
            title = "Test Modal"
        })
        
        m:show()
        
        assert.is_not_nil(m.main_win)
        assert.is_true(api.nvim_win_is_valid(m.main_win))
        assert.is_not_nil(m.main_buf)
        assert.is_true(api.nvim_buf_is_valid(m.main_buf))
        
        m:close()
        
        assert.is_nil(m.main_win)
        assert.is_nil(m.main_buf)
    end)
    
    it("should handle item selection", function()
        local selected_index = nil
        local selected_item = nil
        
        local m = modal.list({
            title = "Test Selection",
            on_select = function(index, item)
                selected_index = index
                selected_item = item
            end
        })
        
        m:set_items({ "Item 1", "Item 2", "Item 3" })
        m:show()
        
        -- Simulate selection
        m.selected_index = 2
        m.opts.on_select(m.selected_index, m.items[m.selected_index])
        
        assert.equals(2, selected_index)
        assert.equals("Item 2", selected_item)
        
        m:close()
    end)
    
    it("should render content to buffers", function()
        local m = modal.list({
            title = "Test Render"
        })
        
        m:show()
        m:render_list({ "Line 1", "Line 2", "Line 3" })
        
        local lines = api.nvim_buf_get_lines(m.main_buf, 0, -1, false)
        assert.equals(3, #lines)
        assert.equals("Line 1", lines[1])
        assert.equals("Line 2", lines[2])
        assert.equals("Line 3", lines[3])
        
        m:close()
    end)
    
    it("should create preview window when enabled", function()
        local m = modal.select_list({
            title = "Test with Preview"
        })
        
        m:show()
        
        assert.is_not_nil(m.preview_win)
        assert.is_true(api.nvim_win_is_valid(m.preview_win))
        assert.is_true(api.nvim_buf_is_valid(m.preview_buf))
        
        m:render_preview({ "Preview content" })
        local lines = api.nvim_buf_get_lines(m.preview_buf, 0, -1, false)
        assert.equals("Preview content", lines[1])
        
        m:close()
    end)
    
    it("should set up navigation keymaps", function()
        local m = modal.list({
            title = "Test Keymaps"
        })
        
        m:show()
        
        local keymaps = api.nvim_buf_get_keymap(m.main_buf, "n")
        local keymap_table = {}
        for _, km in ipairs(keymaps) do
            keymap_table[km.lhs] = true
        end
        
        -- Check for expected keymaps (at least check some critical ones exist)
        assert.is_not_nil(m.main_buf)
        assert.is_true(api.nvim_buf_is_valid(m.main_buf))
        
        -- The keymaps should be set, but the exact format might vary
        -- So we'll just check that we have some keymaps set
        assert.is_true(#keymaps > 0, "Should have keymaps set")
        
        -- Check for specific keymaps more flexibly
        local has_q = false
        local has_j = false
        local has_k = false
        for _, km in ipairs(keymaps) do
            if km.lhs == "q" then has_q = true end
            if km.lhs == "j" then has_j = true end
            if km.lhs == "k" then has_k = true end
        end
        
        assert.is_true(has_q, "Should have 'q' keymap")
        assert.is_true(has_j, "Should have 'j' keymap")
        assert.is_true(has_k, "Should have 'k' keymap")
        
        m:close()
    end)
    
    it("should handle custom keymaps", function()
        local custom_called = false
        
        local m = modal.list({
            title = "Test Custom",
            keymaps = {
                x = function(modal_instance)
                    custom_called = true
                end
            }
        })
        
        m:show()
        
        local keymaps = api.nvim_buf_get_keymap(m.main_buf, "n")
        local has_custom = false
        for _, km in ipairs(keymaps) do
            if km.lhs == "x" then
                has_custom = true
                if km.callback then km.callback() end
                break
            end
        end
        
        assert.is_true(has_custom)
        assert.is_true(custom_called)
        
        m:close()
    end)
    
    it("should call close callback", function()
        local close_called = false
        
        local m = modal.list({
            title = "Test Close",
            on_close = function()
                close_called = true
            end
        })
        
        m:show()
        m:close()
        
        assert.is_true(close_called)
    end)
end)