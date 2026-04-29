# Zot — A fast, minimal note-taking CLI

*Named after "jot" (as in jot down ideas) — but since it's written in Zig, it became Zot.*

A fast, minimal notes CLI written in Zig. Uses macOS system SQLite for storage and exports a C ABI shared library for Swift app integration.

## Prerequisites

- **Zig**: 0.16.0 or higher
- **SQLite3**: Standard on macOS

## Install

### Option 1: Standard Install (requires sudo)
```bash
zig build -Doptimize=ReleaseSafe
sudo cp zig-out/bin/zot /usr/local/bin/
```

### Option 2: Local Install (no sudo)
```bash
zig build -Doptimize=ReleaseSafe
mkdir -p ~/.local/bin
cp zig-out/bin/zot ~/.local/bin/
# Ensure ~/.local/bin is in your PATH
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
| `export` | Export all notes to JSON (stdout) |
| `import <file>` | Import notes from a JSON file |

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
| `YYYY-MM-DD` | `2026-05-01` | ISO specific date |
| `MM/DD/YYYY` | `05/01/2026` | US specific date |
| `YYYY-MM-DD HH:MM` | `2026-05-01 14:00` | Date with time (09:00–17:00 only) |
| `today` | | Resolves to today's date |
| `tomorrow` | | Resolves to tomorrow's date |
| `eow` | | End of week (Friday) |
| `eom` | | End of month (last working day) |

## Examples

```bash
# Add a simple note
zot -n "buy groceries"

# Use different date formats
zot -n "pay rent" -d 05/01/2026
zot -n "fix bug" -p . -d tomorrow --every hour

# Export and Import
zot export > notes_backup.json
zot import notes_backup.json
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

## Notes & Limitations

- **Text Size**: Note messages can be up to **1GB** in the database. Command-line input is usually limited by the OS to **~256KB**.
- **Rich Text**: Notes are stored as raw UTF-8. You can manually include ANSI escape codes for terminal styling.
- **JSON Format**: Exported JSON includes all fields: `id`, `message`, `project`, `due_date`, `remind`, `schedule`, and `done`.
- **Database**: SQLite data is stored at `~/.zot_notes.db`.

## Running Tests

```bash
zig build test
```

## Project Structure

```
├── build.zig                # Build config (exe + dylib + tests)
├── include/zot.h            # C header for Swift bridging
└── src/                     # Zig source code
    ├── db.zig               # SQLite storage & logic
    ├── lib.zig              # C ABI shared library exports
    ├── main.zig             # CLI entry point
    └── tests.zig            # Unit tests
```
