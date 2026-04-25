const std = @import("std");
const db = @import("db.zig");
const posix = std.posix;

// ANSI color codes
const BOLD = "\x1b[1m";
const DIM = "\x1b[2m";
const RED = "\x1b[31m";
const RESET = "\x1b[0m";

var global_io: std.Io = undefined;

fn print(comptime fmt: []const u8, args: anytype) void {
    var buf: [4096]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, fmt, args) catch return;
    std.Io.File.stdout().writeStreamingAll(global_io, s) catch {};
}

fn readByte() ?u8 {
    var buf: [1]u8 = undefined;
    const n = std.Io.File.stdin().readStreaming(global_io, &.{&buf}) catch return null;
    if (n == 0) return null;
    return buf[0];
}

const HELP =
    \\
    \\📝 Zot — A fast, minimal note-taking CLI
    \\
    \\Usage: zot [command] [options]
    \\
    \\Commands:
    \\  (default)        Add a new note
    \\  list [. | name]  List notes (optionally filter by project)
    \\  list -d <date>   List notes by due date (today/tomorrow/eow/eom/YYYY-MM-DD/MM/DD/YYYY)
    \\  search <text>    Search notes by message
    \\  done <id>        Mark a note as complete
    \\  delete <id>      Delete a note (asks for confirmation)
    \\  update <id>      Update a note
    \\  remind           Show due reminders
    \\
    \\Options:
    \\  -n, --note       Note message (required for add/update)
    \\  -p, --project    Project name (use "." for current directory)
    \\  -d, --due        Due date (YYYY-MM-DD, MM/DD/YYYY, today, tomorrow, eow, eom)
    \\  --remind         Enable reminders
    \\  --no-remind      Disable reminders (for update)
    \\  --every          Reminder frequency: hour or day (implies --remind)
    \\  -y               Skip confirmation prompts
    \\  --help           Show this help
    \\
    \\Examples:
    \\  zot -n "buy groceries"
    \\  zot -n "fix bug" -p . -d tomorrow --every hour
    \\  zot list .
    \\  zot list -d today
    \\  zot search "bug"
    \\  zot done 3
    \\  zot update 3 --no-remind
    \\
;

