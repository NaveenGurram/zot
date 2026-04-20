const std = @import("std");
const c = @cImport(@cInclude("sqlite3.h"));

pub const RemindSchedule = enum(u8) { none = 0, every_hour = 1, every_day = 2 };

var db: ?*c.sqlite3 = null;

pub fn init() bool {
    const home = std.posix.getenv("HOME") orelse "/tmp";
    var buf: [512]u8 = undefined;
    const path = std.fmt.bufPrintZ(&buf, "{s}/.zot_notes.db", .{home}) catch return false;

    if (c.sqlite3_open(path.ptr, &db) != c.SQLITE_OK) return false;

    const sql = "CREATE TABLE IF NOT EXISTS notes(" ++
        "id INTEGER PRIMARY KEY AUTOINCREMENT," ++
        "message TEXT NOT NULL," ++
        "project TEXT DEFAULT ''," ++
        "due_date TEXT DEFAULT ''," ++
        "remind INTEGER DEFAULT 0," ++
        "schedule INTEGER DEFAULT 0)";

    return c.sqlite3_exec(db, sql, null, null, null) == c.SQLITE_OK;
}

pub fn deinit() void {
    if (db) |d| _ = c.sqlite3_close(d);
    db = null;
}

pub fn addNote(msg: [*:0]const u8, project: [*:0]const u8, due: [*:0]const u8, remind: bool, sched: RemindSchedule) i64 {
    if (!validateDueDate(due)) return -2;
    var stmt: ?*c.sqlite3_stmt = null;
    const sql = "INSERT INTO notes(message,project,due_date,remind,schedule) VALUES(?,?,?,?,?)";
    if (c.sqlite3_prepare_v2(db, sql, -1, &stmt, null) != c.SQLITE_OK) return -1;
    defer _ = c.sqlite3_finalize(stmt);

    _ = c.sqlite3_bind_text(stmt, 1, msg, -1, null);
    _ = c.sqlite3_bind_text(stmt, 2, project, -1, null);
    _ = c.sqlite3_bind_text(stmt, 3, due, -1, null);
    _ = c.sqlite3_bind_int(stmt, 4, @intFromBool(remind));
    _ = c.sqlite3_bind_int(stmt, 5, @intFromEnum(sched));

    if (c.sqlite3_step(stmt) != c.SQLITE_DONE) return -1;
    return c.sqlite3_last_insert_rowid(db);
}

pub fn deleteNote(id: i64) bool {
    var stmt: ?*c.sqlite3_stmt = null;
    if (c.sqlite3_prepare_v2(db, "DELETE FROM notes WHERE id=?", -1, &stmt, null) != c.SQLITE_OK) return false;
    defer _ = c.sqlite3_finalize(stmt);
    _ = c.sqlite3_bind_int64(stmt, 1, id);
    if (c.sqlite3_step(stmt) != c.SQLITE_DONE) return false;
    return c.sqlite3_changes(db) > 0;
}

pub fn updateNote(id: i64, msg: [*:0]const u8, project: [*:0]const u8, due: [*:0]const u8, remind: bool, sched: RemindSchedule) bool {
    if (!validateDueDate(due)) return false;
    var stmt: ?*c.sqlite3_stmt = null;
    const sql = "UPDATE notes SET message=?,project=?,due_date=?,remind=?,schedule=? WHERE id=?";
    if (c.sqlite3_prepare_v2(db, sql, -1, &stmt, null) != c.SQLITE_OK) return false;
    defer _ = c.sqlite3_finalize(stmt);

    _ = c.sqlite3_bind_text(stmt, 1, msg, -1, null);
    _ = c.sqlite3_bind_text(stmt, 2, project, -1, null);
    _ = c.sqlite3_bind_text(stmt, 3, due, -1, null);
    _ = c.sqlite3_bind_int(stmt, 4, @intFromBool(remind));
    _ = c.sqlite3_bind_int(stmt, 5, @intFromEnum(sched));
    _ = c.sqlite3_bind_int64(stmt, 6, id);

    return c.sqlite3_step(stmt) == c.SQLITE_DONE;
}

