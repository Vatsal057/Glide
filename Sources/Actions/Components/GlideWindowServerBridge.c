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
typedef CGError (*GLDWGetConnectionIDForPSN)(int, GLDWProcessSerialNumber *, int *);
typedef CFArrayRef (*GLDWCopyManagedDisplaySpaces)(int);
typedef CFArrayRef (*GLDWCopyWindowsWithOptionsAndTags)(int, uint32_t, CFArrayRef, uint32_t, uint64_t *, uint64_t *);

static const char *skylight_path =
    "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight";

static GLDWGetProcessForPID fn_get_process = NULL;
static GLDWSetFrontProcess fn_set_front = NULL;
static GLDWPostEventRecord fn_post_event = NULL;
static GLDWMainConnectionID fn_main_connection = NULL;
static GLDWGetConnectionIDForPSN fn_get_connection = NULL;
static GLDWCopyManagedDisplaySpaces fn_copy_display_spaces = NULL;
static GLDWCopyWindowsWithOptionsAndTags fn_copy_windows = NULL;

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
    fn_get_connection = (GLDWGetConnectionIDForPSN)dlsym(handle, "SLSGetConnectionIDForPSN");
    fn_copy_display_spaces = (GLDWCopyManagedDisplaySpaces)dlsym(handle, "SLSCopyManagedDisplaySpaces");
    fn_copy_windows = (GLDWCopyWindowsWithOptionsAndTags)dlsym(handle, "SLSCopyWindowsWithOptionsAndTags");
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

CFArrayRef GLDWCopyWindowIDsForProcess(pid_t process_id) {
    if (process_id <= 0) {
        return NULL;
    }

    pthread_once(&bridge_init_once, init_bridge_symbols);
    if (fn_get_process == NULL || fn_main_connection == NULL || fn_get_connection == NULL
        || fn_copy_display_spaces == NULL || fn_copy_windows == NULL) {
        return NULL;
    }

    GLDWProcessSerialNumber process = {0};
    if (fn_get_process(process_id, &process) != 0) {
        return NULL;
    }

    int connection = fn_main_connection();
    int process_connection = 0;
    if (connection == 0 || fn_get_connection(connection, &process, &process_connection) != kCGErrorSuccess
        || process_connection == 0) {
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
        windows = fn_copy_windows(connection, (uint32_t)process_connection, spaces, 0x7, &set_tags, &clear_tags);
    }
    CFRelease(spaces);
    CFRelease(display_spaces);
    return windows;
}

