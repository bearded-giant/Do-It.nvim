-- Tests for todos due_dates module
local due_dates_module = require("doit.modules.todos.state.due_dates")

describe("todos due_dates", function()
    local due_dates
    local state

    before_each(function()
        state = {
            todos = {
                { text = "Todo 1", done = false },
                { text = "Todo 2", done = false },
            },
            save_todos = function() end,
        }
        due_dates = due_dates_module.setup(state)
    end)

    describe("set_due_date", function()
        it("should set a valid due date", function()
            local ok, msg = due_dates.set_due_date(1, "2026-03-15")
            assert.is_true(ok)
            assert.are.equal("2026-03-15", state.todos[1].due_date)
        end)

        it("should reject invalid format", function()
            local ok, err = due_dates.set_due_date(1, "03/15/2026")
            assert.is_false(ok)
            assert.truthy(err:find("Invalid date format"))
        end)

        it("should reject invalid month", function()
            local ok, err = due_dates.set_due_date(1, "2026-13-01")
            assert.is_false(ok)
        end)

        it("should reject invalid day", function()
            local ok, err = due_dates.set_due_date(1, "2026-01-32")
            assert.is_false(ok)
        end)

        it("should reject out of range index", function()
            local ok, err = due_dates.set_due_date(99, "2026-03-15")
            assert.is_false(ok)
            assert.truthy(err:find("out of range"))
        end)
    end)

    describe("remove_due_date", function()
        it("should remove an existing due date", function()
            state.todos[1].due_date = "2026-03-15"
            local ok = due_dates.remove_due_date(1)
            assert.is_true(ok)
            assert.is_nil(state.todos[1].due_date)
        end)

        it("should return false when no due date set", function()
            local ok = due_dates.remove_due_date(1)
            assert.is_false(ok)
        end)

        it("should return false for invalid index", function()
            local ok = due_dates.remove_due_date(99)
            assert.is_false(ok)
        end)
    end)

    describe("format_due_date", function()
        it("should return empty for nil", function()
            assert.are.equal("", due_dates.format_due_date(nil))
        end)

        it("should include relative time indicator", function()
            -- Use a date far in the future to guarantee a positive days count
            local result = due_dates.format_due_date("2099-12-31")
            assert.truthy(result:match("%d+d%)"))
        end)

        it("should show overdue for past dates", function()
            local result = due_dates.format_due_date("2020-01-01")
            assert.truthy(result:find("overdue"))
        end)

        it("should return raw string for unparseable date", function()
            local result = due_dates.format_due_date("not-a-date")
            assert.are.equal("not-a-date", result)
        end)
    end)
end)
