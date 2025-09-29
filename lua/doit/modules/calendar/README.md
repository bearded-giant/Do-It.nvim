# DoIt Calendar Module v2.0

A calendar integration module for do-it.nvim that provides a native Neovim interface for viewing calendar events using macOS's `icalbuddy` command-line tool.

## What's New in v2.0

- **Complete Parser Rewrite**: Now correctly parses 100% of icalbuddy events (up from ~5% in v1.0)
- **UTF-8 Support**: Handles narrow no-break spaces (U+202F) used by icalbuddy
- **Auto-refresh on View Switch**: Calendar automatically fetches new events when changing views
- **Silent Operation**: Removed notification spam, only diagnostic commands show output
- **Improved Multi-day Event Handling**: Fixed parsing for events spanning multiple days
- **Better Cache Management**: Cache clears automatically when switching views
- **Fixed Date Parsing**: Correctly handles relative dates (today, tomorrow) and absolute dates

## Features

- **Multiple View Modes**: Day, 3-day, and week views
- **Native Neovim Interface**: Fast, keyboard-driven calendar navigation
- **Real-time Event Updates**: Fetches events directly from macOS Calendar
- **Smart Caching**: Efficient event caching with automatic refresh
- **All-day and Timed Events**: Properly handles both event types
- **Attendee Support**: Shows event attendees when available

## Requirements

- macOS with `icalbuddy` installed
- Neovim 0.8+
- do-it.nvim plugin

### Installing icalbuddy

```bash
brew install icalbuddy
```

## Configuration

The calendar module is configured through your do-it.nvim setup:

```lua
require('doit').setup({
    modules = {
        calendar = {
            enabled = true,
            default_view = "day",  -- "day", "3day", or "week"
            hours = {
                start_hour = 6,     -- First hour shown (6 = 6 AM)
                end_hour = 22       -- Last hour shown (22 = 10 PM)
            },
            window = {
                position = "right",
                width = 80,
                height = 30
            },
            keymaps = {
                close = "q",
                next_period = "l",
                prev_period = "h",
                today = "t",
                switch_view_day = "1",
                switch_view_3day = "3",
                switch_view_week = "7",
                refresh = "r"
            },
            icalbuddy = {
                path = "icalbuddy",  -- Path to icalbuddy executable
                cache_timeout = 300,  -- Cache timeout in seconds
                debug = false         -- Enable debug output
            }
        }
    }
})
```

## Commands

### Basic Commands

| Command | Description |
|---------|-------------|
| `:DoItCalendar` or `:DoItCalendar toggle` | Toggle calendar window open/closed |
| `:DoItCalendar show` | Open calendar window |
| `:DoItCalendar hide` | Close calendar window |
| `:DoItCalendar today` | Jump to today's date |
| `:DoItCalendar next` | Navigate to next period (day/3-day/week) |
| `:DoItCalendar prev` | Navigate to previous period |
| `:DoItCalendar refresh` | Clear cache and refresh events |

### View Commands

| Command | Description |
|---------|-------------|
| `:DoItCalendar view day` | Switch to day view |
| `:DoItCalendar view 3day` | Switch to 3-day view |
| `:DoItCalendar view week` | Switch to week view |
| `:DoItCalendarDay` | Open calendar in day view |
| `:DoItCalendar3Day` | Open calendar in 3-day view |
| `:DoItCalendarWeek` | Open calendar in week view |

### Debug Commands

| Command | Description |
|---------|-------------|
| `:DoItCalendar debug` | Toggle debug mode on/off |
| `:DoItCalendar diagnose` | Show raw icalbuddy output in new buffer |
| `:DoItCalendar check-state` | Display current calendar state info |
| `:DoItCalendar check-date` | Show system date and calendar date info |
| `:DoItCalendar test-parse` | Test parser with sample event data |

## Keybindings

When the calendar window is open, these keys are available:

| Key | Action |
|-----|--------|
| `q` | Close calendar |
| `h` | Previous period |
| `l` | Next period |
| `t` | Jump to today |
| `1` | Switch to day view |
| `3` | Switch to 3-day view |
| `7` | Switch to week view |
| `r` | Refresh events |

## View Modes

### Day View
Shows a single day with hourly time slots from start_hour to end_hour. Events are displayed in their time slots with duration indicators.

### 3-Day View
Displays today and the next two days side-by-side, making it easy to see your immediate schedule.

### Week View
Shows a full week starting from Sunday, with all seven days visible in columns.

## Event Display

Events are displayed with the following information:
- **Time**: Start and end times for timed events
- **Title**: Event name
- **All-day indicator**: ALL DAY label for all-day events
- **Multi-day events**: Shown with date ranges

Example display:
```
08:00-10:00: Team Standup
10:30-11:30: Product Review
ALL DAY: Company Holiday
```

## Troubleshooting

### No Events Showing

1. Check icalbuddy is installed:
   ```bash
   which icalbuddy
   ```

2. Test icalbuddy directly:
   ```bash
   icalbuddy eventsToday
   ```

3. Run diagnostics:
   ```vim
   :DoItCalendar diagnose
   ```

### Events Not Updating

Clear the cache and refresh:
```vim
:DoItCalendar refresh
```

Or press `r` while in the calendar window.

### Debug Mode

Enable debug mode to see detailed parsing information:
```vim
:DoItCalendar debug
```

This will show notifications about event parsing and help identify issues.

## Technical Details

### Parser

The module uses a custom parser for icalbuddy output that:
- Handles both hierarchical and flat output formats
- Normalizes UTF-8 narrow no-break spaces (U+202F) used by icalbuddy
- Parses relative dates (today, tomorrow) and absolute dates
- Extracts event properties (attendees, location, etc.)
- Properly identifies all-day vs timed events

### Caching

Events are cached for 5 minutes by default to reduce system calls. The cache is automatically cleared when:
- Switching between view modes
- Manually refreshing with `r` key
- Running the refresh command

### Date Handling

- Week view always starts on Sunday
- All views are relative to the current date
- Date navigation moves by the view period (1 day, 3 days, or 7 days)

## API

The calendar module can be accessed programmatically:

```lua
local calendar = require('doit.modules.calendar')

-- Toggle calendar
calendar.toggle()

-- Show calendar
calendar.show()

-- Switch to week view
calendar.switch_view("week")

-- Navigate to next period
calendar.next_period()

-- Jump to today
calendar.today()

-- Refresh events
calendar.refresh()
```

## Contributing

The calendar module is part of do-it.nvim. To contribute:

1. Check existing issues for calendar-related bugs or features
2. Test changes with different calendar configurations
3. Ensure icalbuddy parsing works with various event types
4. Run the test suite: `docker/run-tests.sh`

## License

Part of do-it.nvim - see main project for license details.