-- Tests for todo_actions (multiline support and bullet-line indexing)
describe("todo_actions", function()
    local todo_actions
    local mock_state
    local mock_win_id
    local mock_buf_id

    before_each(function()
        -- Clear module cache
        package.loaded["doit.ui.todo_actions"] = nil
        package.loaded["doit.config"] = nil
        package.loaded["doit.calendar"] = nil
        package.loaded["doit.core.ui.multiline_input"] = nil

        -- Mock vim API
        mock_buf_id = 1
        mock_win_id = 100

        -- Mock config
        package.loaded["doit.config"] = {
            options = {
                formatting = {
                    pending = { icon = "○" },
                    in_progress = { icon = "◐" },
                    done = { icon = "✓" }
                },
                keymaps = {
                    toggle_priority = "p"
                }
            }
        }

        -- Mock calendar
        package.loaded["doit.calendar"] = {}

        -- Mock multiline input
        package.loaded["doit.core.ui.multiline_input"] = {
            create = function(opts)
                return {
                    buf = mock_buf_id,
                    win = mock_win_id,
                    close = function() end
                }
            end
        }

        -- Create mock state
        mock_state = {
            todos = {},
            active_filter = nil,
            active_category = nil,
            deleted_todos = {},
            MAX_UNDO_HISTORY = 50,
            delete_todo = function(index)
                local todo = mock_state.todos[index]
                if todo then
                    todo.delete_time = os.time()
                    table.insert(mock_state.deleted_todos, 1, todo)
                    table.remove(mock_state.todos, index)
                end
            end,
            toggle_todo = function(index)
                if mock_state.todos[index] then
                    local todo = mock_state.todos[index]
                    if not todo.in_progress and not todo.done then
                        todo.in_progress = true
                        todo.done = false
                    elseif todo.in_progress and not todo.done then
                        todo.in_progress = false
                        todo.done = true
                    else
                        todo.in_progress = false
                        todo.done = false
                    end
                end
            end,
            save_to_disk = function() end,
            load_from_disk = function() end
        }

        -- Mock vim API functions
        _G.vim = _G.vim or {}
        vim.api = vim.api or {}
        vim.fn = vim.fn or {}
        vim.loop = vim.loop or {}
        vim.ui = vim.ui or {}

        vim.api.nvim_win_is_valid = function(win) return win == mock_win_id end
        vim.api.nvim_buf_is_valid = function(buf) return buf == mock_buf_id end
        vim.api.nvim_win_get_buf = function() return mock_buf_id end
        vim.api.nvim_buf_line_count = function(buf)
            local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
            return #lines
        end
        vim.api.nvim_win_set_cursor = function(win, pos) end  -- Mock cursor set
        vim.api.nvim_buf_get_lines = function(buf, start, end_, strict)
            -- Return mock buffer lines based on current state
            local lines = { "" }  -- blank line at top
            for _, todo in ipairs(mock_state.todos) do
                local text_lines = vim.split(todo.text, "\n", { plain = true })
                for i, line in ipairs(text_lines) do
                    if i == 1 then
                        table.insert(lines, "  ○ " .. line)
                    else
                        table.insert(lines, "    " .. line)
                    end
                end
            end
            table.insert(lines, "")  -- blank line at bottom

            -- Handle slicing
            if start >= 0 and end_ >= 0 then
                local result = {}
                for i = start + 1, math.min(end_, #lines) do
                    table.insert(result, lines[i])
                end
                return result
            end
            return lines
        end

        vim.split = function(text, sep, opts)
            local result = {}
            local current = ""
            for i = 1, #text do
                local char = text:sub(i, i)
                if char == sep then
                    table.insert(result, current)
                    current = ""
                else
                    current = current .. char
                end
            end
            table.insert(result, current)
            return result
        end

        vim.notify = function() end
        vim.schedule = function(fn) fn() end

        -- Mock core module loading
        package.loaded["doit.core"] = {
            get_module = function(name)
                if name == "todos" then
                    return {
                        state = mock_state
                    }
                end
                return nil
            end
        }

        -- Load todo_actions
        todo_actions = require("doit.ui.todo_actions")
    end)

    describe("multiline todo support", function()
        it("should handle single-line todos", function()
            mock_state.todos = {
                { id = "1", text = "Single line todo", done = false, in_progress = false }
            }

            -- Line 2 should map to index 1 (line 1 is blank)
            local lines = vim.api.nvim_buf_get_lines(mock_buf_id, 0, -1, false)
            assert.are.equal(3, #lines)  -- blank, todo, blank
            assert.truthy(lines[2]:match("Single line todo"))
        end)

        it("should handle two-line todos", function()
            mock_state.todos = {
                { id = "1", text = "First line\nSecond line", done = false, in_progress = false }
            }

            local lines = vim.api.nvim_buf_get_lines(mock_buf_id, 0, -1, false)
            assert.are.equal(4, #lines)  -- blank, line1, line2, blank
            assert.truthy(lines[2]:match("First line"))
            assert.truthy(lines[3]:match("Second line"))
        end)

        it("should handle multiple multiline todos", function()
            mock_state.todos = {
                { id = "1", text = "Todo 1 line 1\nTodo 1 line 2", done = false, in_progress = false },
                { id = "2", text = "Todo 2 single", done = false, in_progress = false },
                { id = "3", text = "Todo 3 line 1\nTodo 3 line 2\nTodo 3 line 3", done = false, in_progress = false }
            }

            local lines = vim.api.nvim_buf_get_lines(mock_buf_id, 0, -1, false)
            -- blank(1) + todo1(2) + todo2(1) + todo3(3) + blank(1) = 8
            assert.are.equal(8, #lines)
        end)
    end)

    describe("bullet-line indexing", function()
        before_each(function()
            mock_state.todos = {
                { id = "1", text = "First todo\nsecond line", done = false, in_progress = false },
                { id = "2", text = "Second todo", done = false, in_progress = false }
            }
        end)

        it("should find bullet line from first line of todo", function()
            -- Mock cursor on line 2 (first line of first todo)
            vim.api.nvim_win_get_cursor = function() return { 2, 0 } end

            -- The bullet line for line 2 should be line 2 itself
            local lines = vim.api.nvim_buf_get_lines(mock_buf_id, 0, -1, false)
            assert.truthy(lines[2]:match("○"))  -- Has bullet
        end)

        it("should find bullet line from continuation line", function()
            -- Mock cursor on line 3 (second line of first todo, a continuation)
            vim.api.nvim_win_get_cursor = function() return { 3, 0 } end

            local lines = vim.api.nvim_buf_get_lines(mock_buf_id, 0, -1, false)
            assert.falsy(lines[3]:match("○"))  -- No bullet on continuation
            assert.truthy(lines[2]:match("○"))  -- Bullet is on line 2
        end)
    end)

    describe("delete_todo", function()
        it("should delete single-line todo", function()
            mock_state.todos = {
                { id = "1", text = "Todo to delete", done = false, in_progress = false }
            }

            vim.api.nvim_win_get_cursor = function() return { 2, 0 } end

            todo_actions.delete_todo(mock_win_id, function() end)

            assert.are.equal(0, #mock_state.todos)
            assert.are.equal(1, #mock_state.deleted_todos)
        end)

        it("should delete multiline todo from bullet line", function()
            mock_state.todos = {
                { id = "1", text = "First line\nSecond line", done = false, in_progress = false }
            }

            -- Cursor on bullet line (line 2)
            vim.api.nvim_win_get_cursor = function() return { 2, 0 } end

            todo_actions.delete_todo(mock_win_id, function() end)

            assert.are.equal(0, #mock_state.todos)
            assert.are.equal(1, #mock_state.deleted_todos)
        end)

        it("should delete multiline todo from continuation line", function()
            mock_state.todos = {
                { id = "1", text = "First line\nSecond line", done = false, in_progress = false }
            }

            -- Cursor on continuation line (line 3)
            vim.api.nvim_win_get_cursor = function() return { 3, 0 } end

            todo_actions.delete_todo(mock_win_id, function() end)

            assert.are.equal(0, #mock_state.todos)
            assert.are.equal(1, #mock_state.deleted_todos)
        end)
    end)

    describe("toggle_todo", function()
        it("should toggle single-line todo", function()
            mock_state.todos = {
                { id = "1", text = "Todo", done = false, in_progress = false }
            }
            mock_state.save_to_disk = function() end

            vim.api.nvim_win_get_cursor = function() return { 2, 0 } end

            todo_actions.toggle_todo(mock_win_id, function() end)

            -- Should toggle to in_progress
            assert.is_true(mock_state.todos[1].in_progress)
            assert.is_false(mock_state.todos[1].done)
        end)

        it("should toggle multiline todo from continuation line", function()
            mock_state.todos = {
                { id = "1", text = "First line\nSecond line", done = false, in_progress = false }
            }
            mock_state.save_to_disk = function() end

            -- Cursor on continuation line (line 3)
            vim.api.nvim_win_get_cursor = function() return { 3, 0 } end

            todo_actions.toggle_todo(mock_win_id, function() end)

            -- Should toggle to in_progress
            assert.is_true(mock_state.todos[1].in_progress)
            assert.is_false(mock_state.todos[1].done)
        end)
    end)

    describe("get_real_todo_index", function()
        it("should return correct index for first todo", function()
            mock_state.todos = {
                { id = "1", text = "First", done = false, in_progress = false },
                { id = "2", text = "Second", done = false, in_progress = false }
            }

            -- Line 2 (after blank line) should be index 1
            -- This is tested indirectly through delete/toggle operations
            vim.api.nvim_win_get_cursor = function() return { 2, 0 } end

            todo_actions.delete_todo(mock_win_id, function() end)

            -- First todo should be deleted
            assert.are.equal(1, #mock_state.todos)
            assert.are.equal("Second", mock_state.todos[1].text)
        end)

        it("should return correct index for multiline todo", function()
            mock_state.todos = {
                { id = "1", text = "First\nline two", done = false, in_progress = false },
                { id = "2", text = "Second", done = false, in_progress = false }
            }

            -- Line 4 should map to todo index 2 (lines: blank, todo1-line1, todo1-line2, todo2)
            vim.api.nvim_win_get_cursor = function() return { 4, 0 } end

            todo_actions.delete_todo(mock_win_id, function() end)

            -- Second todo should be deleted
            assert.are.equal(1, #mock_state.todos)
            assert.are.equal("First\nline two", mock_state.todos[1].text)
        end)
    end)
end)
