#ifndef GLIDE_WINDOW_SERVER_BRIDGE_H
#define GLIDE_WINDOW_SERVER_BRIDGE_H

#include <stdbool.h>
#include <stdint.h>
#include <sys/types.h>

// Focuses one WindowServer window without raising every window owned by its process.
// Returns false when the private compatibility symbols are unavailable or reject the request.
bool GLDWFocusWindow(pid_t process_id, uint32_t window_id);

#endif
