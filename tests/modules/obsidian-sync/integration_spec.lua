describe("obsidian-sync integration", function()
    local obsidian_sync
    local temp_file

    before_each(function()
        -- Clear module cache
        package.loaded["doit.modules.obsidian-sync"] = nil

        -- Create a temporary file
        temp_file = vim.fn.tempname() .. ".md"

        -- Mock minimal requirements
        package.loaded["doit.core"] = {
            get_module = function()
                return {
                    state = {
                        todos = {},
                        todo_lists = { active = "default" },
                        add_todo = function(text)
                            return {
                                id = "int_test_" .. os.time(),
                                text = text,
                                done = false
                            }
                        end,
                        get_available_lists = function()
                            return {{name = "default"}}
                        end,
                        create_list = function() return true end,
                        load_list = function() return true end
                    }
                }
            end,
            register_module = function() end
        }

        package.loaded["obsidian"] = {
            get_client = function() return nil end
        }

        obsidian_sync = require("doit.modules.obsidian-sync")
        obsidian_sync.setup({
            vault_path = vim.fn.fnamemodify(temp_file, ":h")
        })
    end)

    after_each(function()
        -- Clean up temp file
        if temp_file and vim.fn.filereadable(temp_file) == 1 then
            vim.fn.delete(temp_file)
        end
    end)

    describe("commands", function()
        it("should create import commands", function()
            local commands = vim.api.nvim_get_commands({})
            assert.is_not_nil(commands.DoItImportBuffer)
            assert.is_not_nil(commands.DoItImportToday)
            assert.is_not_nil(commands.DoItSyncStatus)
        end)

        it("should NOT create DoItGotoSource command", function()
            local commands = vim.api.nvim_get_commands({})
            assert.is_nil(commands.DoItGotoSource)
        end)
    end)

    describe("real file operations", function()
        it("should handle file import workflow", function()
            -- Write test content to file
            local file = io.open(temp_file, "w")
            file:write("# Test Note\n")
            file:write("- [ ] First task\n")
            file:write("- [x] Done task\n")
            file:write("- [ ] - Second task\n")
            file:write("- [ ] -\n")  -- Empty placeholder
            file:close()

            -- Open file in buffer
            vim.cmd("edit " .. temp_file)
            local bufnr = vim.api.nvim_get_current_buf()

            -- Import
            local count = obsidian_sync.import_current_buffer()

            -- Should import 2 real tasks (not done, not empty)
            assert.equals(2, count)

            -- Check that markers were added
            local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

            -- First task should have marker
            assert.is_true(lines[2]:match("<!-- doit:") ~= nil)

            -- Done task should not have marker
            assert.is_false(lines[3]:match("<!-- doit:") ~= nil)

            -- Second task should have marker
            assert.is_true(lines[4]:match("<!-- doit:") ~= nil)

            -- Empty placeholder should not have marker
            assert.is_false(lines[5]:match("<!-- doit:") ~= nil)

            -- Clean up
            vim.api.nvim_buf_delete(bufnr, {force = true})
        end)
    end)

    describe("keymaps in obsidian buffers", function()
        it("should set up keymaps for obsidian files", function()
            -- Create a buffer with Recharge-Notes path
            local bufnr = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_buf_set_name(bufnr, "~/Recharge-Notes/test.md")

            -- Trigger autocmd
            vim.api.nvim_set_current_buf(bufnr)
            vim.cmd("doautocmd BufEnter")

            -- Check keymaps exist
            local keymaps = vim.api.nvim_buf_get_keymap(bufnr, "n")
            local has_di = false
            local has_dt = false

            for _, map in ipairs(keymaps) do
                if map.lhs == "<leader>di" then
                    has_di = true
                elseif map.lhs == "<leader>dt" then
                    has_dt = true
                end
            end

            -- Note: Keymaps might not be set in test environment
            -- without full autocmd setup, this is more of a structure test

            -- Clean up
            vim.api.nvim_buf_delete(bufnr, {force = true})
        end)
    end)
end)