# Do-It.nvim Docker Environment

This directory contains the Docker environment for testing and demonstrating the Do-It.nvim plugin.

## Quick Start

```bash
# Run interactive environment
./run-interactive.sh

# Or use make
make docker-interactive

# Run tests
./run-tests.sh
# Or
make test
```

## Files

- `Dockerfile` - Container definition
- `init.lua` - Neovim configuration for the container
- `run-interactive.sh` - Launch interactive testing environment
- `run-tests.sh` - Run the test suite
- `HELP.txt` - Central help documentation (auto-generated)
- `generate-help.lua` - Script to generate HELP.txt from lua/doit/help.lua

## Keeping Help Documentation in Sync

The help documentation is centralized in `lua/doit/help.lua`. To update the Docker help file:

```bash
make update-help
```

This ensures that:
- The interactive script shows current keybindings
- The in-container help is accurate
- All documentation stays synchronized

## Features Available in Docker

The Docker environment provides the full Do-It framework:

- **Todo Management**: Create, edit, organize todos
- **Multiple Lists**: Switch between named todo lists
- **Categories**: Organize with categories
- **Tags**: Filter with #hashtags
- **Due Dates**: Calendar integration
- **Notes**: Project or global notes
- **Import/Export**: Backup and share

## Data Persistence

Data is stored in `~/.doit-data/` on your host machine and persists between sessions.

## Customization

Edit `init.lua` to change the container configuration. The main settings:
- Window sizes and positions
- Keybindings
- Storage paths
- Module enable/disable