pub fn main(init: std.process.Init) !void {
    global_io = init.io;
    var args = init.minimal.args.iterate();
    _ = args.skip();

    var message: ?[:0]const u8 = null;
    var project: ?[:0]const u8 = null;
    var due_date: ?[:0]const u8 = null;
    var remind: ?bool = null;
    var schedule: db.RemindSchedule = .none;
    var cmd: enum { add, list, delete, update, remind, search, done, help } = .add;
    var target_id: i64 = 0;
    var list_filter: ?[:0]const u8 = null;
    var list_due_filter: ?[:0]const u8 = null;
    var search_term: ?[:0]const u8 = null;
    var skip_confirm: bool = false;
    var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;

    while (args.next()) |arg| {
        if (eql(arg, "-n") or eql(arg, "--note")) {
            message = args.next();
        } else if (eql(arg, "-p") or eql(arg, "--project")) {
            const raw = args.next() orelse @as([:0]const u8, "");
            project = if (eql(raw, ".")) resolveCwd(&cwd_buf) orelse raw else raw;
        } else if (eql(arg, "-d") or eql(arg, "--due")) {
            const val = args.next() orelse @as([:0]const u8, "");
            if (cmd == .list)
                list_due_filter = val
            else
                due_date = val;
        } else if (eql(arg, "--remind")) {
            remind = true;
        } else if (eql(arg, "--no-remind")) {
            remind = false;
        } else if (eql(arg, "--every")) {
            remind = true;
            const v: []const u8 = args.next() orelse @as([:0]const u8, "");
            schedule = if (std.mem.eql(u8, v, "hour")) .every_hour else if (std.mem.eql(u8, v, "day")) .every_day else .none;
        } else if (eql(arg, "-y")) {
            skip_confirm = true;
        } else if (eql(arg, "--help") or eql(arg, "-h")) {
            cmd = .help;
        } else if (eql(arg, "list")) {
            cmd = .list;
            if (args.next()) |next| {
                if (eql(next, "-d") or eql(next, "--due")) {
                    list_due_filter = args.next();
                } else if (next.len > 0 and next[0] != '-') {
                    list_filter = if (eql(next, ".")) resolveCwd(&cwd_buf) orelse "." else next;
                }
            }
        } else if (eql(arg, "search")) {
            cmd = .search;
            search_term = args.next();
        } else if (eql(arg, "done")) {
            cmd = .done;
            const v: []const u8 = args.next() orelse "0";
            target_id = std.fmt.parseInt(i64, v, 10) catch 0;
        } else if (eql(arg, "remind")) {
            cmd = .remind;
        } else if (eql(arg, "delete")) {
            cmd = .delete;
            const v: []const u8 = args.next() orelse "0";
            target_id = std.fmt.parseInt(i64, v, 10) catch 0;
        } else if (eql(arg, "update")) {
            cmd = .update;
            const v: []const u8 = args.next() orelse "0";
            target_id = std.fmt.parseInt(i64, v, 10) catch 0;
        }
    }

    if (cmd == .help) {
        print(HELP, .{});
        return;
    }

    if (!db.init()) {
        print("Failed to init database\n", .{});
        return;
    }
    defer db.deinit();

    // Resolve special date strings
    var date_buf: [11]u8 = undefined;
    const raw_due: [:0]const u8 = due_date orelse @as([:0]const u8, "");
    const resolved_due: [*:0]const u8 = db.resolveDueDate(raw_due.ptr, &date_buf) orelse raw_due.ptr;

    switch (cmd) {
        .help => unreachable,
        .add => {
            const msg = message orelse {
                print("Usage: zot -n \"note\" [-p project] [-d due] [--remind] [--every hour|day]\nTry: zot --help\n", .{});
                return;
            };
            const id = db.addNote(msg.ptr, (project orelse @as([:0]const u8, "")).ptr, resolved_due, remind orelse false, schedule);
            if (id == -2) {
                print("Invalid due date. Format: YYYY-MM-DD or YYYY-MM-DD HH:MM (09:00-17:00)\n", .{});
            } else if (id > 0) {
                print("Note added (id: {d})\n", .{id});
            } else {
                print("Failed to add note\n", .{});
            }
        },
        .list => {
            list_count = 0;
            print("\n" ++ BOLD ++ "\xf0\x9f\x93\x8b Zot Notes" ++ RESET, .{});
            if (list_filter) |f| print(" " ++ DIM ++ "[{s}]" ++ RESET, .{f});
            var due_dbuf: [11]u8 = undefined;
            const resolved_due_filter: ?[*:0]const u8 = if (list_due_filter) |d| (db.resolveDueDate(d.ptr, &due_dbuf) orelse d.ptr) else null;
            if (resolved_due_filter) |rd| print(" " ++ DIM ++ "[due: {s}]" ++ RESET, .{rd});
            print("\n" ++ DIM ++ "\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80" ++ RESET ++ "\n", .{});
            if (resolved_due_filter) |rd| {
                db.listNotesByDue(rd, &printNote);
            } else if (list_filter) |f| {
                db.listNotesByProject(f.ptr, &printNote);
            } else {
                db.listNotes(&printNote);
            }
            if (list_count == 0)
                print("  No notes found.\n", .{});
            print("\n", .{});
        },
        .search => {
            const term = search_term orelse {
                print("Usage: zot search \"keyword\"\n", .{});
                return;
            };
            list_count = 0;
            print("\n" ++ BOLD ++ "\xf0\x9f\x94\x8d Search: \"{s}\"" ++ RESET ++ "\n" ++ DIM ++ "\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80" ++ RESET ++ "\n", .{term});
            db.searchNotes(term.ptr, &printNote);
            if (list_count == 0)
                print("  No matches found.\n", .{});
            print("\n", .{});
        },
        .done => {
            if (target_id == 0) { print("Usage: zot done <id>\n", .{}); return; }
            if (db.markDone(target_id))
                print("\xe2\x9c\x93 Note #{d} marked done\n", .{target_id})
            else
                print("Failed — note not found\n", .{});
        },
        .remind => {
            remind_count = 0;
            print("\n" ++ BOLD ++ "\xf0\x9f\x94\x94 Zot Reminders" ++ RESET ++ "\n" ++ DIM ++ "\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80" ++ RESET ++ "\n", .{});
            db.listReminders(&printReminder);
            if (remind_count == 0)
                print("  No reminders due.\n", .{})
            else
                print(DIM ++ "\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80" ++ RESET ++ "\n\xe2\x9a\xa1 {d} reminder{s} due.\n", .{ remind_count, if (remind_count > 1) "s" else "" });
            print("\n", .{});
        },
        .delete => {
            if (target_id == 0) { print("Usage: zot delete <id>\n", .{}); return; }
            if (!skip_confirm) {
                print("Delete note #{d}? [y/N] ", .{target_id});
                const ch = readByte() orelse return;
                if (ch != 'y' and ch != 'Y') { print("Cancelled.\n", .{}); return; }
            }
            if (db.deleteNote(target_id)) print("Deleted note {d}\n", .{target_id}) else print("Failed\n", .{});
        },
        .update => {
            if (message == null and project == null and due_date == null and remind == null) {
                print("Usage: zot update <id> [-n \"msg\"] [-p project] [-d due] [--remind|--no-remind] [--every hour|day]\n", .{});
                return;
            }
            if (db.updateNotePartial(target_id, message, project, due_date, remind, schedule))
                print("Updated note {d}\n", .{target_id})
            else
                print("Invalid due date (YYYY-MM-DD or YYYY-MM-DD HH:MM) or update failed\n", .{});
        },
    }
}

