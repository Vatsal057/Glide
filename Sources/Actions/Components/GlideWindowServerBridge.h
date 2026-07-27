#ifndef GLIDE_WINDOW_SERVER_BRIDGE_H
#define GLIDE_WINDOW_SERVER_BRIDGE_H

#include <stdbool.h>
#include <stdint.h>
#include <sys/types.h>
#include <CoreFoundation/CoreFoundation.h>

// Focuses one WindowServer window without raising every window owned by its process.
// Returns false when the private compatibility symbols are unavailable or reject the request.
bool GLDWFocusWindow(pid_t process_id, uint32_t window_id);

// Returns retained CFArray<CFNumber(window id)> for every WindowServer window
// belonging to a process across all managed Spaces, including minimized ones.
// Returns NULL when the private symbols are unavailable.
CFArrayRef GLDWCopyWindowIDsForProcess(pid_t process_id);

#endif
