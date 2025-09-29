# Calendar Module (v2.0)

The calendar module provides a TUI calendar interface with icalbuddy integration for viewing calendar events within Neovim.

> **Version 2.0 Updates**: Complete parser rewrite now correctly handles 100% of icalbuddy events (up from ~5%), UTF-8 support for special characters, auto-refresh on view changes, and silent operation mode.

## Features

- **icalbuddy Integration**: View real calendar events from macOS Calendar app
- **Multiple Views**: Day, 3-day, and week views for different perspectives
- **Mock Data Support**: Automatic fallback for Docker/CI environments
- **Smart Navigation**: Vim-style keybindings for intuitive control
- **Event Caching**: 60-second cache TTL for optimal performance
- **Configurable Hours**: Set your working hours (default 8am-8pm)
- **All Calendar Sources**: Supports iCloud, Google, Exchange calendars

## Commands

- `:DoItCalendar` - Toggle calendar window
- `:DoItCalendar show` - Show calendar window
- `:DoItCalendar hide` - Hide calendar window
- `:DoItCalendar today` - Jump to today
- `:DoItCalendar next` - Navigate to next period
- `:DoItCalendar prev` - Navigate to previous period
- `:DoItCalendar view {type}` - Switch to day/3day/week view
- `:DoItCalendar refresh` - Clear cache and refresh
- `:DoItCalendarDay` - Open in day view
- `:DoItCalendar3Day` - Open in 3-day view
- `:DoItCalendarWeek` - Open in week view

## Keybindings

| Key | Action |
|-----|--------|
| `<leader>dC` | Toggle calendar window |
| `d` | Switch to day view |
| `3` | Switch to 3-day view |
| `w` | Switch to week view |
| `h` | Previous period (day/3 days/week) |
| `l` | Next period (day/3 days/week) |
| `t` | Jump to today |
| `r` | Refresh (clears cache) |
| `q` | Close calendar |

## Configuration

```lua
calendar = {
    enabled = true,
    default_view = "day",  -- "day", "3day", or "week"
    hours = {
        start = 8,   -- Start hour (8am)
        ["end"] = 20 -- End hour (8pm)
    },
    window = {
        width = 80,
        height = 30,
        position = "center",
        border = "rounded",
        title = " Calendar ",
        title_pos = "center"
    },
    keymaps = {
        toggle_window = "<leader>dC",
        switch_view_day = "d",
        switch_view_3day = "3",
        switch_view_week = "w",
        next_period = "l",
        prev_period = "h",
        today = "t",
        close = "q",
        refresh = "r"
    },
    icalbuddy = {
        path = "icalbuddy",      -- Path to icalbuddy binary
        cache_ttl = 60,          -- Cache TTL in seconds
        format_options = "-nc -nrd" -- No calendar names, no relative dates
    }
}
```

## Requirements

### macOS (Real Calendar Data)
- Install icalbuddy: `brew install icalbuddy`
- Calendar app with configured accounts
- System permissions for calendar access

### Docker/Linux (Mock Data)
- No additional requirements
- Automatically generates realistic mock events
- Consistent data based on date seed

## icalbuddy Integration

The module uses icalbuddy to fetch events from macOS Calendar:

```bash
# Example icalbuddy command
icalbuddy -nc -nrd eventsFrom:today to:today+7
```

Event data is parsed from icalbuddy's text output and cached for 60 seconds to minimize system calls.

### Supported Event Properties
- Title and location
- Start and end times
- All-day events
- Calendar source
- Notes/descriptions

## View Modes

### Day View
Shows a single day with hourly time slots from configured start to end hours. Events are displayed inline with their duration.

```
Monday, September 2, 2024
──────────────────────────
 8:00 ┃ 
 9:00 ┃ Team Standup (30m)
10:00 ┃ 
11:00 ┃ Product Review (1h)
```

### 3-Day View
Displays three consecutive days with a condensed event list for each day, ideal for short-term planning.

### Week View
Shows Monday through Sunday with the first 2-3 events per day, providing a weekly overview.

## Docker Support

When running in Docker containers (detected via `/.dockerenv`):
- Automatically switches to mock data mode
- Generates realistic meeting patterns
- Includes daily standups, random meetings, lunch breaks
- Consistent data based on date seed for testing

## Dashboard Integration

The calendar module adds upcoming events to the DoIt dashboard:
- Shows next 5 meetings
- Displays "Today" or "Tomorrow" for near events
- Shows day of week for future events
- Includes time ranges for each event

## Storage

The calendar module is read-only and does not store any data. All event information comes from icalbuddy or mock data generation.

## Troubleshooting

### icalbuddy not found
```bash
brew install icalbuddy
which icalbuddy  # Verify installation
```

### No events showing
- Check Calendar app permissions in System Settings > Privacy & Security
- Test icalbuddy manually: `icalbuddy eventsToday`
- Verify calendar accounts are configured

### Docker environment
- Mock data activates automatically
- No configuration needed
- Check for `/.dockerenv` file if detection fails