// Extract last path component for display
fn shortProject(project: [*:0]const u8) [*:0]const u8 {
    const p: []const u8 = std.mem.span(project);
    if (p.len == 0) return project;
    // If it looks like a path (contains /), show last component
    if (std.mem.lastIndexOfScalar(u8, p, '/')) |idx| {
        if (idx + 1 < p.len) return @ptrCast(project + idx + 1);
    }
    return project;
}

var list_count: usize = 0;

fn printNote(id: i64, msg: [*:0]const u8, project: [*:0]const u8, due: [*:0]const u8, remind: bool, sched: db.RemindSchedule) void {
    list_count += 1;
    const d: []const u8 = std.mem.span(due);
    const p: []const u8 = std.mem.span(project);
    const overdue = d.len > 0 and db.isDueNowOrPast(due);

    // Message line: bold, red if overdue
    if (overdue)
        print("  " ++ RED ++ BOLD ++ "#{d} {s}" ++ RESET ++ "\n", .{ id, msg })
    else
        print("  " ++ BOLD ++ "#{d}" ++ RESET ++ " {s}\n", .{ id, msg });

    // Metadata line: dim
    if (p.len > 0 or d.len > 0 or remind) {
        print("     " ++ DIM, .{});
        var sep = false;
        if (p.len > 0) { print("\xf0\x9f\x93\x81 {s}", .{shortProject(project)}); sep = true; }
        if (d.len > 0) {
            if (sep) print("  ", .{});
            if (overdue) print(RESET ++ RED ++ "\xf0\x9f\x93\x85 {s}" ++ RESET ++ DIM, .{due}) else print("\xf0\x9f\x93\x85 {s}", .{due});
            sep = true;
        }
        if (remind) { if (sep) print("  ", .{}); print("\xf0\x9f\x94\x94 {s}", .{if (sched == .every_hour) "every hour" else if (sched == .every_day) "every day" else "on"}); }
        print(RESET ++ "\n", .{});
    }
}

var remind_count: usize = 0;

fn printReminder(id: i64, msg: [*:0]const u8, project: [*:0]const u8, due: [*:0]const u8, _: bool, _: db.RemindSchedule) void {
    remind_count += 1;
    const p: []const u8 = std.mem.span(project);
    const d: []const u8 = std.mem.span(due);
    const sp = shortProject(project);
    if (p.len > 0 and d.len > 0) {
        print("  {d}. " ++ BOLD ++ "(#{d}) {s}" ++ RESET ++ DIM ++ " [{s}] - due: " ++ RESET ++ RED ++ "{s}" ++ RESET ++ "\n", .{ remind_count, id, msg, sp, due });
    } else if (p.len > 0) {
        print("  {d}. " ++ BOLD ++ "(#{d}) {s}" ++ RESET ++ DIM ++ " [{s}]" ++ RESET ++ "\n", .{ remind_count, id, msg, sp });
    } else if (d.len > 0) {
        print("  {d}. " ++ BOLD ++ "(#{d}) {s}" ++ RESET ++ " - due: " ++ RED ++ "{s}" ++ RESET ++ "\n", .{ remind_count, id, msg, due });
    } else {
        print("  {d}. " ++ BOLD ++ "(#{d}) {s}" ++ RESET ++ "\n", .{ remind_count, id, msg });
    }
}

fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

fn resolveCwd(buf: *[std.fs.max_path_bytes]u8) ?[:0]const u8 {
    const len = std.process.currentPath(global_io, buf) catch return null;
    buf[len] = 0;
    return buf[0..len :0];
}
