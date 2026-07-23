#include "GlideMultitouchBridge.h"

#include <dlfcn.h>
#include <math.h>
#include <pthread.h>
#include <stddef.h>

typedef void *MTDeviceRef;

typedef struct {
    float x;
    float y;
} MTPoint;

typedef struct {
    MTPoint position;
    MTPoint velocity;
} MTVector;

// This compatibility layout is deliberately contained in this bridge. The
// Swift runtime sees only GLDTouchPoint and can disable this provider if the
// framework or ABI is unavailable on a future macOS release.
typedef struct {
    int32_t frame;
    int32_t padding;
    double timestamp;
    int32_t identifier;
    int32_t state;
    int32_t finger_id;
    int32_t hand_id;
    MTVector normalized;
    float size;
    int32_t zero1;
    float angle;
    float major_axis;
    float minor_axis;
    MTVector millimeters;
    int32_t zero2[2];
    float unknown;
} MTTouch;

typedef int (*MTContactCallback)(MTDeviceRef, MTTouch *, int32_t, double, int32_t);
typedef MTDeviceRef (*MTDeviceCreateDefaultFunction)(void);
typedef void (*MTRegisterContactFrameCallbackFunction)(MTDeviceRef, MTContactCallback);
typedef void (*MTUnregisterContactFrameCallbackFunction)(MTDeviceRef, MTContactCallback);
typedef void (*MTDeviceStartFunction)(MTDeviceRef, int32_t);
typedef void (*MTDeviceStopFunction)(MTDeviceRef);
typedef void (*MTDeviceReleaseFunction)(MTDeviceRef);

static const char *framework_path =
    "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport";

static pthread_mutex_t state_lock = PTHREAD_MUTEX_INITIALIZER;
static void *framework_handle = NULL;
static MTDeviceRef device = NULL;
static GLDTFrameCallback client_callback = NULL;
static void *client_context = NULL;
static MTUnregisterContactFrameCallbackFunction unregister_callback = NULL;
static MTDeviceStopFunction stop_device = NULL;
static MTDeviceReleaseFunction release_device = NULL;
static bool forwarding_gesture = false;
static double last_forwarded_timestamp = 0;
static int32_t last_forwarded_active_count = 0;
static int32_t last_forwarded_identifiers[32];
static float last_forwarded_x[32];
static float last_forwarded_y[32];
static GLDTStatus last_start_status = GLDTStatusStartFailed;

// MultitouchSupport can deliver substantially faster than the app can display or act on.
// A 60 Hz ceiling preserves one update per display frame and prevents raw input from
// flooding Swift's main actor. Contact-count changes and the final release always pass.
static const double minimum_frame_interval = 1.0 / 60.0;
// Stationary contacts fluctuate slightly even when the fingers are resting. Compare
// against the last delivered positions so genuine slow movement still accumulates.
static const float minimum_position_delta = 0.0015f;

static bool contacts_moved_meaningfully(
    const int32_t *identifiers,
    const float *x,
    const float *y,
    int32_t active_count
) {
    if (active_count != last_forwarded_active_count) {
        return true;
    }
    for (int32_t current_index = 0; current_index < active_count; current_index++) {
        int32_t previous_index = -1;
        for (int32_t candidate = 0; candidate < last_forwarded_active_count; candidate++) {
            if (last_forwarded_identifiers[candidate] == identifiers[current_index]) {
                previous_index = candidate;
                break;
            }
        }
        if (previous_index < 0 ||
            fabsf(x[current_index] - last_forwarded_x[previous_index]) >= minimum_position_delta ||
            fabsf(y[current_index] - last_forwarded_y[previous_index]) >= minimum_position_delta) {
            return true;
        }
    }
    return false;
}

static void remember_forwarded_contacts(
    const int32_t *identifiers,
    const float *x,
    const float *y,
    int32_t active_count
) {
    last_forwarded_active_count = active_count;
    for (int32_t index = 0; index < active_count; index++) {
        last_forwarded_identifiers[index] = identifiers[index];
        last_forwarded_x[index] = x[index];
        last_forwarded_y[index] = y[index];
    }
}

