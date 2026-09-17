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

// Returns the Space that owns a window, including the dedicated Space a
// full-screen window always occupies. Returns 0 when unknown.
uint64_t GLDWSpaceForWindow(uint32_t window_id);

// Whether a Space is the one currently showing on the display that owns it.
bool GLDWIsSpaceCurrent(uint64_t space_id);

// How far a Space is from the one on screen, in Mission Control order: the number
// of "move one Space left/right" steps needed to reach it, negative for left.
//
// Changing Space by naming a new current Space is not an option — the WindowServer
// rejects the calls that show and hide the two Spaces (an ordinary connection is
// not allowed to), which leaves the Space being left composited on the display.
// Asking macOS to make the move by its own shortcut is what transitions cleanly.
//
// Returns false when the distance cannot be established, including when the Space
// belongs to a display other than the one holding the menu bar, since the shortcut
// only moves that one.
bool GLDWSpaceWalkSteps(uint64_t space_id, int *steps);

#endif
