const std = @import("std");
const db = @import("db.zig");

const plist_label = "com.zot.notify";
const plist_filename = "com.zot.notify.plist";

const MAX_NOTIFICATIONS = 32;

const Notification = struct {
    msg: [256]u8 = undefined,
    msg_len: usize = 0,
    subtitle: [256]u8 = undefined,
    subtitle_len: usize = 0,
};

var notes: [MAX_NOTIFICATIONS]Notification = undefined;
var note_count: usize = 0;

fn collect(_: i64, msg: [*:0]const u8, project: [*:0]const u8, due: [*:0]const u8, _: bool, _: db.RemindSchedule) void {
    if (note_count >= MAX_NOTIFICATIONS) return;
    var n = &notes[note_count];
    const m = std.mem.span(msg);
    const p = std.mem.span(project);
    const d = std.mem.span(due);

    const mlen = @min(m.len, 256);
    @memcpy(n.msg[0..mlen], m[0..mlen]);
    n.msg_len = mlen;

    var sw = std.Io.Writer.fixed(&n.subtitle);
    if (p.len > 0) sw.writeAll(p) catch {};
    if (p.len > 0 and d.len > 0) sw.writeAll(" \xe2\x80\x94 due: ") catch {};
    if (d.len > 0) sw.writeAll(d) catch {};
    n.subtitle_len = sw.buffered().len;

    note_count += 1;
}

fn escapeAS(s: []const u8, w: *std.Io.Writer) void {
    for (s) |ch| {
        if (ch == '"') w.writeAll("\\\"") catch return
        else if (ch == '\\') w.writeAll("\\\\") catch return
        else w.writeByte(ch) catch return;
    }
}

pub fn sendNotifications(io: std.Io) usize {
    note_count = 0;
    db.listReminders(&collect);

    for (0..note_count) |i| {
        var buf: [2048]u8 = undefined;
        var w = std.Io.Writer.fixed(&buf);
        w.writeAll("display notification \"") catch continue;
        escapeAS(notes[i].msg[0..notes[i].msg_len], &w);
        w.writeAll("\" with title \"Zot Reminder\"") catch continue;
        if (notes[i].subtitle_len > 0) {
            w.writeAll(" subtitle \"") catch continue;
            escapeAS(notes[i].subtitle[0..notes[i].subtitle_len], &w);
            w.writeAll("\"") catch continue;
        }
        const script = w.buffered();

        var child = std.process.spawn(io, .{
            .argv = &.{ "osascript", "-e", script },
            .stdin = .close,
            .stdout = .close,
            .stderr = .close,
        }) catch continue;
        _ = child.wait(io) catch {};
    }
    return note_count;
}

pub fn install(io: std.Io, zot_path: []const u8) bool {
    const home = std.mem.sliceTo(std.c.getenv("HOME") orelse return false, 0);

    var dir_buf: [512]u8 = undefined;
    var dw = std.Io.Writer.fixed(&dir_buf);
    dw.print("{s}/Library/LaunchAgents", .{home}) catch return false;
    const dir_path = dw.buffered();

    var path_buf: [600]u8 = undefined;
    var pw = std.Io.Writer.fixed(&path_buf);
    pw.print("{s}/{s}", .{ dir_path, plist_filename }) catch return false;
    const plist_path = pw.buffered();

    var content_buf: [2048]u8 = undefined;
    var cw = std.Io.Writer.fixed(&content_buf);
    cw.print(
        \\<?xml version="1.0" encoding="UTF-8"?>
        \\<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        \\<plist version="1.0">
        \\<dict>
        \\    <key>Label</key>
        \\    <string>{s}</string>
        \\    <key>ProgramArguments</key>
        \\    <array>
        \\        <string>{s}</string>
        \\        <string>notify</string>
        \\    </array>
        \\    <key>StartInterval</key>
        \\    <integer>300</integer>
        \\    <key>RunAtLoad</key>
        \\    <true/>
        \\    <key>StandardOutPath</key>
        \\    <string>/tmp/zot-notify.log</string>
        \\    <key>StandardErrorPath</key>
        \\    <string>/tmp/zot-notify.log</string>
        \\</dict>
        \\</plist>
        \\
    , .{ plist_label, zot_path }) catch return false;
    const content = cw.buffered();

    // Write plist
    const file = std.Io.Dir.cwd().createFile(io, plist_path, .{}) catch return false;
    file.writeStreamingAll(io, content) catch {
        file.close(io);
        return false;
    };
    file.close(io);

    // Load agent
    var child = std.process.spawn(io, .{
        .argv = &.{ "launchctl", "load", plist_path },
        .stdin = .close,
    }) catch return false;
    _ = child.wait(io) catch return false;

    return true;
}

pub fn uninstall(io: std.Io) bool {
    const home = std.mem.sliceTo(std.c.getenv("HOME") orelse return false, 0);

    var path_buf: [600]u8 = undefined;
    var pw = std.Io.Writer.fixed(&path_buf);
    pw.print("{s}/Library/LaunchAgents/{s}", .{ home, plist_filename }) catch return false;
    const plist_path = pw.buffered();

    // Unload
    var child = std.process.spawn(io, .{
        .argv = &.{ "launchctl", "unload", plist_path },
        .stdin = .close,
    }) catch return false;
    _ = child.wait(io) catch {};

    // Remove file
    std.Io.Dir.cwd().deleteFile(io, plist_path) catch return false;
    return true;
}
