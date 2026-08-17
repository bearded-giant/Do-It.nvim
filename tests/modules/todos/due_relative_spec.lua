local due_dates = require("doit.modules.todos.state.due_dates")

-- Fixed reference point so these never depend on when the suite runs.
-- 2026-06-15 12:00 local.
local NOW = os.time({ year = 2026, month = 6, day = 15, hour = 12 })

describe("due date relative rendering", function()
	it("counts whole days in both directions", function()
		assert.are.equal(-3, due_dates.days_until("2026-06-12", NOW))
		assert.are.equal(0, due_dates.days_until("2026-06-15", NOW))
		assert.are.equal(1, due_dates.days_until("2026-06-16", NOW))
		assert.are.equal(30, due_dates.days_until("2026-07-15", NOW))
	end)

	it("classifies status", function()
		assert.are.equal("overdue", due_dates.status("2026-06-14", NOW))
		assert.are.equal("today", due_dates.status("2026-06-15", NOW))
		assert.are.equal("soon", due_dates.status("2026-06-20", NOW))
		assert.are.equal("later", due_dates.status("2026-08-01", NOW))
	end)

	it("renders the labels the three surfaces share", function()
		assert.are.equal("overdue 3d", due_dates.render("2026-06-12", NOW))
		assert.are.equal("due today", due_dates.render("2026-06-15", NOW))
		assert.are.equal("due tomorrow", due_dates.render("2026-06-16", NOW))
		assert.are.equal("in 5d", due_dates.render("2026-06-20", NOW))
	end)

	it("returns nothing for a malformed or missing date", function()
		assert.is_nil(due_dates.days_until("garbage", NOW))
		assert.is_nil(due_dates.days_until(nil, NOW))
		assert.are.equal("", due_dates.render("2026-6-1", NOW))
	end)

	it("crossing a month boundary still counts one day", function()
		local eom = os.time({ year = 2026, month = 6, day = 30, hour = 12 })
		assert.are.equal(1, due_dates.days_until("2026-07-01", eom))
	end)
end)
