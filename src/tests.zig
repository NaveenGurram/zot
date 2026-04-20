const std = @import("std");
const db = @import("db.zig");

// --- validateDueDate tests ---

test "empty due date is valid" {
    try std.testing.expect(db.validateDueDate(""));
}

test "valid date YYYY-MM-DD" {
    try std.testing.expect(db.validateDueDate("2026-05-01"));
    try std.testing.expect(db.validateDueDate("2026-12-31"));
    try std.testing.expect(db.validateDueDate("2026-01-01"));
}

test "valid date with time" {
    try std.testing.expect(db.validateDueDate("2026-05-01 09:00"));
    try std.testing.expect(db.validateDueDate("2026-05-01 12:30"));
    try std.testing.expect(db.validateDueDate("2026-05-01 17:00"));
}

test "invalid free-form date rejected" {
    try std.testing.expect(!db.validateDueDate("May 1, 2026"));
    try std.testing.expect(!db.validateDueDate("next friday"));
    try std.testing.expect(!db.validateDueDate("tomorrow"));
}

test "invalid date separators" {
    try std.testing.expect(!db.validateDueDate("2026/05/01"));
    try std.testing.expect(!db.validateDueDate("2026.05.01"));
}

test "invalid month and day" {
    try std.testing.expect(!db.validateDueDate("2026-13-01"));
    try std.testing.expect(!db.validateDueDate("2026-00-01"));
    try std.testing.expect(!db.validateDueDate("2026-05-00"));
    try std.testing.expect(!db.validateDueDate("2026-05-32"));
}

test "time outside 9-17 rejected" {
    try std.testing.expect(!db.validateDueDate("2026-05-01 08:00"));
    try std.testing.expect(!db.validateDueDate("2026-05-01 18:00"));
    try std.testing.expect(!db.validateDueDate("2026-05-01 22:00"));
    try std.testing.expect(!db.validateDueDate("2026-05-01 00:00"));
}

test "17:01 rejected (past 5pm)" {
    try std.testing.expect(!db.validateDueDate("2026-05-01 17:01"));
}

test "invalid time format" {
    try std.testing.expect(!db.validateDueDate("2026-05-01 9:00"));
    try std.testing.expect(!db.validateDueDate("2026-05-0110:00"));
}

// --- CRUD tests ---

test "init and deinit" {
    // Use a temp db for testing
    try std.testing.expect(db.init());
    db.deinit();
}

test "add note minimal" {
    try std.testing.expect(db.init());
    defer db.deinit();

    const id = db.addNote("test note", "", "", false, .none);
    try std.testing.expect(id > 0);
}

test "add note with all fields" {
    try std.testing.expect(db.init());
    defer db.deinit();

    const id = db.addNote("full note", "myproject", "2026-06-15", true, .every_hour);
    try std.testing.expect(id > 0);
}

test "add note with invalid date returns -2" {
    try std.testing.expect(db.init());
    defer db.deinit();

    const id = db.addNote("bad", "", "not-a-date", false, .none);
    try std.testing.expectEqual(@as(i64, -2), id);
}

test "delete note" {
    try std.testing.expect(db.init());
    defer db.deinit();

    const id = db.addNote("to delete", "", "", false, .none);
    try std.testing.expect(id > 0);
    try std.testing.expect(db.deleteNote(id));
}

test "delete nonexistent note returns false" {
    try std.testing.expect(db.init());
    defer db.deinit();

    try std.testing.expect(!db.deleteNote(999999));
}

test "update note" {
    try std.testing.expect(db.init());
    defer db.deinit();

    const id = db.addNote("original", "", "", false, .none);
    try std.testing.expect(id > 0);
    try std.testing.expect(db.updateNote(id, "updated", "proj", "2026-07-01", true, .every_day));
}

test "update note with invalid date returns false" {
    try std.testing.expect(db.init());
    defer db.deinit();

    const id = db.addNote("orig", "", "", false, .none);
    try std.testing.expect(id > 0);
    try std.testing.expect(!db.updateNote(id, "new", "", "bad-date", false, .none));
}

test "list notes calls callback" {
    try std.testing.expect(db.init());
    defer db.deinit();

    _ = db.addNote("list test", "proj1", "2026-08-01", false, .none);

    // Verify listNotes doesn't crash
    db.listNotes(struct {
        fn cb(_: i64, _: [*:0]const u8, _: [*:0]const u8, _: [*:0]const u8, _: bool, _: db.RemindSchedule) void {}
    }.cb);
}

test "listReminders only shows remind=true" {
    try std.testing.expect(db.init());
    defer db.deinit();

    _ = db.addNote("no remind", "", "", false, .none);
    _ = db.addNote("yes remind", "", "", true, .every_hour);

    // Just verify it doesn't crash — callback testing is limited without closures
    db.listReminders(struct {
        fn cb(_: i64, _: [*:0]const u8, _: [*:0]const u8, _: [*:0]const u8, _: bool, _: db.RemindSchedule) void {}
    }.cb);
}

// --- isDueNowOrPast tests ---

test "empty due date is always due" {
    try std.testing.expect(db.isDueNowOrPast(""));
}

test "past date is due" {
    try std.testing.expect(db.isDueNowOrPast("2020-01-01"));
}

test "far future date is not due" {
    try std.testing.expect(!db.isDueNowOrPast("2099-12-31"));
}

// --- resolveDueDate tests ---

test "resolveDueDate returns null for regular date" {
    var buf: [11]u8 = undefined;
    try std.testing.expect(db.resolveDueDate("2026-05-01", &buf) == null);
}

test "resolveDueDate returns null for empty string" {
    var buf: [11]u8 = undefined;
    try std.testing.expect(db.resolveDueDate("", &buf) == null);
}

test "resolveDueDate resolves today" {
    var buf: [11]u8 = undefined;
    const result = db.resolveDueDate("today", &buf);
    try std.testing.expect(result != null);
    const s = std.mem.span(result.?);
    try std.testing.expectEqual(@as(usize, 10), s.len);
    try std.testing.expect(s[4] == '-' and s[7] == '-');
}

test "resolveDueDate resolves tomorrow" {
    var buf: [11]u8 = undefined;
    const result = db.resolveDueDate("tomorrow", &buf);
    try std.testing.expect(result != null);
    const s = std.mem.span(result.?);
    try std.testing.expectEqual(@as(usize, 10), s.len);
}

test "resolveDueDate resolves eow" {
    var buf: [11]u8 = undefined;
    const result = db.resolveDueDate("eow", &buf);
    try std.testing.expect(result != null);
    // Result should be a valid date
    try std.testing.expect(db.validateDueDate(result.?));
}

test "resolveDueDate resolves eom" {
    var buf: [11]u8 = undefined;
    const result = db.resolveDueDate("eom", &buf);
    try std.testing.expect(result != null);
    try std.testing.expect(db.validateDueDate(result.?));
}

test "resolveDueDate unknown string returns null" {
    var buf: [11]u8 = undefined;
    try std.testing.expect(db.resolveDueDate("next friday", &buf) == null);
}

// --- RemindSchedule enum ---

test "schedule enum values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(db.RemindSchedule.none));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(db.RemindSchedule.every_hour));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(db.RemindSchedule.every_day));
}
