#include "GlideWindowServerBridge.h"

#include <CoreGraphics/CoreGraphics.h>
#include <dlfcn.h>
#include <string.h>

typedef struct {
    uint32_t high;
    uint32_t low;
} GLDWProcessSerialNumber;

typedef int32_t (*GLDWGetProcessForPID)(pid_t, GLDWProcessSerialNumber *);
typedef CGError (*GLDWSetFrontProcess)(GLDWProcessSerialNumber *, uint32_t, uint32_t);
typedef CGError (*GLDWPostEventRecord)(GLDWProcessSerialNumber *, uint8_t *);
typedef int (*GLDWMainConnectionID)(void);
typedef CGError (*GLDWGetConnectionIDForPSN)(int, GLDWProcessSerialNumber *, int *);
typedef CFArrayRef (*GLDWCopyManagedDisplaySpaces)(int);
typedef CFArrayRef (*GLDWCopyWindowsWithOptionsAndTags)(int, uint32_t, CFArrayRef, uint32_t, uint64_t *, uint64_t *);

static const char *skylight_path =
    "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight";

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

    void *handle = dlopen(skylight_path, RTLD_LAZY | RTLD_LOCAL);
    if (handle == NULL) {
        return false;
    }

    GLDWGetProcessForPID get_process =
        (GLDWGetProcessForPID)dlsym(RTLD_DEFAULT, "GetProcessForPID");
    GLDWSetFrontProcess set_front =
        (GLDWSetFrontProcess)dlsym(handle, "_SLPSSetFrontProcessWithOptions");
    GLDWPostEventRecord post_event =
        (GLDWPostEventRecord)dlsym(handle, "SLPSPostEventRecordTo");
    if (get_process == NULL || set_front == NULL || post_event == NULL) {
        dlclose(handle);
        return false;
    }

    GLDWProcessSerialNumber process = {0};
    if (get_process(process_id, &process) != 0) {
        dlclose(handle);
        return false;
    }

    // 0x200 marks the request as user-generated and, unlike 0x100, does not raise all windows.
    CGError front = set_front(&process, window_id, 0x200);
    bool made_key = front == kCGErrorSuccess
        && post_key_window_event(post_event, &process, window_id);
    dlclose(handle);
    return made_key;
}

CFArrayRef GLDWCopyWindowIDsForProcess(pid_t process_id) {
    if (process_id <= 0) {
        return NULL;
    }

    void *handle = dlopen(skylight_path, RTLD_LAZY | RTLD_LOCAL);
    if (handle == NULL) {
        return NULL;
    }

    GLDWGetProcessForPID get_process =
        (GLDWGetProcessForPID)dlsym(RTLD_DEFAULT, "GetProcessForPID");
    GLDWMainConnectionID main_connection =
        (GLDWMainConnectionID)dlsym(handle, "SLSMainConnectionID");
    GLDWGetConnectionIDForPSN get_connection =
        (GLDWGetConnectionIDForPSN)dlsym(handle, "SLSGetConnectionIDForPSN");
    GLDWCopyManagedDisplaySpaces copy_display_spaces =
        (GLDWCopyManagedDisplaySpaces)dlsym(handle, "SLSCopyManagedDisplaySpaces");
    GLDWCopyWindowsWithOptionsAndTags copy_windows =
        (GLDWCopyWindowsWithOptionsAndTags)dlsym(handle, "SLSCopyWindowsWithOptionsAndTags");
    if (get_process == NULL || main_connection == NULL || get_connection == NULL
        || copy_display_spaces == NULL || copy_windows == NULL) {
        dlclose(handle);
        return NULL;
    }

    GLDWProcessSerialNumber process = {0};
    if (get_process(process_id, &process) != 0) {
        dlclose(handle);
        return NULL;
    }

    int connection = main_connection();
    int process_connection = 0;
    if (connection == 0 || get_connection(connection, &process, &process_connection) != kCGErrorSuccess
        || process_connection == 0) {
        dlclose(handle);
        return NULL;
    }

    CFArrayRef display_spaces = copy_display_spaces(connection);
    if (display_spaces == NULL) {
        dlclose(handle);
        return NULL;
    }

    CFMutableArrayRef spaces = CFArrayCreateMutable(NULL, 0, &kCFTypeArrayCallBacks);
    CFIndex display_count = CFArrayGetCount(display_spaces);
    for (CFIndex i = 0; i < display_count; ++i) {
        CFDictionaryRef display = (CFDictionaryRef)CFArrayGetValueAtIndex(display_spaces, i);
        if (display == NULL || CFGetTypeID(display) != CFDictionaryGetTypeID()) continue;
        CFArrayRef display_space_list = CFDictionaryGetValue(display, CFSTR("Spaces"));
        if (display_space_list == NULL || CFGetTypeID(display_space_list) != CFArrayGetTypeID()) continue;

        CFIndex space_count = CFArrayGetCount(display_space_list);
        for (CFIndex j = 0; j < space_count; ++j) {
            CFDictionaryRef space = (CFDictionaryRef)CFArrayGetValueAtIndex(display_space_list, j);
            if (space == NULL || CFGetTypeID(space) != CFDictionaryGetTypeID()) continue;
            CFNumberRef space_id = CFDictionaryGetValue(space, CFSTR("id64"));
            if (space_id != NULL && CFGetTypeID(space_id) == CFNumberGetTypeID()) {
                CFArrayAppendValue(spaces, space_id);
            }
        }
    }

    uint64_t set_tags = 0;
    uint64_t clear_tags = 0;
    CFArrayRef windows = NULL;
    if (CFArrayGetCount(spaces) > 0) {
        // 0x7 includes minimized windows as well as ordered-in windows.
        windows = copy_windows(connection, (uint32_t)process_connection, spaces, 0x7, &set_tags, &clear_tags);
    }
    CFRelease(spaces);
    CFRelease(display_spaces);
    dlclose(handle);
    return windows;
}
