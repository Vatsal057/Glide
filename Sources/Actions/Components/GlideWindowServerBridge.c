#include "GlideWindowServerBridge.h"

#include <CoreGraphics/CoreGraphics.h>
#include <dlfcn.h>
#include <pthread.h>
#include <string.h>

typedef struct {
    uint32_t high;
    uint32_t low;
} GLDWProcessSerialNumber;

typedef int32_t (*GLDWGetProcessForPID)(pid_t, GLDWProcessSerialNumber *);
typedef CGError (*GLDWSetFrontProcess)(GLDWProcessSerialNumber *, uint32_t, uint32_t);
typedef CGError (*GLDWPostEventRecord)(GLDWProcessSerialNumber *, uint8_t *);
typedef int (*GLDWMainConnectionID)(void);
typedef CFArrayRef (*GLDWCopyManagedDisplaySpaces)(int);
typedef CFArrayRef (*GLDWCopyWindowsWithOptionsAndTags)(int, uint32_t, CFArrayRef, uint32_t, uint64_t *, uint64_t *);
typedef CFArrayRef (*GLDWCopySpacesForWindows)(int, int, CFArrayRef);
typedef CFStringRef (*GLDWCopyManagedDisplayForSpace)(int, uint64_t);
typedef CFStringRef (*GLDWCopyActiveMenuBarDisplayIdentifier)(int);

static const char *skylight_path =
    "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight";

static GLDWGetProcessForPID fn_get_process = NULL;
static GLDWSetFrontProcess fn_set_front = NULL;
static GLDWPostEventRecord fn_post_event = NULL;
static GLDWMainConnectionID fn_main_connection = NULL;
static GLDWCopyManagedDisplaySpaces fn_copy_display_spaces = NULL;
static GLDWCopyWindowsWithOptionsAndTags fn_copy_windows = NULL;
static GLDWCopySpacesForWindows fn_spaces_for_windows = NULL;
static GLDWCopyManagedDisplayForSpace fn_display_for_space = NULL;
static GLDWCopyActiveMenuBarDisplayIdentifier fn_active_menubar_display = NULL;

static pthread_once_t bridge_init_once = PTHREAD_ONCE_INIT;

static void init_bridge_symbols(void) {
    void *handle = dlopen(skylight_path, RTLD_LAZY | RTLD_GLOBAL);
    if (handle == NULL) {
        return;
    }
    fn_get_process = (GLDWGetProcessForPID)dlsym(RTLD_DEFAULT, "GetProcessForPID");
    fn_set_front = (GLDWSetFrontProcess)dlsym(handle, "_SLPSSetFrontProcessWithOptions");
    fn_post_event = (GLDWPostEventRecord)dlsym(handle, "SLPSPostEventRecordTo");
    fn_main_connection = (GLDWMainConnectionID)dlsym(handle, "SLSMainConnectionID");
    fn_copy_display_spaces = (GLDWCopyManagedDisplaySpaces)dlsym(handle, "SLSCopyManagedDisplaySpaces");
    fn_copy_windows = (GLDWCopyWindowsWithOptionsAndTags)dlsym(handle, "SLSCopyWindowsWithOptionsAndTags");
    fn_spaces_for_windows = (GLDWCopySpacesForWindows)dlsym(handle, "SLSCopySpacesForWindows");
    fn_display_for_space = (GLDWCopyManagedDisplayForSpace)dlsym(handle, "SLSCopyManagedDisplayForSpace");
    fn_active_menubar_display =
        (GLDWCopyActiveMenuBarDisplayIdentifier)dlsym(handle, "SLSCopyActiveMenuBarDisplayIdentifier");
}

static bool post_key_window_event(
    GLDWPostEventRecord post_event,
    GLDWProcessSerialNumber *process,
    uint32_t window_id
) {
    // Event-record layout adapted from yabai's MIT-licensed window focus implementation.
    // See the bundled ThirdPartyNotices.txt. Delivery is by window id at an off-content point.
    uint8_t bytes[0x100] = {0};
    const CGPoint off_content = {.x = -1, .y = -1};
    bytes[0x04] = 0xf8;
    bytes[0x3a] = 0x10;
    memcpy(bytes + 0x20, &off_content, sizeof(off_content));
    memcpy(bytes + 0x3c, &window_id, sizeof(window_id));

    bytes[0x08] = (uint8_t)kCGEventLeftMouseDown;
    CGError down = post_event(process, bytes);
    bytes[0x08] = (uint8_t)kCGEventLeftMouseUp;
    CGError up = post_event(process, bytes);
    return down == kCGErrorSuccess && up == kCGErrorSuccess;
}

