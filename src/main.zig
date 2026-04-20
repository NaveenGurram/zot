const std = @import("std");
const db = @import("db.zig");
const posix = std.posix;
const c = @cImport(@cInclude("stdlib.h"));

fn print(comptime fmt: []const u8, args: anytype) void {
    var buf: [4096]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, fmt, args) catch return;
    _ = posix.write(1, s) catch {};
}

pub fn main() void {
    var args = std.process.args();
    _ = args.skip();

    var message: ?[:0]const u8 = null;
    var project: [:0]const u8 = "";
    var due_date: [:0]const u8 = "";
    var remind: bool = false;
    var schedule: db.RemindSchedule = .none;
    var cmd: enum { add, list, delete, update, remind, zap } = .add;
    var target_id: i64 = 0;

    while (args.next()) |arg| {
        if (eql(arg, "-n") or eql(arg, "--note")) {
            message = args.next();
        } else if (eql(arg, "-p") or eql(arg, "--project")) {
            project = args.next() orelse "";
        } else if (eql(arg, "-d") or eql(arg, "--due")) {
            due_date = args.next() orelse "";
        } else if (eql(arg, "--remind")) {
            remind = true;
        } else if (eql(arg, "--every")) {
            remind = true;
            const v: []const u8 = args.next() orelse "";
            schedule = if (std.mem.eql(u8, v, "hour")) .every_hour else if (std.mem.eql(u8, v, "day")) .every_day else .none;
        } else if (eql(arg, "list")) {
            cmd = .list;
        } else if (eql(arg, "remind")) {
            cmd = .remind;
        } else if (eql(arg, "zap")) {
            cmd = .zap;
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

    if (!db.init()) {
        print("Failed to init database\n", .{});
        return;
    }
    defer db.deinit();

    // Resolve special date strings
    var date_buf: [11]u8 = undefined;
    const resolved_due: [*:0]const u8 = db.resolveDueDate(due_date.ptr, &date_buf) orelse due_date.ptr;

    switch (cmd) {
        .add => {
            const msg = message orelse {
                print("Usage: zot -n \"note\" [-p project] [-d due_date] [--remind] [--every hour|day]\n", .{});
                return;
            };
            const id = db.addNote(msg.ptr, project.ptr, resolved_due, remind, schedule);
            if (id == -2) {
                print("Invalid due date. Format: YYYY-MM-DD or YYYY-MM-DD HH:MM (09:00-17:00)\n", .{});
            } else if (id > 0) {
                print("Note added (id: {d})\n", .{id});
            } else {
                print("Failed to add note\n", .{});
            }
        },
        .list => db.listNotes(&printNote),
        .remind => db.listReminders(&printReminder),
        .zap => db.listReminders(&zapNote),
        .delete => {
            if (db.deleteNote(target_id)) print("Deleted note {d}\n", .{target_id}) else print("Failed\n", .{});
        },
        .update => {
            const msg = message orelse {
                print("Usage: zn update <id> -n \"new message\" [...]\n", .{});
                return;
            };
            if (db.updateNote(target_id, msg.ptr, project.ptr, resolved_due, remind, schedule))
                print("Updated note {d}\n", .{target_id})
            else
                print("Invalid due date (YYYY-MM-DD or YYYY-MM-DD HH:MM) or update failed\n", .{});
        },
    }
}

fn printNote(id: i64, msg: [*:0]const u8, project: [*:0]const u8, due: [*:0]const u8, remind: bool, sched: db.RemindSchedule) void {
    print("[{d}] {s}", .{ id, msg });
    const p: []const u8 = std.mem.span(project);
    const d: []const u8 = std.mem.span(due);
    if (p.len > 0) print(" | project: {s}", .{project});
    if (d.len > 0) print(" | due: {s}", .{due});
    if (remind) print(" | remind: {s}", .{if (sched == .every_hour) "everyHour" else "everyDay"});
    print("\n", .{});
}

fn printReminder(id: i64, msg: [*:0]const u8, project: [*:0]const u8, due: [*:0]const u8, _: bool, _: db.RemindSchedule) void {
    _ = id;
    const p: []const u8 = std.mem.span(project);
    const d: []const u8 = std.mem.span(due);
    if (p.len > 0 and d.len > 0) {
        print("{s} [{s}] - due: {s}\n", .{ msg, project, due });
    } else if (p.len > 0) {
        print("{s} [{s}]\n", .{ msg, project });
    } else if (d.len > 0) {
        print("{s} - due: {s}\n", .{ msg, due });
    } else {
        print("{s}\n", .{msg});
    }
}

fn zapNote(id: i64, msg: [*:0]const u8, project: [*:0]const u8, due: [*:0]const u8, _: bool, _: db.RemindSchedule) void {
    _ = id;
    const p: []const u8 = std.mem.span(project);
    const d: []const u8 = std.mem.span(due);
    var buf: [2048]u8 = undefined;
    const body = if (p.len > 0 and d.len > 0)
        std.fmt.bufPrint(&buf, "{s} [{s}] - due: {s}", .{ msg, project, due }) catch return
    else if (p.len > 0)
        std.fmt.bufPrint(&buf, "{s} [{s}]", .{ msg, project }) catch return
    else if (d.len > 0)
        std.fmt.bufPrint(&buf, "{s} - due: {s}", .{ msg, due }) catch return
    else
        std.fmt.bufPrint(&buf, "{s}", .{msg}) catch return;

    var cmd_buf: [4096]u8 = undefined;
    const cmd = std.fmt.bufPrintZ(&cmd_buf, "osascript -e 'display notification \"{s}\" with title \"\xf0\x9f\x93\x9d Zot\"'", .{body}) catch return;
    _ = c.system(cmd.ptr);
    print("⚡ {s}\n", .{body});
}

fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
