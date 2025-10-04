describe("obsidian-sync module", function()
    local obsidian_sync
    local mock_todos_module
    local test_bufnr

    before_each(function()
        -- Clear module cache
        package.loaded["doit.modules.obsidian-sync"] = nil
        package.loaded["doit.core"] = nil

        -- Create mock todos module
        mock_todos_module = {
            state = {
                todos = {},
                todo_lists = {
                    active = "default"
                },
                add_todo = function(text)
                    local todo = {
                        id = "test_" .. #mock_todos_module.state.todos + 1,
                        text = text,
                        done = false,
                        in_progress = false
                    }
                    table.insert(mock_todos_module.state.todos, todo)
                    return todo
                end,
                get_available_lists = function()
                    return {
                        {name = "default"},
                        {name = "daily"}
                    }
                end,
                create_list = function(name)
                    return true
                end,
                load_list = function(name)
                    mock_todos_module.state.todo_lists.active = name
                    return true
                end
            }
        }

        -- Mock doit.core
        package.loaded["doit.core"] = {
            get_module = function(name)
                if name == "todos" then
                    return mock_todos_module
                end
                return nil
            end,
            register_module = function() end
        }

        -- Mock obsidian (not available in tests)
        package.loaded["obsidian"] = {
            get_client = function()
                return nil
            end
        }

        -- Load the module
        obsidian_sync = require("doit.modules.obsidian-sync")

        -- Create a test buffer
        test_bufnr = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_name(test_bufnr, "/Users/bryan/Recharge-Notes/daily/2025-10-04.md")
    end)

    after_each(function()
        -- Clean up test buffer
        if test_bufnr and vim.api.nvim_buf_is_valid(test_bufnr) then
            vim.api.nvim_buf_delete(test_bufnr, {force = true})
        end
    end)

    describe("module loading", function()
        it("should load without errors", function()
            assert.is_not_nil(obsidian_sync)
            assert.equals("1.0.0", obsidian_sync.version)
            assert.equals("obsidian-sync", obsidian_sync.metadata.name)
        end)

        it("should have required metadata", function()
            assert.is_not_nil(obsidian_sync.metadata)
            assert.equals("obsidian-sync", obsidian_sync.metadata.name)
            assert.is_table(obsidian_sync.metadata.dependencies)
            assert.is_true(vim.tbl_contains(obsidian_sync.metadata.dependencies, "todos"))
        end)
    end)

    describe("setup", function()
        it("should setup with default config", function()
            local result = obsidian_sync.setup()
            assert.is_not_nil(result)
            assert.equals("~/Recharge-Notes", obsidian_sync.config.vault_path)
            assert.equals("obsidian", obsidian_sync.config.default_list)
        end)

        it("should accept custom config", function()
            obsidian_sync.setup({
                vault_path = "~/CustomVault",
                default_list = "custom",
                auto_import_on_open = true
            })
            assert.equals("~/CustomVault", obsidian_sync.config.vault_path)
            assert.equals("custom", obsidian_sync.config.default_list)
            assert.is_true(obsidian_sync.config.auto_import_on_open)
        end)
    end)

    describe("import_current_buffer", function()
        before_each(function()
            obsidian_sync.setup({
                vault_path = "~/Recharge-Notes"
            })
            obsidian_sync.setup_functions()
        end)

        it("should import unchecked todos", function()
            -- Set buffer content with checkboxes
            vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
                "# Daily Notes",
                "",
                "- [ ] Task 1",
                "- [x] Completed task",
                "- [ ] Task 2"
            })

            -- Make buffer current
            vim.api.nvim_set_current_buf(test_bufnr)

            local count = obsidian_sync.import_current_buffer()
            assert.equals(2, count) -- Should import 2 unchecked items
            assert.equals(2, #mock_todos_module.state.todos)
            assert.equals("Task 1", mock_todos_module.state.todos[1].text)
            assert.equals("Task 2", mock_todos_module.state.todos[2].text)
        end)

        it("should handle format '- [ ] - text'", function()
            vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
                "- [ ] - Create module",
                "- [ ] - Test module"
            })

            vim.api.nvim_set_current_buf(test_bufnr)
            local count = obsidian_sync.import_current_buffer()

            assert.equals(2, count)
            -- Should strip the leading dash
            assert.equals("Create module", mock_todos_module.state.todos[1].text)
            assert.equals("Test module", mock_todos_module.state.todos[2].text)
        end)

        it("should skip empty placeholders", function()
            vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
                "- [ ] Real task",
                "- [ ] -",  -- Empty placeholder
                "- [ ] ",   -- Empty
                "- [ ] Another task"
            })

            vim.api.nvim_set_current_buf(test_bufnr)
            local count = obsidian_sync.import_current_buffer()

            assert.equals(2, count) -- Only real tasks
            assert.equals("Real task", mock_todos_module.state.todos[1].text)
            assert.equals("Another task", mock_todos_module.state.todos[2].text)
        end)

        it("should add tracking markers", function()
            vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
                "- [ ] Task with marker"
            })

            vim.api.nvim_set_current_buf(test_bufnr)
            obsidian_sync.import_current_buffer()

            local lines = vim.api.nvim_buf_get_lines(test_bufnr, 0, -1, false)
            assert.is_true(lines[1]:match("doit:test_1") ~= nil)
        end)

        it("should not re-import already imported items", function()
            vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
                "- [ ] Already imported <!-- doit:existing_id -->"
            })

            vim.api.nvim_set_current_buf(test_bufnr)
            local count = obsidian_sync.import_current_buffer()

            assert.equals(0, count)
            assert.equals(0, #mock_todos_module.state.todos)
        end)
    end)

    describe("determine_list", function()
        before_each(function()
            obsidian_sync.setup({
                list_mapping = {
                    daily = "daily",
                    inbox = "inbox",
                    projects = "projects"
                },
                default_list = "general"
            })
            obsidian_sync.setup_functions()
        end)

        it("should map daily folder to daily list", function()
            local list = obsidian_sync.determine_list(
                "/Users/bryan/Recharge-Notes/daily/2025-10-04.md",
                "Some task"
            )
            assert.equals("daily", list)
        end)

        it("should map inbox folder to inbox list", function()
            local list = obsidian_sync.determine_list(
                "/Users/bryan/Recharge-Notes/inbox/ideas.md",
                "New idea"
            )
            assert.equals("inbox", list)
        end)

        it("should use tag if present", function()
            local list = obsidian_sync.determine_list(
                "/Users/bryan/Recharge-Notes/random.md",
                "Task #projects for work"
            )
            assert.equals("projects", list)
        end)

        it("should use default list if no match", function()
            local list = obsidian_sync.determine_list(
                "/Users/bryan/Recharge-Notes/other.md",
                "Random task"
            )
            assert.equals("general", list)
        end)
    end)

    describe("sync_completion", function()
        before_each(function()
            obsidian_sync.setup()
            obsidian_sync.setup_functions()

            -- Set up a test buffer with content
            vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
                "- [ ] Test task"
            })

            -- Add a reference
            obsidian_sync.refs["test_1"] = {
                bufnr = test_bufnr,
                lnum = 1,
                file = "/Users/bryan/Recharge-Notes/daily/test.md"
            }
        end)

        it("should mark checkbox complete when todo.done = true", function()
            local todo = {
                done = true,
                in_progress = false
            }

            obsidian_sync.sync_completion("test_1", todo)

            local lines = vim.api.nvim_buf_get_lines(test_bufnr, 0, -1, false)
            assert.equals("- [x] Test task", lines[1])
        end)

        it("should NOT mark complete when in_progress", function()
            local todo = {
                done = false,
                in_progress = true
            }

            obsidian_sync.sync_completion("test_1", todo)

            local lines = vim.api.nvim_buf_get_lines(test_bufnr, 0, -1, false)
            assert.equals("- [ ] Test task", lines[1])
        end)

        it("should keep unchecked when not started", function()
            local todo = {
                done = false,
                in_progress = false
            }

            obsidian_sync.sync_completion("test_1", todo)

            local lines = vim.api.nvim_buf_get_lines(test_bufnr, 0, -1, false)
            assert.equals("- [ ] Test task", lines[1])
        end)

        it("should handle invalid references gracefully", function()
            local result = obsidian_sync.sync_completion("invalid_id", {done = true})
            assert.is_false(result)
        end)
    end)

    describe("reference tracking", function()
        before_each(function()
            obsidian_sync.setup()
            obsidian_sync.setup_functions()
        end)

        it("should track references during import", function()
            vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
                "- [ ] Track this"
            })

            vim.api.nvim_set_current_buf(test_bufnr)
            obsidian_sync.import_current_buffer()

            assert.is_not_nil(obsidian_sync.refs["test_1"])
            assert.equals(test_bufnr, obsidian_sync.refs["test_1"].bufnr)
            assert.equals(1, obsidian_sync.refs["test_1"].lnum)
        end)

        it("should refresh existing references", function()
            vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
                "- [ ] Existing <!-- doit:old_id -->"
            })

            obsidian_sync.refresh_buffer_refs(test_bufnr)

            assert.is_not_nil(obsidian_sync.refs["old_id"])
            assert.equals(test_bufnr, obsidian_sync.refs["old_id"].bufnr)
        end)
    end)

    describe("list management", function()
        before_each(function()
            obsidian_sync.setup()
            obsidian_sync.setup_functions()
        end)

        it("should create list if it doesn't exist", function()
            -- Mock that daily list doesn't exist
            mock_todos_module.state.get_available_lists = function()
                return {{name = "default"}}
            end

            local created = false
            mock_todos_module.state.create_list = function(name)
                created = (name == "daily")
                return true
            end

            vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
                "- [ ] Daily task"
            })

            vim.api.nvim_set_current_buf(test_bufnr)
            obsidian_sync.import_current_buffer()

            assert.is_true(created)
        end)

        it("should switch lists during import", function()
            local switched = false
            mock_todos_module.state.load_list = function(name)
                switched = (name == "daily")
                mock_todos_module.state.todo_lists.active = name
                return true
            end

            vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
                "- [ ] Daily task"
            })

            vim.api.nvim_set_current_buf(test_bufnr)
            obsidian_sync.import_current_buffer()

            assert.is_true(switched)
        end)
    end)
end)