bool GLDWFocusWindow(pid_t process_id, uint32_t window_id) {
    if (process_id <= 0 || window_id == 0) {
        return false;
    }

    pthread_once(&bridge_init_once, init_bridge_symbols);
    if (fn_get_process == NULL || fn_set_front == NULL || fn_post_event == NULL) {
        return false;
    }

    GLDWProcessSerialNumber process = {0};
    if (fn_get_process(process_id, &process) != 0) {
        return false;
    }

    // 0x200 marks the request as user-generated and, unlike 0x100, does not raise all windows.
    CGError front = fn_set_front(&process, window_id, 0x200);
    bool made_key = front == kCGErrorSuccess
        && post_key_window_event(fn_post_event, &process, window_id);
    return made_key;
}

static void append_space_id(CFMutableArrayRef spaces, CFDictionaryRef space) {
    if (space == NULL || CFGetTypeID(space) != CFDictionaryGetTypeID()) return;
    CFNumberRef space_id = CFDictionaryGetValue(space, CFSTR("id64"));
    if (space_id != NULL && CFGetTypeID(space_id) == CFNumberGetTypeID()) {
        CFArrayAppendValue(spaces, space_id);
    }
}

static uint64_t space_id_of(CFDictionaryRef space) {
    if (space == NULL || CFGetTypeID(space) != CFDictionaryGetTypeID()) return 0;
    CFNumberRef number = CFDictionaryGetValue(space, CFSTR("id64"));
    if (number == NULL || CFGetTypeID(number) != CFNumberGetTypeID()) return 0;
    uint64_t space_id = 0;
    CFNumberGetValue(number, kCFNumberSInt64Type, &space_id);
    return space_id;
}

CFArrayRef GLDWCopyWindowIDs(bool current_space_only, bool ordered_in_only) {
    pthread_once(&bridge_init_once, init_bridge_symbols);
    if (fn_main_connection == NULL || fn_copy_display_spaces == NULL || fn_copy_windows == NULL) {
        return NULL;
    }

    int connection = fn_main_connection();
    if (connection == 0) {
        return NULL;
    }

    CFArrayRef display_spaces = fn_copy_display_spaces(connection);
    if (display_spaces == NULL) {
        return NULL;
    }

    CFMutableArrayRef spaces = CFArrayCreateMutable(NULL, 0, &kCFTypeArrayCallBacks);
    CFIndex display_count = CFArrayGetCount(display_spaces);
    for (CFIndex i = 0; i < display_count; ++i) {
        CFDictionaryRef display = (CFDictionaryRef)CFArrayGetValueAtIndex(display_spaces, i);
        if (display == NULL || CFGetTypeID(display) != CFDictionaryGetTypeID()) continue;

        if (current_space_only) {
            append_space_id(spaces, CFDictionaryGetValue(display, CFSTR("Current Space")));
            continue;
        }
        CFArrayRef display_space_list = CFDictionaryGetValue(display, CFSTR("Spaces"));
        if (display_space_list == NULL || CFGetTypeID(display_space_list) != CFArrayGetTypeID()) continue;
        CFIndex space_count = CFArrayGetCount(display_space_list);
        for (CFIndex j = 0; j < space_count; ++j) {
            append_space_id(spaces, (CFDictionaryRef)CFArrayGetValueAtIndex(display_space_list, j));
        }
    }

    uint64_t set_tags = 0;
    uint64_t clear_tags = 0;
    CFArrayRef windows = NULL;
    if (CFArrayGetCount(spaces) > 0) {
        // Owner connection 0 means "every process". 0x7 also reports windows that
        // are ordered out (minimized, or belonging to a hidden application);
        // 0x2 reports only the ordered-in ones.
        uint32_t options = ordered_in_only ? 0x2 : 0x7;
        windows = fn_copy_windows(connection, 0, spaces, options, &set_tags, &clear_tags);
    }
    CFRelease(spaces);
    CFRelease(display_spaces);
    return windows;
}

uint64_t GLDWSpaceForWindow(uint32_t window_id) {
    if (window_id == 0) {
        return 0;
    }

    pthread_once(&bridge_init_once, init_bridge_symbols);
    if (fn_main_connection == NULL || fn_spaces_for_windows == NULL) {
        return 0;
    }

    int connection = fn_main_connection();
    if (connection == 0) {
        return 0;
    }

    CFNumberRef id_number = CFNumberCreate(NULL, kCFNumberSInt32Type, &window_id);
    if (id_number == NULL) {
        return 0;
    }
    CFArrayRef window_ids = CFArrayCreate(NULL, (const void **)&id_number, 1, &kCFTypeArrayCallBacks);

    // 0x7 reports every Space that references the window rather than only the
    // visible ones, which is what makes an inactive or full-screen Space answer.
    CFArrayRef spaces = fn_spaces_for_windows(connection, 0x7, window_ids);
    uint64_t space_id = 0;
    if (spaces != NULL) {
        if (CFArrayGetCount(spaces) > 0) {
            CFNumberRef first = (CFNumberRef)CFArrayGetValueAtIndex(spaces, 0);
            if (first != NULL && CFGetTypeID(first) == CFNumberGetTypeID()) {
                CFNumberGetValue(first, kCFNumberSInt64Type, &space_id);
            }
        }
        CFRelease(spaces);
    }

    CFRelease(window_ids);
    CFRelease(id_number);
    return space_id;
}

