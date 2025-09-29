-- Tests for calendar module
describe("DoIt Calendar Module", function()
    local calendar
    local icalbuddy
    local state
    
    -- Mock icalbuddy output based on new format (datetime first, then title)
    local mock_icalbuddy_output = [[
today
    Labor Day
today at 9:00 AM - 9:30 AM
    Team Standup
today at 12:30 PM - 1:00 PM
    Stand-up - SFE
tomorrow at 2:00 PM - 3:00 PM
    Product Review
day after tomorrow at 10:00 AM - 10:30 AM
    1:1 with Manager
Sep 4, 2025 at 3:00 PM - 4:00 PM
    Engineering Sync
Sep 6, 2025
    Weekend Project
Sep 8, 2025 at 10:00 AM - 12:00 PM
    Sprint Planning
]]
    
    before_each(function()
        -- Clear any existing module cache
        package.loaded["doit.modules.calendar"] = nil
        package.loaded["doit.modules.calendar.icalbuddy"] = nil
        package.loaded["doit.modules.calendar.state"] = nil
        package.loaded["doit.modules.calendar.config"] = nil
        
        -- Load modules
        calendar = require("doit.modules.calendar")
        icalbuddy = require("doit.modules.calendar.icalbuddy")
        state = require("doit.modules.calendar.state")
    end)
    
    describe("icalbuddy integration", function()
        it("should detect availability", function()
            local available = icalbuddy.check_availability()
            assert.is_true(available) -- Should be true in Docker (mocked)
        end)
        
        it("should parse icalbuddy output correctly", function()
            local events = icalbuddy.parse_output(mock_icalbuddy_output)
            
            -- Should have at least some events
            assert.is_true(#events > 0)
            assert.equals(8, #events, "Should parse all 8 events")
            
            -- Check first event (all-day)
            assert.equals("Labor Day", events[1].title)
            assert.is_true(events[1].all_day)
            assert.is_not_nil(events[1].date)
            
            -- Check timed event
            assert.equals("Team Standup", events[2].title)
            assert.equals("09:00", events[2].start_time)
            assert.equals("09:30", events[2].end_time)
            assert.is_not_nil(events[2].date)
            
            -- Check PM time conversion
            assert.equals("Stand-up - SFE", events[3].title)
            assert.equals("12:30", events[3].start_time)
            assert.equals("13:00", events[3].end_time)
            
            -- Check that dates are properly set for all events
            for i, event in ipairs(events) do
                assert.is_not_nil(event.date, "Event " .. i .. " should have a date")
                assert.is_string(event.title, "Event " .. i .. " should have a title")
            end
        end)
        
        it("should detect tentative events with attendees", function()
            -- Test output with attendees info
            local test_output = [[
today
    Stay at Grand attendees: b..
    All Day Meeting attendees: john@example.com
today at 9:00 AM - 10:00 AM
    Team Standup attendees: team@example.com
tomorrow at 2:00 PM - 3:00 PM
    Product Review
]]
            local events = icalbuddy.parse_output(test_output)

            assert.equals(4, #events)

            -- Events with attendees should be marked tentative
            assert.is_true(events[1].tentative, "Stay at Grand should be tentative")
            assert.equals("Stay at Grand", events[1].title) -- Title should not include attendees

            assert.is_true(events[2].tentative, "All Day Meeting should be tentative")
            assert.equals("All Day Meeting", events[2].title)

            assert.is_true(events[3].tentative, "Team Standup should be tentative")
            assert.equals("Team Standup", events[3].title)

            -- Event without attendees should not be tentative
            assert.is_not_true(events[4].tentative, "Product Review should not be tentative")
            assert.equals("Product Review", events[4].title)
        end)

        it("should parse different date formats correctly", function()
            -- Test with specific date headers
            local test_output = [[
today
    Today Event
tomorrow
    Tomorrow Event
day after tomorrow at 10:00 AM - 11:00 AM
    Day After Event
Sep 15, 2025 at 2:00 PM - 3:00 PM
    Future Event
]]
            local events = icalbuddy.parse_output(test_output)
            
            assert.equals(4, #events)
            
            -- Check that each event has the right relative date
            local today = os.date("%Y-%m-%d")
            local tomorrow = os.date("%Y-%m-%d", os.time() + 86400)
            local day_after = os.date("%Y-%m-%d", os.time() + 2 * 86400)
            
            assert.equals(today, events[1].date)
            assert.equals(tomorrow, events[2].date)
            assert.equals(day_after, events[3].date)
            assert.equals("2025-09-15", events[4].date)
        end)
        
        it("should generate mock events in Docker", function()
            -- Mock is_docker to return true
            local old_open = io.open
            io.open = function(path)
                if path == "/.dockerenv" then
                    return { close = function() end }
                end
                return old_open(path)
            end
            
            local events = icalbuddy.get_events("2025-09-01", "2025-09-07", {})
            
            -- Should have generated events
            assert.is_true(#events > 0)
            
            -- Check structure of generated events
            for _, event in ipairs(events) do
                assert.is_string(event.title)
                assert.is_string(event.date)
                -- Should have either time or all_day flag
                assert.is_true(event.start_time ~= nil or event.all_day == true)
            end
            
            -- Restore io.open
            io.open = old_open
        end)
    end)
    
    describe("state management", function()
        before_each(function()
            state.setup({ config = { default_view = "day" } })
        end)
        
        it("should initialize with today's date", function()
            local current = state.get_date()
            local today = os.date("%Y-%m-%d")
            assert.equals(today, current)
        end)
        
        it("should switch between views", function()
            assert.equals("day", state.get_view())
            
            state.set_view("week")
            assert.equals("week", state.get_view())
            
            state.set_view("3day")
            assert.equals("3day", state.get_view())
            
            -- Invalid view should not change
            state.set_view("invalid")
            assert.equals("3day", state.get_view())
        end)
        
        it("should calculate date ranges for different views", function()
            -- Mock today's date for consistent testing
            local today = os.date("%Y-%m-%d")
            state.set_date("2025-09-03") -- Wednesday

            -- Day view - uses current_date
            state.set_view("day")
            local start, end_date = state.get_date_range()
            assert.equals("2025-09-03", start)
            assert.equals("2025-09-03", end_date)

            -- 3-day view - always today + 2 days
            state.set_view("3day")
            start, end_date = state.get_date_range()
            assert.equals(today, start)  -- Always starts from today
            assert.equals(state.add_days(today, 2), end_date)  -- Today + 2 days

            -- Week view - always today + 6 days
            state.set_view("week")
            start, end_date = state.get_date_range()
            assert.equals(today, start)  -- Always starts from today
            assert.equals(state.add_days(today, 6), end_date)  -- Today + 6 days
        end)
        
        it("should navigate periods correctly", function()
            state.set_date("2025-09-03")
            
            -- Day navigation
            state.set_view("day")
            state.next_period()
            assert.equals("2025-09-04", state.get_date())
            
            state.prev_period()
            assert.equals("2025-09-03", state.get_date())
            
            -- Week navigation
            state.set_view("week")
            state.next_period()
            assert.equals("2025-09-10", state.get_date())
            
            state.prev_period()
            assert.equals("2025-09-03", state.get_date())
        end)
        
        it("should jump to today", function()
            state.set_date("2025-12-25")
            state.today()
            assert.equals(os.date("%Y-%m-%d"), state.get_date())
        end)
        
        it("should format dates correctly", function()
            local formatted = state.format_date("2025-09-03")
            assert.is_string(formatted)
            assert.is_true(formatted:find("September") ~= nil)
            assert.is_true(formatted:find("2025") ~= nil)
            
            local short = state.format_date_short("2025-09-03")
            assert.is_string(short)
            assert.is_true(#short < #formatted)
        end)
    end)
    
    describe("view renderers", function()
        local day_view
        local week_view
        local three_day_view

        before_each(function()
            day_view = require("doit.modules.calendar.ui.day_view")
            week_view = require("doit.modules.calendar.ui.week_view")
            three_day_view = require("doit.modules.calendar.ui.three_day_view")
            
            -- Setup minimal calendar module mock
            calendar = {
                state = state,
                config = {
                    hours = { start = 8, ["end"] = 20 },
                    window = { width = 80, height = 30 }
                }
            }
            
            state.setup(calendar)
            state.set_events({
                { title = "Morning Standup", date = "2025-09-03", start_time = "09:00", end_time = "09:30" },
                { title = "Lunch", date = "2025-09-03", start_time = "12:00", end_time = "13:00" },
                { title = "All Day Event", date = "2025-09-03", all_day = true }
            })
        end)
        
        it("should render day view", function()
            state.set_date("2025-09-03")
            state.set_view("day")
            
            local lines = day_view.render(calendar)
            
            assert.is_table(lines)
            assert.is_true(#lines > 0)
            
            -- Should show date header
            local header_found = false
            for _, line in ipairs(lines) do
                if line:find("September") then
                    header_found = true
                    break
                end
            end
            assert.is_true(header_found)
            
            -- Should show hours
            local nine_am_found = false
            for _, line in ipairs(lines) do
                if line:find("9:00") then
                    nine_am_found = true
                    break
                end
            end
            assert.is_true(nine_am_found)
            
            -- Should show events
            local standup_found = false
            for _, line in ipairs(lines) do
                if line:find("Morning Standup") then
                    standup_found = true
                    break
                end
            end
            assert.is_true(standup_found)
        end)
        
        it("should render week view", function()
            state.set_date("2025-09-03")
            state.set_view("week")
            
            local lines = week_view.render(calendar)
            
            assert.is_table(lines)
            assert.is_true(#lines > 0)
            
            -- Should show days of week
            local days = {"Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"}
            for _, day in ipairs(days) do
                local found = false
                for _, line in ipairs(lines) do
                    if line:find(day) then
                        found = true
                        break
                    end
                end
                assert.is_true(found, "Day " .. day .. " not found")
            end
        end)
        
        it("should calculate event duration", function()
            local duration = day_view.calculate_duration("09:00", "09:30")
            assert.equals("30m", duration)
            
            duration = day_view.calculate_duration("09:00", "10:00")
            assert.equals("1h", duration)
            
            duration = day_view.calculate_duration("09:00", "10:30")
            assert.equals("1h 30m", duration)
        end)
    end)
    
    describe("module setup", function()
        it("should setup with default config", function()
            local module = calendar.setup({})
            assert.is_table(module)
            assert.is_table(module.config)
            assert.equals("day", module.config.default_view)
        end)
        
        it("should create commands", function()
            calendar.setup({})
            
            -- Check if commands would be created
            local commands = require("doit.modules.calendar.commands")
            assert.is_function(commands.create_commands)
        end)
        
        it("should expose API methods", function()
            local module = calendar.setup({})
            
            assert.is_function(module.toggle)
            assert.is_function(module.show)
            assert.is_function(module.hide)
            assert.is_function(module.switch_view)
            assert.is_function(module.next_period)
            assert.is_function(module.prev_period)
            assert.is_function(module.today)
            assert.is_function(module.refresh)
        end)
    end)
end)