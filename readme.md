# Zot — A fast, minimal note-taking CLI

A fast, minimal notes CLI written in Zig. Uses macOS system SQLite for storage and exports a C ABI shared library for Swift app integration.

## Install

```bash
# Build
/path/to/zig build

# Binary at zig-out/bin/zot
# Add to PATH:
export PATH="$PATH:/path/to/zot/zig-out/bin"
```

## Usage

```bash
zot -n "your note here" [options]
```

### Flags

| Flag | Short | Description |
|------|-------|-------------|
| `--note` | `-n` | Note message (required for add/update) |
| `--project` | `-p` | Project name |
| `--due` | `-d` | Due date |
| `--remind` | | Enable reminders (boolean flag) |
| `--every` | | Reminder frequency: `hour` or `day` (implies --remind) |

### Commands

| Command | Description |
|---------|-------------|
| *(default)* | Add a new note |
| `list` | List all notes |
| `delete <id>` | Delete a note by ID |
| `update <id>` | Update a note by ID (pass flags to set new values) |
| `remind` | Print notes with active reminders that are due (stdout only) |
| `zap` | Fire macOS notifications for all due reminders |

## Due Date Formats

| Format | Example | Description |
|--------|---------|-------------|
| `YYYY-MM-DD` | `2026-05-01` | Specific date |
| `YYYY-MM-DD HH:MM` | `2026-05-01 14:00` | Date with time (09:00–17:00 only) |
| `today` | | Resolves to today's date |
| `tomorrow` | | Resolves to tomorrow's date |
| `eow` | | End of week (last working day, Friday) |
| `eom` | | End of month (last working day) |

## Examples

```bash
# Add a simple note
zot -n "buy groceries"

# Add with all options
zot -n "finish writing blog" -p work -d "2026-05-01" --every hour

# Quick due dates
zot -n "standup prep" -d today --remind
zot -n "code review" -d tomorrow -p backend
zot -n "sprint retro" -d eow
zot -n "monthly report" -d eom --every day

# List all notes
zot list

# Update a note
zot update 3 -n "updated message" -p "new project" -d "2026-06-01"

# Delete a note
zot delete 3

# Show due reminders (text output)
zot remind

# Fire macOS notifications for due reminders
zot zap
```

## Notifications (launchd)

Zot includes a launchd agent that sends macOS notifications for due reminders every hour, Monday–Friday 9AM–5PM.

```bash
# Install (already done during setup)
cp scripts/com.zot.notify.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.zot.notify.plist

# Unload
launchctl unload ~/Library/LaunchAgents/com.zot.notify.plist
```

The agent runs `scripts/zot-notify.sh` which calls `zot remind` and pipes each line to `osascript display notification`.

## Swift Integration (C ABI)

Zot builds a shared library (`libzot.dylib`) with C-exported functions for use in macOS Swift apps.

### Header (`include/zot.h`)

```c
bool zot_init(void);
void zot_deinit(void);
int64_t zot_add(const char *message, const char *project, const char *due_date, bool remind, uint8_t schedule);
bool zot_delete(int64_t id);
bool zot_update(int64_t id, const char *message, const char *project, const char *due_date, bool remind, uint8_t schedule);
void zot_list(zot_list_callback cb);
```

### Schedule values

| Value | Meaning |
|-------|---------|
| `0` | No reminder |
| `1` | Every hour |
| `2` | Every day |

### Swift usage

```swift
zot_init()
let id = zot_add("my note", "project", "2026-05-01", true, 1)
zot_list { id, msg, project, due, remind, schedule in
    print("[\(id)] \(String(cString: msg!))")
}
zot_deinit()
```

## Storage

Notes are stored in SQLite at `~/.zot_notes.db`. Both the CLI and Swift app share the same database.

## Running Tests

```bash
/path/to/zig build test
```

## Project Structure

```
├── build.zig              # Build config (exe + dylib + tests)
├── include/zot.h          # C header for Swift bridging
├── scripts/
│   ├── zot-notify.sh      # Notification script
│   └── com.zot.notify.plist  # launchd agent
└── src/
    ├── db.zig             # SQLite CRUD + date validation
    ├── main.zig           # CLI entry point
    ├── lib.zig            # C ABI exports
    └── tests.zig          # Unit tests
```
