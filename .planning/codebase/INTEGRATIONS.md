# External Integrations

**Analysis Date:** 2026-01-19

## APIs & External Services

**Calendar (icalbuddy):**
- macOS system calendar integration
- CLI tool: `icalbuddy` (must be installed separately via Homebrew)
- Implementation: `lua/doit/modules/calendar/icalbuddy.lua`
- Auth: None (uses system calendar permissions)
- Mock data available for Docker/testing environment

**Command format:**
```bash
icalbuddy -nc -b '""' eventsFrom:{start_date} to:{end_date}
```

## Data Storage

**Databases:**
- JSON file storage (local filesystem)
- No external database required

**File Storage Locations:**
- Todo lists: `vim.fn.stdpath("data")/doit/lists/{listname}.json`
- Notes (global): `vim.fn.stdpath("data")/doit/notes/global.json`
- Notes (project): `vim.fn.stdpath("data")/doit/notes/project-{sha256_hash}.json`
- Session state: `vim.fn.stdpath("data")/doit/session.json`

**JSON Formats:**
- Todos: Array of todo objects with `text`, `done`, `in_progress`, `priorities`, `due_date`, `tags`, etc.
- Notes: Object with `id`, `content`, `title`, `created_at`, `updated_at`, `metadata`
- Session: Object with `active_list`, `timestamp`

**Caching:**
- Calendar events cached with configurable TTL (default 60 seconds)
- Implementation: `lua/doit/modules/calendar/icalbuddy.lua` (local cache table)

## Authentication & Identity

**Auth Provider:**
- None required - local-only storage

**Project Identification:**
- Git root detection (optional)
- SHA256 hash of project path for project-scoped storage
- Fallback to CWD when git unavailable

## Monitoring & Observability

**Error Tracking:**
- Neovim notify system (`vim.notify()`)
- Log levels: DEBUG, INFO, WARN, ERROR

**Logs:**
- Standard Neovim messaging
- No external logging service

## CI/CD & Deployment

**Hosting:**
- GitHub repository: `bearded-giant/do-it.nvim`

**CI Pipeline:**
- GitHub Actions for tests
- Badge: `https://github.com/bearded-giant/do-it.nvim/actions/workflows/run-tests.yml`

**Test Environment:**
- Docker container based on Alpine Linux
- Neovim + plenary.nvim + oil.nvim
- Dockerfile: `docker/Dockerfile`

## Editor Integrations

**Lualine (Status Line):**
- Integration: `lua/doit/lualine.lua`
- Functions exposed: `active_todo()`, `current_list()`, `todo_stats()`
- File modification monitoring for external updates

**Tmux:**
- TPM plugin: `tmux/doit.tmux`
- Scripts directory: `tmux/scripts/`
- Features:
  - `todo-popup.sh` - Quick view popup
  - `todo-interactive.sh` - fzf-based management (18KB script)
  - `todo-toggle.sh` - Toggle current todo
  - `todo-next.sh` - Start next pending todo
  - `todo-create.sh` - Create new todo
  - `todo-status.sh` - Status bar segment

**Keybindings (Tmux):**
- `prefix + d + t` - Todo popup
- `prefix + d + i` - Interactive manager
- `prefix + d + x` - Toggle current
- `prefix + d + n` - Start next
- `prefix + d + c` - Create new
- Alt shortcuts: `M-T`, `M-I`, `M-X`, `M-N` (configurable)

## Import/Export

**Todo Import/Export:**
- Format: JSON
- Default path: `~/todos.json` (configurable)
- Functions: `state.import_todos(path)`, `state.export_todos(path)`
- Supports both flat array and structured format with `_metadata`

## Webhooks & Callbacks

**Incoming:**
- None

**Outgoing:**
- None

**Internal Events:**
- Module event system via `doit.core.events`
- Events: `on_note_created`, `on_note_updated`

## Environment Configuration

**Required env vars:**
- None

**Optional settings:**
- `@doit-key` (tmux) - Custom keybinding prefix (default: "d")
- `@doit-alt-bindings` (tmux) - Enable/disable alt key shortcuts (default: on)

**Tmux environment variables (set by plugin):**
- `DOIT_TMUX_DIR` - Plugin directory path
- `DOIT_SCRIPTS_DIR` - Scripts directory path

## External Dependencies Summary

| Integration | Required | Platform | Purpose |
|------------|----------|----------|---------|
| icalbuddy | No | macOS only | Calendar events |
| lualine.nvim | No | Cross-platform | Status line |
| fzf | No | Cross-platform | Tmux interactive mode |
| Neovim API | Yes | Cross-platform | Core functionality |
| plenary.nvim | Dev only | Cross-platform | Testing |

---

*Integration audit: 2026-01-19*