pub fn updateNotePartial(id: i64, msg: ?[:0]const u8, project: [:0]const u8, due_date: [:0]const u8, remind: bool, sched: RemindSchedule) bool {
    // Resolve due date
    var date_buf: [11]u8 = undefined;
    const resolved_due: [*:0]const u8 = resolveDueDate(due_date.ptr, &date_buf) orelse due_date.ptr;
    if (!validateDueDate(resolved_due)) return false;

    var parts: [6][]const u8 = undefined;
    var count: usize = 0;
    if (msg != null) { parts[count] = "message=?"; count += 1; }
    if (project.len > 0) { parts[count] = "project=?"; count += 1; }
    if (std.mem.span(resolved_due).len > 0) { parts[count] = "due_date=?"; count += 1; }
    if (remind) { parts[count] = "remind=?"; count += 1; parts[count] = "schedule=?"; count += 1; }
    if (count == 0) return false;

    var sql_buf: [256]u8 = undefined;
    var pos: usize = 0;
    const prefix = "UPDATE notes SET ";
    @memcpy(sql_buf[pos..][0..prefix.len], prefix);
    pos += prefix.len;
    for (parts[0..count], 0..) |part, i| {
        if (i > 0) { sql_buf[pos] = ','; pos += 1; }
        @memcpy(sql_buf[pos..][0..part.len], part);
        pos += part.len;
    }
    const suffix = " WHERE id=?";
    @memcpy(sql_buf[pos..][0..suffix.len], suffix);
    pos += suffix.len;
    sql_buf[pos] = 0;

    var stmt: ?*c.sqlite3_stmt = null;
    if (c.sqlite3_prepare_v2(db, @ptrCast(&sql_buf), -1, &stmt, null) != c.SQLITE_OK) return false;
    defer _ = c.sqlite3_finalize(stmt);

    var bind: c_int = 1;
    if (msg) |m| { _ = c.sqlite3_bind_text(stmt, bind, m.ptr, -1, null); bind += 1; }
    if (project.len > 0) { _ = c.sqlite3_bind_text(stmt, bind, project.ptr, -1, null); bind += 1; }
    if (std.mem.span(resolved_due).len > 0) { _ = c.sqlite3_bind_text(stmt, bind, resolved_due, -1, null); bind += 1; }
    if (remind) { _ = c.sqlite3_bind_int(stmt, bind, 1); bind += 1; _ = c.sqlite3_bind_int(stmt, bind, @intFromEnum(sched)); bind += 1; }
    _ = c.sqlite3_bind_int64(stmt, bind, id);

    return c.sqlite3_step(stmt) == c.SQLITE_DONE;
}

pub const ListCallback = *const fn (id: i64, msg: [*:0]const u8, project: [*:0]const u8, due: [*:0]const u8, remind: bool, sched: RemindSchedule) void;

fn colText(stmt: ?*c.sqlite3_stmt, col: c_int) [*:0]const u8 {
    const ptr = c.sqlite3_column_text(stmt, col);
    if (ptr) |p| return @ptrCast(p);
    return "";
}

// Validates: empty (no due date), YYYY-MM-DD, or YYYY-MM-DD HH:MM (09-17)
pub fn validateDueDate(due: [*:0]const u8) bool {
    const s = std.mem.span(due);
    if (s.len == 0) return true;
    if (s.len != 10 and s.len != 16) return false;

    // YYYY-MM-DD
    if (s[4] != '-' or s[7] != '-') return false;
    _ = std.fmt.parseInt(u16, s[0..4], 10) catch return false;
    const month = std.fmt.parseInt(u8, s[5..7], 10) catch return false;
    const day = std.fmt.parseInt(u8, s[8..10], 10) catch return false;
    if (month < 1 or month > 12 or day < 1 or day > 31) return false;

    if (s.len == 16) {
        // YYYY-MM-DD HH:MM
        if (s[10] != ' ' or s[13] != ':') return false;
        const hour = std.fmt.parseInt(u8, s[11..13], 10) catch return false;
        const min = std.fmt.parseInt(u8, s[14..16], 10) catch return false;
        if (hour < 9 or hour > 17 or min > 59) return false;
        if (hour == 17 and min > 0) return false;
    }
    return true;
}

const days_in_month_table = [12]u8{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };

fn isLeapYear(y: u16) bool {
    return (y % 4 == 0 and y % 100 != 0) or (y % 400 == 0);
}

fn daysInMonth(y: u16, m: u8) u8 {
    if (m == 2 and isLeapYear(y)) return 29;
    return days_in_month_table[m - 1];
}

fn getToday() struct { year: u16, month: u8, day: u8, weekday: u8 } {
    const ts = std.time.timestamp();
    const epoch_secs: std.time.epoch.EpochSeconds = .{ .secs = @intCast(ts) };
    const epoch_day = epoch_secs.getEpochDay();
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    // epoch day 0 = 1970-01-01 which was Thursday (4)
    // dow: 0=Sun,1=Mon..5=Fri,6=Sat
    const raw_day: i64 = @intCast(epoch_day.day);
    const dow: u8 = @intCast(@mod(raw_day + 4, 7));
    return .{
        .year = @intCast(year_day.year),
        .month = @intFromEnum(month_day.month),
        .day = month_day.day_index + 1,
        .weekday = dow,
    };
}

fn addDays(year: u16, month: u8, day: u8, n: u8) struct { year: u16, month: u8, day: u8 } {
    var y = year;
    var m = month;
    var d: u16 = @as(u16, day) + n;
    while (d > daysInMonth(y, m)) {
        d -= daysInMonth(y, m);
        m += 1;
        if (m > 12) {
            m = 1;
            y += 1;
        }
    }
    return .{ .year = y, .month = m, .day = @intCast(d) };
}

