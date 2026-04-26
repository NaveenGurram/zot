const std = @import("std");
const db = @import("db.zig");

export fn zot_init() bool {
    var map = std.process.Environ.Map.init(std.heap.c_allocator);
    defer map.deinit();
    return db.init(&map);
}

export fn zot_deinit() void {
    db.deinit();
}

export fn zot_add(msg: [*:0]const u8, project: [*:0]const u8, due: [*:0]const u8, remind: bool, schedule: u8) i64 {
    return db.addNote(msg, project, due, remind, @enumFromInt(schedule));
}

export fn zot_delete(id: i64) bool {
    return db.deleteNote(id);
}

export fn zot_update(id: i64, msg: [*:0]const u8, project: [*:0]const u8, due: [*:0]const u8, remind: bool, schedule: u8) bool {
    return db.updateNote(id, msg, project, due, remind, @enumFromInt(schedule));
}

const ListCb = *const fn (id: i64, msg: [*:0]const u8, project: [*:0]const u8, due: [*:0]const u8, remind: bool, schedule: u8) callconv(.c) void;

var ext_cb: ?ListCb = null;

fn bridge(id: i64, msg: [*:0]const u8, project: [*:0]const u8, due: [*:0]const u8, remind: bool, sched: db.RemindSchedule) void {
    if (ext_cb) |cb| cb(id, msg, project, due, remind, @intFromEnum(sched));
}

export fn zot_list(cb: ListCb) void {
    ext_cb = cb;
    db.listNotes(&bridge);
    ext_cb = null;
}

export fn zot_done(id: i64) bool {
    return db.markDone(id);
}

export fn zot_search(keyword: [*:0]const u8, cb: ListCb) void {
    ext_cb = cb;
    db.searchNotes(keyword, &bridge);
    ext_cb = null;
}

export fn zot_list_by_due(due: [*:0]const u8, cb: ListCb) void {
    ext_cb = cb;
    db.listNotesByDue(due, &bridge);
    ext_cb = null;
}
