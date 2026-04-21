# Zot — A fast, minimal note-taking CLI

*Named after "jot" (as in jot down ideas) — but since it's written in Zig, it became Zot.*

A fast, minimal notes CLI written in Zig. Uses macOS system SQLite for storage and exports a C ABI shared library for Swift app integration.

## Install

```bash
# Build
zig build

# Binary at zig-out/bin/zot
# Add to PATH:
export PATH="$PATH:/path/to/zot/zig-out/bin"
```

## Usage

```bash
zot -n "your note here" [options]
zot --help
```

### Commands

| Command | Description |
|---------|-------------|
| *(default)* | Add a new note |
| `list [. \| name]` | List notes (optionally filter by project) |
| `list -d <date>` | List notes by due date |
| `search <text>` | Search notes by message (case-insensitive) |
| `done <id>` | Mark a note as complete |
| `delete <id>` | Delete a note (asks for confirmation) |
| `update <id>` | Update a note by ID |
| `remind` | Show due reminders |

### Options

| Flag | Short | Description |
|------|-------|-------------|
| `--note` | `-n` | Note message (required for add/update) |
| `--project` | `-p` | Project name (use `.` for current directory) |
| `--due` | `-d` | Due date |
| `--remind` | | Enable reminders |
| `--no-remind` | | Disable reminders (for update) |
| `--every` | | Reminder frequency: `hour` or `day` (implies --remind) |
| `-y` | | Skip confirmation prompts |
| `--help` | `-h` | Show help |

## Due Date Formats

| Format | Example | Description |
|--------|---------|-------------|
| `YYYY-MM-DD` | `2026-05-01` | Specific date |
| `YYYY-MM-DD HH:MM` | `2026-05-01 14:00` | Date with time (09:00–17:00 only) |
| `today` | | Resolves to today's date |
| `tomorrow` | | Resolves to tomorrow's date |
| `eow` | | End of week (Friday) |
| `eom` | | End of month (last working day) |

## Examples

```bash
# Add a simple note
zot -n "buy groceries"

# Add with project (current directory)
zot -n "fix auth bug" -p .

# Add with due date and reminders
zot -n "code review" -d tomorrow -p backend --every hour
zot -n "sprint retro" -d eow --every day
zot -n "monthly report" -d eom --remind

# List notes
zot list              # all notes
zot list .            # notes for current directory
zot list backend      # notes for "backend" project
zot list -d today     # notes due today
zot list -d eow       # notes due end of week

# Search
zot search "bug"

# Mark done
zot done 3

# Update
zot update 3 -n "updated message" -d "2026-06-01"
zot update 3 --no-remind

# Delete (with confirmation)
zot delete 3
zot delete 3 -y       # skip confirmation

# Show due reminders
zot remind
```

## Reminder Popup (launchd)

Zot includes a SwiftUI reminder popup (`zot-remind`) that shows due reminders in a native macOS window with checkboxes. Select items and click "✓ Mark Done" to complete them.

A launchd agent runs this popup every hour, Monday–Friday 9AM–5PM. If no reminders are due, nothing happens.

```bash
# Install
cp scripts/com.zot.remind.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.zot.remind.plist

# Unload
launchctl unload ~/Library/LaunchAgents/com.zot.remind.plist

# Build the reminder UI
swiftc -o zig-out/bin/zot-remind scripts/ZotRemind.swift \
  -framework SwiftUI -framework AppKit -parse-as-library
```

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
bool zot_done(int64_t id);
void zot_search(const char *keyword, zot_list_callback cb);
void zot_list_by_due(const char *due_date, zot_list_callback cb);
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
zot_done(id)
zot_deinit()
```

## Storage

Notes are stored in SQLite at `~/.zot_notes.db`. Both the CLI and Swift app share the same database.

## Running Tests

```bash
zig build test
```

## Project Structure

```
├── build.zig                # Build config (exe + dylib + tests)
├── include/zot.h            # C header for Swift bridging
├── scripts/
│   ├── ZotRemind.swift      # SwiftUI reminder popup
│   ├── zot-remind.sh        # Launcher script for launchd
│   └── com.zot.remind.plist # launchd agent
└── src/
    ├── db.zig               # SQLite CRUD, search, date validation
    ├── main.zig             # CLI entry point + formatted output
    ├── lib.zig              # C ABI exports
    └── tests.zig            # Unit tests
```