// Resolve special strings into YYYY-MM-DD. Returns null if not a special string.
pub fn resolveDueDate(due: [*:0]const u8, buf: *[11]u8) ?[*:0]const u8 {
    const s = std.mem.span(due);
    const today = getToday();

    if (std.mem.eql(u8, s, "today")) {
        return fmtDate(buf, today.year, today.month, today.day);
    } else if (std.mem.eql(u8, s, "tomorrow")) {
        const t = addDays(today.year, today.month, today.day, 1);
        return fmtDate(buf, t.year, t.month, t.day);
    } else if (std.mem.eql(u8, s, "eow")) {
        // Last working day of this week (Friday)
        // weekday: 0=Sun,1=Mon,2=Tue,3=Wed,4=Thu,5=Fri,6=Sat
        const days_to_fri: u8 = if (today.weekday <= 5) 5 - today.weekday else 6; // if Sat, next Fri=6 days
        const t = addDays(today.year, today.month, today.day, days_to_fri);
        return fmtDate(buf, t.year, t.month, t.day);
    } else if (std.mem.eql(u8, s, "eom")) {
        // Last working day of this month
        const last_day_num = daysInMonth(today.year, today.month);
        // Calculate weekday of last_day: today.weekday + (last_day - today.day) mod 7
        const diff: u8 = last_day_num - today.day;
        var dow: u8 = @intCast(@mod(@as(u16, today.weekday) + diff, 7));
        var ld: u8 = last_day_num;
        while (dow == 0 or dow == 6) { // Sun or Sat
            ld -= 1;
            if (dow == 0) dow = 6 else dow -= 1;
        }
        return fmtDate(buf, today.year, today.month, ld);
    }
    return null;
}

fn fmtDate(buf: *[11]u8, year: u16, month: u8, day: u8) [*:0]const u8 {
    _ = std.fmt.bufPrint(buf[0..10], "{d:0>4}-{d:0>2}-{d:0>2}", .{ year, month, day }) catch return "";
    buf[10] = 0;
    return @ptrCast(buf);
}

const time_c = @cImport(@cInclude("time.h"));

pub fn isDueNowOrPast(due: [*:0]const u8) bool {
    const s = std.mem.span(due);
    if (s.len == 0) return true;

    var now: time_c.time_t = undefined;
    _ = time_c.time(&now);
    const local = time_c.localtime(&now) orelse return true;

    var buf: [11]u8 = undefined;
    const today = std.fmt.bufPrint(&buf, "{d:0>4}-{d:0>2}-{d:0>2}", .{
        @as(u16, @intCast(local.*.tm_year + 1900)),
        @as(u8, @intCast(local.*.tm_mon + 1)),
        @as(u8, @intCast(local.*.tm_mday)),
    }) catch return true;

    const date_part = s[0..10];
    const cmp = std.mem.order(u8, date_part, today);
    if (cmp == .lt) return true;
    if (cmp == .gt) return false;

    if (s.len == 16) {
        const hour = std.fmt.parseInt(i32, s[11..13], 10) catch return true;
        return local.*.tm_hour >= hour;
    }
    return true;
}

pub fn listNotes(cb: ListCallback) void {
    var stmt: ?*c.sqlite3_stmt = null;
    if (c.sqlite3_prepare_v2(db, "SELECT id,message,project,due_date,remind,schedule FROM notes ORDER BY id", -1, &stmt, null) != c.SQLITE_OK) return;
    defer _ = c.sqlite3_finalize(stmt);

    while (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
        cb(
            c.sqlite3_column_int64(stmt, 0),
            colText(stmt, 1),
            colText(stmt, 2),
            colText(stmt, 3),
            c.sqlite3_column_int(stmt, 4) != 0,
            @enumFromInt(@as(u8, @intCast(c.sqlite3_column_int(stmt, 5)))),
        );
    }
}

pub fn listReminders(cb: ListCallback) void {
    var stmt: ?*c.sqlite3_stmt = null;
    if (c.sqlite3_prepare_v2(db, "SELECT id,message,project,due_date,remind,schedule FROM notes WHERE remind=1 ORDER BY id", -1, &stmt, null) != c.SQLITE_OK) return;
    defer _ = c.sqlite3_finalize(stmt);

    while (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
        const due = colText(stmt, 3);
        if (!isDueNowOrPast(due)) continue;
        cb(
            c.sqlite3_column_int64(stmt, 0),
            colText(stmt, 1),
            colText(stmt, 2),
            due,
            c.sqlite3_column_int(stmt, 4) != 0,
            @enumFromInt(@as(u8, @intCast(c.sqlite3_column_int(stmt, 5)))),
        );
    }
}
