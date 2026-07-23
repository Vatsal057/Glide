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
