-- Tests for obsidian-sync JSON file operations (update_todo_in_json, reverse sync)
describe("obsidian-sync json operations", function()
    local obsidian_sync
    local mock_todos_module
    local test_dir
    local test_bufnr

    before_each(function()
        -- Clear module cache
        package.loaded["doit.modules.obsidian-sync"] = nil
        package.loaded["doit.core"] = nil

        -- Create temp directory for mock JSON files
        test_dir = "/tmp/doit_obsidian_test_" .. os.time() .. "_" .. math.random(1000)
        vim.fn.mkdir(test_dir .. "/lists", "p")

        -- Create mock todos module
        mock_todos_module = {
            state = {
                todos = {},
                todo_lists = { active = "default" },
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
                    return { { name = "default" }, { name = "daily" } }
                end,
                create_list = function() return true end,
                load_list = function(name)
                    mock_todos_module.state.todo_lists.active = name
                    return true
                end,
                save_todos = function() end,
            }
        }

        -- Mock doit.core
        package.loaded["doit.core"] = {
            get_module = function(name)
                if name == "todos" then return mock_todos_module end
                return nil
            end,
            get_module_config = function(name)
                if name == "todos" then
                    return { lists_dir = test_dir .. "/lists" }
                end
                return nil
            end,
            register_module = function() end,
        }

        -- Mock obsidian
        package.loaded["obsidian"] = { get_client = function() return nil end }

        obsidian_sync = require("doit.modules.obsidian-sync")
        obsidian_sync.setup({ vault_path = "~/Recharge-Notes" })
        obsidian_sync.setup_functions()

        -- Create test buffer
        test_bufnr = vim.api.nvim_create_buf(false, true)
        local vault_path = vim.fn.expand("~/Recharge-Notes")
        vim.api.nvim_buf_set_name(test_bufnr, vault_path .. "/daily/2026-02-26.md")
    end)

    after_each(function()
        if test_bufnr and vim.api.nvim_buf_is_valid(test_bufnr) then
            vim.api.nvim_buf_delete(test_bufnr, { force = true })
        end
        os.execute("rm -rf " .. test_dir)
    end)

    -- helper: write a mock todo list JSON file
    local function write_mock_json(filename, data)
        local path = test_dir .. "/lists/" .. filename
        local f = io.open(path, "w")
        f:write(vim.fn.json_encode(data))
        f:close()
        return path
    end

    -- helper: read a JSON file back
    local function read_mock_json(filename)
        local path = test_dir .. "/lists/" .. filename
        local f = io.open(path, "r")
        if not f then return nil end
        local content = f:read("*all")
        f:close()
        local ok, data = pcall(vim.fn.json_decode, content)
        if ok then return data end
        return nil
    end

    describe("update_todo_in_json", function()
        it("should mark a todo done in the JSON file", function()
            write_mock_json("daily.json", {
                todos = {
                    { id = "abc123", text = "Buy milk", done = false, in_progress = false },
                    { id = "def456", text = "Write tests", done = false, in_progress = true },
                },
            })

            local result = obsidian_sync.update_todo_in_json(
                test_dir .. "/lists", "abc123", true
            )
            assert.is_true(result)

            local data = read_mock_json("daily.json")
            assert.is_true(data.todos[1].done)
            assert.is_false(data.todos[1].in_progress)
            -- second todo unchanged
            assert.is_false(data.todos[2].done)
        end)

        it("should mark a todo undone in the JSON file", function()
            write_mock_json("daily.json", {
                todos = {
                    { id = "abc123", text = "Buy milk", done = true, in_progress = false },
                },
            })

            local result = obsidian_sync.update_todo_in_json(
                test_dir .. "/lists", "abc123", false
            )
            assert.is_true(result)

            local data = read_mock_json("daily.json")
            assert.is_false(data.todos[1].done)
        end)

        it("should return false when todo is already in the requested state", function()
            write_mock_json("daily.json", {
                todos = {
                    { id = "abc123", text = "Already done", done = true, in_progress = false },
                },
            })

            local result = obsidian_sync.update_todo_in_json(
                test_dir .. "/lists", "abc123", true
            )
            assert.is_false(result)
        end)

        it("should return false when todo ID is not found", function()
            write_mock_json("daily.json", {
                todos = {
                    { id = "abc123", text = "Only todo", done = false, in_progress = false },
                },
            })

            local result = obsidian_sync.update_todo_in_json(
                test_dir .. "/lists", "nonexistent", true
            )
            assert.is_false(result)
        end)

        it("should search across multiple JSON files", function()
            write_mock_json("daily.json", {
                todos = {
                    { id = "daily_1", text = "Daily task", done = false, in_progress = false },
                },
            })
            write_mock_json("inbox.json", {
                todos = {
                    { id = "inbox_1", text = "Inbox task", done = false, in_progress = false },
                },
            })

            local result = obsidian_sync.update_todo_in_json(
                test_dir .. "/lists", "inbox_1", true
            )
            assert.is_true(result)

            -- daily unchanged
            local daily = read_mock_json("daily.json")
            assert.is_false(daily.todos[1].done)

            -- inbox updated
            local inbox = read_mock_json("inbox.json")
            assert.is_true(inbox.todos[1].done)
        end)

        it("should set in_progress=false when marking done", function()
            write_mock_json("daily.json", {
                todos = {
                    { id = "abc123", text = "Active task", done = false, in_progress = true },
                },
            })

            obsidian_sync.update_todo_in_json(
                test_dir .. "/lists", "abc123", true
            )

            local data = read_mock_json("daily.json")
            assert.is_true(data.todos[1].done)
            assert.is_false(data.todos[1].in_progress)
        end)

        it("should add _metadata.updated_at on change", function()
            write_mock_json("daily.json", {
                todos = {
                    { id = "abc123", text = "Task", done = false, in_progress = false },
                },
            })

            obsidian_sync.update_todo_in_json(
                test_dir .. "/lists", "abc123", true
            )

            local data = read_mock_json("daily.json")
            assert.is_not_nil(data._metadata)
            assert.is_not_nil(data._metadata.updated_at)
            assert.is_true(type(data._metadata.updated_at) == "number")
        end)

        it("should handle empty lists directory", function()
            -- no JSON files at all
            local result = obsidian_sync.update_todo_in_json(
                test_dir .. "/empty_dir", "abc123", true
            )
            assert.is_false(result)
        end)

        it("should handle malformed JSON gracefully", function()
            local path = test_dir .. "/lists/bad.json"
            local f = io.open(path, "w")
            f:write("not valid json {{{")
            f:close()

            local result = obsidian_sync.update_todo_in_json(
                test_dir .. "/lists", "abc123", true
            )
            assert.is_false(result)
        end)
    end)

    describe("sync_completions_from_buffer", function()
        it("should sync checked items from buffer to JSON", function()
            -- Write a todo list JSON with an unchecked todo
            write_mock_json("daily.json", {
                todos = {
                    { id = "todo_1", text = "Finish report", done = false, in_progress = false },
                },
            })

            -- Buffer has the checkbox checked
            vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
                "- [x] Finish report <!-- doit:todo_1 -->"
            })
            vim.api.nvim_set_current_buf(test_bufnr)

            local count = obsidian_sync.sync_completions_from_buffer(test_bufnr)
            assert.are.equal(1, count)

            local data = read_mock_json("daily.json")
            assert.is_true(data.todos[1].done)
        end)

        it("should sync unchecked items from buffer to JSON", function()
            write_mock_json("daily.json", {
                todos = {
                    { id = "todo_1", text = "Reopened task", done = true, in_progress = false },
                },
            })

            -- Buffer has checkbox unchecked (user unchecked it in obsidian)
            vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
                "- [ ] Reopened task <!-- doit:todo_1 -->"
            })
            vim.api.nvim_set_current_buf(test_bufnr)

            local count = obsidian_sync.sync_completions_from_buffer(test_bufnr)
            assert.are.equal(1, count)

            local data = read_mock_json("daily.json")
            assert.is_false(data.todos[1].done)
        end)

        it("should handle multiple todos in one buffer", function()
            write_mock_json("daily.json", {
                todos = {
                    { id = "t1", text = "Task 1", done = false, in_progress = false },
                    { id = "t2", text = "Task 2", done = false, in_progress = false },
                    { id = "t3", text = "Task 3", done = false, in_progress = false },
                },
            })

            vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
                "# Daily",
                "- [x] Task 1 <!-- doit:t1 -->",
                "- [ ] Task 2 <!-- doit:t2 -->",
                "- [X] Task 3 <!-- doit:t3 -->",
            })
            vim.api.nvim_set_current_buf(test_bufnr)

            local count = obsidian_sync.sync_completions_from_buffer(test_bufnr)
            assert.are.equal(2, count) -- t1 and t3 changed

            local data = read_mock_json("daily.json")
            assert.is_true(data.todos[1].done)
            assert.is_false(data.todos[2].done)
            assert.is_true(data.todos[3].done)
        end)

        it("should return 0 for buffer not in vault", function()
            -- Create a buffer that's NOT in the vault
            local other_buf = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_buf_set_name(other_buf, "/tmp/not_vault/note.md")
            vim.api.nvim_buf_set_lines(other_buf, 0, -1, false, {
                "- [x] Task <!-- doit:abc -->"
            })
            vim.api.nvim_set_current_buf(other_buf)

            local count = obsidian_sync.sync_completions_from_buffer(other_buf)
            assert.are.equal(0, count)

            vim.api.nvim_buf_delete(other_buf, { force = true })
        end)

        it("should return 0 when no changes needed", function()
            write_mock_json("daily.json", {
                todos = {
                    { id = "t1", text = "Already done", done = true, in_progress = false },
                },
            })

            vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
                "- [x] Already done <!-- doit:t1 -->"
            })
            vim.api.nvim_set_current_buf(test_bufnr)

            local count = obsidian_sync.sync_completions_from_buffer(test_bufnr)
            assert.are.equal(0, count)
        end)

        it("should ignore lines without doit markers", function()
            write_mock_json("daily.json", {
                todos = {
                    { id = "t1", text = "Tracked", done = false, in_progress = false },
                },
            })

            vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
                "- [x] Not tracked",
                "- [x] Tracked <!-- doit:t1 -->",
                "Some random text",
            })
            vim.api.nvim_set_current_buf(test_bufnr)

            local count = obsidian_sync.sync_completions_from_buffer(test_bufnr)
            assert.are.equal(1, count)
        end)
    end)

    describe("resolve_daily_note_path", function()
        it("should resolve using default template", function()
            local path = obsidian_sync.resolve_daily_note_path(os.time())
            assert.is_string(path)
            assert.truthy(path:match("daily/"))
            assert.truthy(path:match("%d%d%d%d%-%d%d%-%d%d%.md"))
        end)

        it("should use custom resolve function", function()
            obsidian_sync.config.daily_note.resolve = function(vault, time)
                return vault .. "/custom/" .. os.date("%Y-%m-%d", time) .. ".md"
            end

            local path = obsidian_sync.resolve_daily_note_path(os.time())
            assert.truthy(path:match("custom/"))
        end)
    end)

    describe("resolve_daily_path with lookback", function()
        it("should return today if file exists", function()
            local today_path = obsidian_sync.resolve_daily_note_path(os.time())
            -- Create the file so it's found
            local dir = today_path:match("(.*/)")
            vim.fn.mkdir(dir, "p")
            local f = io.open(today_path, "w")
            f:write("# Today\n")
            f:close()

            local result = obsidian_sync.resolve_daily_path(os.time())
            assert.are.equal(today_path, result)

            os.remove(today_path)
        end)

        it("should look back when today does not exist", function()
            -- Don't create today's file; create yesterday's
            local yesterday = os.time() - 86400
            local yesterday_path = obsidian_sync.resolve_daily_note_path(yesterday)
            local dir = yesterday_path:match("(.*/)")
            vim.fn.mkdir(dir, "p")
            local f = io.open(yesterday_path, "w")
            f:write("# Yesterday\n")
            f:close()

            local result = obsidian_sync.resolve_daily_path(os.time())
            assert.are.equal(yesterday_path, result)

            os.remove(yesterday_path)
        end)

        it("should return today path when no files found within lookback", function()
            local today_path = obsidian_sync.resolve_daily_note_path(os.time())
            local result = obsidian_sync.resolve_daily_path(os.time())
            assert.are.equal(today_path, result)
        end)
    end)
end)
