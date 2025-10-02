# Calendar Debug Commands

## icalbuddy Command Format for 3-Day View

The calendar module uses this command to fetch events:

```bash
icalbuddy -nc -b '""' eventsFrom:YYYY-MM-DD to:YYYY-MM-DD
```

### Parameters:
- `-nc` = no calendar names (don't show which calendar events are from)
- `-b '""'` = empty bullet (no bullet points before events)
- `eventsFrom:YYYY-MM-DD` = start date in ISO format
- `to:YYYY-MM-DD` = end date in ISO format

### Date Ranges by View:

**3-Day View:**
- Start: Today's date (e.g., `2025-01-30`)
- End: Today + 2 days (e.g., `2025-02-01`)
- Shows: Today, Tomorrow, Day after tomorrow

**Week View:**
- Start: Sunday of current week
- End: Saturday of current week
- Shows: Full week Sunday-Saturday

**Day View:**
- Start: Current selected date
- End: Same as start date
- Shows: Single day

## Test Commands

### Check Thursday Events (if today is Tuesday)
```bash
# 3-day view (Today through Day after tomorrow)
icalbuddy -nc -b '""' eventsFrom:2025-01-30 to:2025-02-01

# Specific day only (Thursday)
icalbuddy -nc -b '""' eventsFrom:2025-02-01 to:2025-02-01

# Full week to see all events
icalbuddy -nc -b '""' eventsFrom:2025-01-26 to:2025-02-01
```

### Debug in Neovim

1. **Enable debug mode:**
   ```vim
   :DoItCalendar debug
   ```

2. **Check cache status:**
   ```vim
   :DoItCalendar check-cache
   ```

3. **Check current state:**
   ```vim
   :DoItCalendar check-state
   ```

4. **Run diagnostics (shows raw icalbuddy output):**
   ```vim
   :DoItCalendar diagnose
   ```

5. **Force refresh (clears cache):**
   ```vim
   :DoItCalendar refresh
   ```

## Cache Information

- **Location:** In-memory variable in `lua/doit/modules/calendar/icalbuddy.lua`
- **TTL:** 60 seconds default
- **Clear cache:** `:DoItCalendar refresh` or switch views
- **Config option:** `config.icalbuddy.cache_ttl`

## Troubleshooting Missing Events

1. Run raw icalbuddy command to verify events exist
2. Check if events are multi-day (might be showing on wrong day)
3. Verify date parsing with `:DoItCalendar debug` enabled
4. Check for duplicates with `:DoItCalendar check-cache`
5. Look for timezone issues in event dates

## Common Issues

- **Events not showing:** Check if they're all-day events that span multiple days
- **Wrong day:** Multi-day events might be parsed to start date only
- **Duplicates:** Fixed by deduplication in filter_events() and before caching
- **Thursday missing:** Could be date range calculation or parsing issue