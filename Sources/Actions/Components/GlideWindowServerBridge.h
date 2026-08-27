#ifndef GLIDE_WINDOW_SERVER_BRIDGE_H
#define GLIDE_WINDOW_SERVER_BRIDGE_H

#include <stdbool.h>
#include <stdint.h>
#include <sys/types.h>
#include <CoreFoundation/CoreFoundation.h>

// Focuses one WindowServer window without raising every window owned by its process.
// Returns false when the private compatibility symbols are unavailable or reject the request.
bool GLDWFocusWindow(pid_t process_id, uint32_t window_id);

// Returns retained CFArray<CFNumber(window id)> for every WindowServer window,
// of every process, that the window manager tracks — including windows on
// inactive and full-screen Spaces, which Accessibility does not expose.
//
//   current_space_only  restrict to the Space currently visible on each display
//   ordered_in_only     drop windows that are not ordered in (minimized, hidden
//                       application, or closed but still cached by the app)
//
// Returns NULL when the private symbols are unavailable.
CFArrayRef GLDWCopyWindowIDs(bool current_space_only, bool ordered_in_only);

#endif