static bool resolve_symbol(void *handle, const char *name, void **result) {
    *result = dlsym(handle, name);
    return *result != NULL;
}

static int contact_frame_callback(
    MTDeviceRef callback_device,
    MTTouch *touches,
    int32_t count,
    double timestamp,
    int32_t frame
) {
    (void)callback_device;
    (void)frame;

    if (count < 0 || count > 32 || (count > 0 && touches == NULL)) {
        return 0;
    }

    int32_t active_count = 0;
    int32_t active_identifiers[32];
    float active_x[32];
    float active_y[32];
    for (int32_t index = 0; index < count; index++) {
        if (touches[index].state == 3 || touches[index].state == 4) {
            active_identifiers[active_count] = touches[index].identifier;
            active_x[active_count] = touches[index].normalized.position.x;
            active_y[active_count] = touches[index].normalized.position.y;
            active_count++;
        }
    }

    pthread_mutex_lock(&state_lock);
    GLDTFrameCallback callback = client_callback;
    void *context = client_context;
    bool should_forward = false;
    if (active_count >= 3) {
        bool started = !forwarding_gesture;
        bool contact_count_changed = active_count != last_forwarded_active_count;
        bool interval_elapsed =
            timestamp <= last_forwarded_timestamp ||
            timestamp - last_forwarded_timestamp >= minimum_frame_interval;
        bool moved = contacts_moved_meaningfully(
            active_identifiers,
            active_x,
            active_y,
            active_count
        );
        forwarding_gesture = true;
        should_forward = started || contact_count_changed || (interval_elapsed && moved);
        if (should_forward) {
            last_forwarded_timestamp = timestamp;
            remember_forwarded_contacts(
                active_identifiers,
                active_x,
                active_y,
                active_count
            );
        }
    } else if (active_count == 0 && forwarding_gesture) {
        forwarding_gesture = false;
        should_forward = true;
        last_forwarded_timestamp = 0;
        last_forwarded_active_count = 0;
    }
    pthread_mutex_unlock(&state_lock);

    if (callback != NULL && should_forward) {
        GLDTouchPoint points[32];
        int32_t output_index = 0;
        for (int32_t index = 0; index < count; index++) {
            if (touches[index].state != 3 && touches[index].state != 4) {
                continue;
            }
            points[output_index].identifier = touches[index].identifier;
            points[output_index].state = touches[index].state;
            points[output_index].x = touches[index].normalized.position.x;
            points[output_index].y = touches[index].normalized.position.y;
            points[output_index].vx = touches[index].normalized.velocity.x;
            points[output_index].vy = touches[index].normalized.velocity.y;
            points[output_index].size = touches[index].size;
            output_index++;
        }
        callback(points, output_index, timestamp, context);
    }
    return 0;
}

GLDTStatus GLDTGetAvailabilityStatus(void) {
    void *handle = dlopen(framework_path, RTLD_LAZY | RTLD_LOCAL);
    if (handle == NULL) {
        return GLDTStatusFrameworkUnavailable;
    }
    bool available =
        dlsym(handle, "MTDeviceCreateDefault") != NULL &&
        dlsym(handle, "MTRegisterContactFrameCallback") != NULL &&
        dlsym(handle, "MTDeviceStart") != NULL &&
        dlsym(handle, "MTDeviceStop") != NULL;
    dlclose(handle);
    return available ? GLDTStatusAvailable : GLDTStatusRequiredSymbolsUnavailable;
}

GLDTStatus GLDTGetLastStartStatus(void) {
    pthread_mutex_lock(&state_lock);
    GLDTStatus status = last_start_status;
    pthread_mutex_unlock(&state_lock);
    return status;
}

bool GLDTIsAvailable(void) {
    return GLDTGetAvailabilityStatus() == GLDTStatusAvailable;
}

