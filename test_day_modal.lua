-- Test script for calendar day detail modal
vim.cmd("set runtimepath+=.")

-- Load the do-it module
local doit = require("doit")

-- Setup with calendar module
doit.setup({
    modules = {
        calendar = {
            enabled = true,
            default_view = "week",
        }
    }
})

-- Create some test events for today
local calendar_module = doit.get_module("calendar")
if calendar_module then
    local today = os.date("%Y-%m-%d")
    local tomorrow = calendar_module.state.add_days(today, 1)

    -- Mock some events
    local mock_events = {
        {
            date = today,
            title = "Team Standup Meeting",
            start_time = "09:00",
            end_time = "09:30",
            location = "Conference Room A",
            calendar = "Work",
            all_day = false,
        },
        {
            date = today,
            title = "Lunch with Client",
            start_time = "12:00",
            end_time = "13:30",
            location = "Downtown Restaurant",
            calendar = "Work",
            all_day = false,
        },
        {
            date = today,
            title = "Birthday Party",
            all_day = true,
            calendar = "Personal",
        },
        {
            date = tomorrow,
            title = "Project Review",
            start_time = "14:00",
            end_time = "15:00",
            tentative = true,
            location = "Zoom",
            calendar = "Work",
            all_day = false,
        },
    }

    -- Set the mock events
    calendar_module.state.set_events(mock_events)

    print("Calendar module setup complete")
    print("Opening calendar in week view...")

    -- Open the calendar
    vim.defer_fn(function()
        calendar_module.toggle()

        print("Calendar opened. Testing keys:")
        print("- Press '1' to see Sunday's events")
        print("- Press '2' to see Monday's events")
        print("- Press '3' to see Tuesday's events")
        print("- etc...")
        print("- Press 'q' to close the day detail modal")
        print("- Press '3' to switch to 3-day view")
        print("- In 3-day view, press 1-3 to see day details")
    end, 100)
else
    print("Failed to load calendar module")
end