bool GLDWIsSpaceCurrent(uint64_t space_id) {
    if (space_id == 0) {
        return false;
    }

    pthread_once(&bridge_init_once, init_bridge_symbols);
    if (fn_main_connection == NULL || fn_copy_display_spaces == NULL) {
        // Without the window manager there is no way to tell, and claiming the
        // Space is elsewhere would trigger a pointless switch.
        return true;
    }

    int connection = fn_main_connection();
    if (connection == 0) {
        return true;
    }

    CFArrayRef display_spaces = fn_copy_display_spaces(connection);
    if (display_spaces == NULL) {
        return true;
    }

    bool is_current = false;
    CFIndex display_count = CFArrayGetCount(display_spaces);
    for (CFIndex i = 0; i < display_count && !is_current; ++i) {
        CFDictionaryRef display = (CFDictionaryRef)CFArrayGetValueAtIndex(display_spaces, i);
        if (display == NULL || CFGetTypeID(display) != CFDictionaryGetTypeID()) continue;
        // Every display shows one Space at a time, so a window is reachable
        // without a switch when its Space is current on any of them.
        if (space_id_of(CFDictionaryGetValue(display, CFSTR("Current Space"))) == space_id) {
            is_current = true;
        }
    }
    CFRelease(display_spaces);
    return is_current;
}

// Whether a Space sits on the display that currently owns the menu bar, which is
// the display the "move one Space left/right" shortcut acts on.
static bool space_is_on_active_display(int connection, uint64_t space_id) {
    if (fn_active_menubar_display == NULL || fn_display_for_space == NULL) {
        // Undecidable, so assume it is: on a single display it always is, and the
        // caller checks that the Space change actually happened either way.
        return true;
    }
    CFStringRef active = fn_active_menubar_display(connection);
    CFStringRef owner = fn_display_for_space(connection, space_id);
    bool same = active != NULL && owner != NULL
        && CFStringCompare(active, owner, 0) == kCFCompareEqualTo;
    if (active != NULL) CFRelease(active);
    if (owner != NULL) CFRelease(owner);
    return same;
}

bool GLDWSpaceWalkSteps(uint64_t space_id, int *steps) {
    if (space_id == 0 || steps == NULL) {
        return false;
    }

    pthread_once(&bridge_init_once, init_bridge_symbols);
    if (fn_main_connection == NULL || fn_copy_display_spaces == NULL) {
        return false;
    }

    int connection = fn_main_connection();
    if (connection == 0 || !space_is_on_active_display(connection, space_id)) {
        return false;
    }

    CFArrayRef display_spaces = fn_copy_display_spaces(connection);
    if (display_spaces == NULL) {
        return false;
    }

    bool resolved = false;
    CFIndex display_count = CFArrayGetCount(display_spaces);
    for (CFIndex i = 0; i < display_count && !resolved; ++i) {
        CFDictionaryRef display = (CFDictionaryRef)CFArrayGetValueAtIndex(display_spaces, i);
        if (display == NULL || CFGetTypeID(display) != CFDictionaryGetTypeID()) continue;
        CFArrayRef list = CFDictionaryGetValue(display, CFSTR("Spaces"));
        if (list == NULL || CFGetTypeID(list) != CFArrayGetTypeID()) continue;

        // This array is in Mission Control order, which is the order the shortcut
        // steps through — full-screen Spaces included, each in the position it
        // occupies on screen.
        uint64_t showing = space_id_of(CFDictionaryGetValue(display, CFSTR("Current Space")));
        CFIndex target_index = -1, current_index = -1;
        CFIndex count = CFArrayGetCount(list);
        for (CFIndex j = 0; j < count; ++j) {
            uint64_t candidate = space_id_of((CFDictionaryRef)CFArrayGetValueAtIndex(list, j));
            if (candidate == space_id) target_index = j;
            if (candidate == showing) current_index = j;
        }
        if (target_index < 0 || current_index < 0) continue;

        *steps = (int)(target_index - current_index);
        resolved = true;
    }
    CFRelease(display_spaces);
    return resolved;
}
