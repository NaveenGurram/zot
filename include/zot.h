// zot.h - C ABI header for Swift interop with libzot.dylib
#ifndef ZOT_H
#define ZOT_H

#include <stdbool.h>
#include <stdint.h>

bool zot_init(void);
void zot_deinit(void);

// schedule: 0=none, 1=everyHour, 2=everyDay
int64_t zot_add(const char *message, const char *project, const char *due_date, bool remind, uint8_t schedule);
bool zot_delete(int64_t id);
bool zot_update(int64_t id, const char *message, const char *project, const char *due_date, bool remind, uint8_t schedule);

typedef void (*zot_list_callback)(int64_t id, const char *message, const char *project, const char *due_date, bool remind, uint8_t schedule);
void zot_list(zot_list_callback cb);

#endif