bool GLDTStart(GLDTFrameCallback callback, void *context) {
    if (callback == NULL) {
        pthread_mutex_lock(&state_lock);
        last_start_status = GLDTStatusInvalidCallback;
        pthread_mutex_unlock(&state_lock);
        return false;
    }

    pthread_mutex_lock(&state_lock);
    if (device != NULL) {
        client_callback = callback;
        client_context = context;
        forwarding_gesture = false;
        last_forwarded_timestamp = 0;
        last_forwarded_active_count = 0;
        last_start_status = GLDTStatusAvailable;
        pthread_mutex_unlock(&state_lock);
        return true;
    }
    pthread_mutex_unlock(&state_lock);

    void *handle = dlopen(framework_path, RTLD_LAZY | RTLD_LOCAL);
    if (handle == NULL) {
        pthread_mutex_lock(&state_lock);
        last_start_status = GLDTStatusFrameworkUnavailable;
        pthread_mutex_unlock(&state_lock);
        return false;
    }

    MTDeviceCreateDefaultFunction create_device = NULL;
    MTRegisterContactFrameCallbackFunction register_callback = NULL;
    MTDeviceStartFunction start_device = NULL;
    MTUnregisterContactFrameCallbackFunction resolved_unregister = NULL;
    MTDeviceStopFunction resolved_stop = NULL;
    MTDeviceReleaseFunction resolved_release = NULL;

    bool resolved =
        resolve_symbol(handle, "MTDeviceCreateDefault", (void **)&create_device) &&
        resolve_symbol(handle, "MTRegisterContactFrameCallback", (void **)&register_callback) &&
        resolve_symbol(handle, "MTDeviceStart", (void **)&start_device) &&
        resolve_symbol(handle, "MTDeviceStop", (void **)&resolved_stop);
    resolve_symbol(handle, "MTUnregisterContactFrameCallback", (void **)&resolved_unregister);
    resolve_symbol(handle, "MTDeviceRelease", (void **)&resolved_release);

    if (!resolved) {
        dlclose(handle);
        pthread_mutex_lock(&state_lock);
        last_start_status = GLDTStatusRequiredSymbolsUnavailable;
        pthread_mutex_unlock(&state_lock);
        return false;
    }

    MTDeviceRef created_device = create_device();
    if (created_device == NULL) {
        dlclose(handle);
        pthread_mutex_lock(&state_lock);
        last_start_status = GLDTStatusDefaultDeviceUnavailable;
        pthread_mutex_unlock(&state_lock);
        return false;
    }

    pthread_mutex_lock(&state_lock);
    framework_handle = handle;
    device = created_device;
    client_callback = callback;
    client_context = context;
    forwarding_gesture = false;
    last_forwarded_timestamp = 0;
    last_forwarded_active_count = 0;
    unregister_callback = resolved_unregister;
    stop_device = resolved_stop;
    release_device = resolved_release;
    last_start_status = GLDTStatusAvailable;
    pthread_mutex_unlock(&state_lock);

    register_callback(created_device, contact_frame_callback);
    start_device(created_device, 0);
    return true;
}

void GLDTStop(void) {
    pthread_mutex_lock(&state_lock);
    MTDeviceRef current_device = device;
    void *current_handle = framework_handle;
    MTUnregisterContactFrameCallbackFunction current_unregister = unregister_callback;
    MTDeviceStopFunction current_stop = stop_device;
    MTDeviceReleaseFunction current_release = release_device;

    client_callback = NULL;
    client_context = NULL;
    forwarding_gesture = false;
    last_forwarded_timestamp = 0;
    last_forwarded_active_count = 0;
    device = NULL;
    framework_handle = NULL;
    unregister_callback = NULL;
    stop_device = NULL;
    release_device = NULL;
    pthread_mutex_unlock(&state_lock);

    if (current_device != NULL) {
        if (current_unregister != NULL) {
            current_unregister(current_device, contact_frame_callback);
        }
        if (current_stop != NULL) {
            current_stop(current_device);
        }
        if (current_release != NULL) {
            current_release(current_device);
        }
    }
    if (current_handle != NULL) {
        dlclose(current_handle);
    }
}
