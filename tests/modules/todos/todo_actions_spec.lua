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
            sort_todos = function() end,
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
            -- Mirror main_window.build_render_rows layout so cursor mapping tests are faithful:
            -- blank top; named priority headers for the pending block (blank before each
            -- except the first); blank between in-progress groups; always-shown Notes
            -- section (blank + "Notes" + note rows or "(no notes)") before the done block;
            -- blank+divider+blank before completed.
            local function prio(todo)
                local p = todo.priorities
                if type(p) == "string" and p ~= "" then return p end
                return nil
            end
            local HEADER = { critical = "Critical", urgent = "Urgent", important = "Important", default = "Default" }
            local notes = (mock_state.todo_lists and mock_state.todo_lists.notes) or {}
            local lines = { "" }  -- blank line at top
            local prev_group = nil
            local done_started = false
            local notes_emitted = false
            local function emit_notes()
                notes_emitted = true
                table.insert(lines, "")
                table.insert(lines, "Notes")
                if #notes == 0 then
                    table.insert(lines, "  (no notes)")
                else
                    for _, note in ipairs(notes) do
                        local title = note.title
                        if not title or title == "" then title = "(untitled)" end
                        table.insert(lines, "  • " .. title)
                    end
                end
            end
            for _, todo in ipairs(mock_state.todos) do
                if todo.done then
                    if not done_started then
                        done_started = true
                        if not notes_emitted then emit_notes() end
                        table.insert(lines, "")
                        table.insert(lines, "────────")
                        table.insert(lines, "")
                    end
                else
                    local section = (todo.in_progress and "ip" or "pd")
                    local group = section .. ":" .. (prio(todo) or "default")
                    if group ~= prev_group then
                        if section == "pd" then
                            if prev_group then table.insert(lines, "") end
                            table.insert(lines, HEADER[prio(todo) or "default"] or "Default")
                        elseif prev_group then
                            table.insert(lines, "")
                        end
                    end
                    prev_group = group
                end
                local text_lines = vim.split(todo.text, "\n", { plain = true })
                for i, line in ipairs(text_lines) do
                    if i == 1 then
                        table.insert(lines, "  ○ " .. line)
                    else
                        table.insert(lines, "    " .. line)
                    end
                end
            end
            if not notes_emitted then emit_notes() end
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
            assert.are.equal(7, #lines)  -- blank, Default header, todo, blank, Notes, (no notes), blank
            assert.truthy(lines[3]:match("Single line todo"))
        end)

        it("should handle two-line todos", function()
            mock_state.todos = {
                { id = "1", text = "First line\nSecond line", done = false, in_progress = false }
            }

            local lines = vim.api.nvim_buf_get_lines(mock_buf_id, 0, -1, false)
            assert.are.equal(8, #lines)  -- blank, Default, line1, line2, blank, Notes, (no notes), blank
            assert.truthy(lines[3]:match("First line"))
            assert.truthy(lines[4]:match("Second line"))
        end)

        it("should handle multiple multiline todos", function()
            mock_state.todos = {
                { id = "1", text = "Todo 1 line 1\nTodo 1 line 2", done = false, in_progress = false },
                { id = "2", text = "Todo 2 single", done = false, in_progress = false },
                { id = "3", text = "Todo 3 line 1\nTodo 3 line 2\nTodo 3 line 3", done = false, in_progress = false }
            }

            local lines = vim.api.nvim_buf_get_lines(mock_buf_id, 0, -1, false)
            -- blank(1) + Default header(1) + todo1(2) + todo2(1) + todo3(3) + notes section(3) + blank(1) = 12
            assert.are.equal(12, #lines)
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

            -- The first todo's bullet is line 3 (line 2 is the Default priority header)
            local lines = vim.api.nvim_buf_get_lines(mock_buf_id, 0, -1, false)
            assert.truthy(lines[3]:match("○"))  -- Has bullet
        end)

        it("should find bullet line from continuation line", function()
            -- Mock cursor on line 3 (second line of first todo, a continuation)
            vim.api.nvim_win_get_cursor = function() return { 3, 0 } end

            local lines = vim.api.nvim_buf_get_lines(mock_buf_id, 0, -1, false)
            assert.falsy(lines[4]:match("○"))  -- No bullet on continuation
            assert.truthy(lines[3]:match("○"))  -- Bullet is on line 3
        end)
    end)

    describe("delete_todo", function()
        it("should delete single-line todo", function()
            mock_state.todos = {
                { id = "1", text = "Todo to delete", done = false, in_progress = false }
            }

            vim.api.nvim_win_get_cursor = function() return { 3, 0 } end

            todo_actions.delete_todo(mock_win_id, function() end)

            assert.are.equal(0, #mock_state.todos)
            assert.are.equal(1, #mock_state.deleted_todos)
        end)

        it("should delete multiline todo from bullet line", function()
            mock_state.todos = {
                { id = "1", text = "First line\nSecond line", done = false, in_progress = false }
            }

            -- Cursor on bullet line (line 3, after the Default header)
            vim.api.nvim_win_get_cursor = function() return { 3, 0 } end

            todo_actions.delete_todo(mock_win_id, function() end)

            assert.are.equal(0, #mock_state.todos)
            assert.are.equal(1, #mock_state.deleted_todos)
        end)

        it("should delete multiline todo from continuation line", function()
            mock_state.todos = {
                { id = "1", text = "First line\nSecond line", done = false, in_progress = false }
            }

            -- Cursor on continuation line (line 4, after the Default header)
            vim.api.nvim_win_get_cursor = function() return { 4, 0 } end

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

            vim.api.nvim_win_get_cursor = function() return { 3, 0 } end

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

            -- Cursor on continuation line (line 4, after the Default header)
            vim.api.nvim_win_get_cursor = function() return { 4, 0 } end

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

            -- Line 3 (after top blank + Default header) is the first todo
            -- This is tested indirectly through delete/toggle operations
            vim.api.nvim_win_get_cursor = function() return { 3, 0 } end

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

            -- Line 5 maps to todo index 2 (lines: blank, Default, todo1-l1, todo1-l2, todo2)
            vim.api.nvim_win_get_cursor = function() return { 5, 0 } end

            todo_actions.delete_todo(mock_win_id, function() end)

            -- Second todo should be deleted
            assert.are.equal(1, #mock_state.todos)
            assert.are.equal("First\nline two", mock_state.todos[1].text)
        end)

        it("should account for priority-group separators and the done divider", function()
            -- layout (must match build_render_rows):
            --   line1 blank
            --   line2 "Critical" header, line3 Crit
            --   line4 blank, line5 "Important" header, line6 Imp
            --   line7 blank, line8 "Notes", line9 (no notes)
            --   line10 blank, line11 divider, line12 blank
            --   line13 Old (done)
            mock_state.todos = {
                { id = "1", text = "Crit", done = false, in_progress = false, priorities = "critical" },
                { id = "2", text = "Imp", done = false, in_progress = false, priorities = "important" },
                { id = "3", text = "Old", done = true, in_progress = false },
            }

            vim.api.nvim_win_get_cursor = function() return { 6, 0 } end
            todo_actions.delete_todo(mock_win_id, function() end)
            assert.are.equal(2, #mock_state.todos)
            assert.is_nil((function()
                for _, t in ipairs(mock_state.todos) do
                    if t.text == "Imp" then return t end
                end
            end)())
        end)

        it("should map the cursor to a done todo past the divider", function()
            mock_state.todos = {
                { id = "1", text = "Crit", done = false, in_progress = false, priorities = "critical" },
                { id = "2", text = "Imp", done = false, in_progress = false, priorities = "important" },
                { id = "3", text = "Old", done = true, in_progress = false },
            }

            vim.api.nvim_win_get_cursor = function() return { 13, 0 } end
            todo_actions.delete_todo(mock_win_id, function() end)
            assert.are.equal(2, #mock_state.todos)
            assert.is_nil((function()
                for _, t in ipairs(mock_state.todos) do
                    if t.text == "Old" then return t end
                end
            end)())
        end)
    end)

    describe("get_note_at_cursor", function()
        -- layout: 1 blank, 2 Default, 3 "○ Task", 4 blank, 5 "Notes", 6 "• My note", 7 blank
        before_each(function()
            mock_state.todos = {
                { id = "1", text = "Task", done = false, in_progress = false },
            }
            mock_state.todo_lists = { notes = { { id = "n1", title = "My note", body = "b" } } }
        end)

        it("returns the note when the cursor is on a note row", function()
            vim.api.nvim_win_get_cursor = function() return { 6, 0 } end
            local note = todo_actions.get_note_at_cursor(mock_win_id)
            assert.is_not_nil(note)
            assert.are.equal("n1", note.id)
        end)

        it("returns nil when the cursor is on a todo row", function()
            vim.api.nvim_win_get_cursor = function() return { 3, 0 } end
            assert.is_nil(todo_actions.get_note_at_cursor(mock_win_id))
        end)

        it("returns nil when the cursor is on the Notes header", function()
            vim.api.nvim_win_get_cursor = function() return { 5, 0 } end
            assert.is_nil(todo_actions.get_note_at_cursor(mock_win_id))
        end)
    end)
end)
