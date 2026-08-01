#ifndef GLIDE_MULTITOUCH_BRIDGE_H
#define GLIDE_MULTITOUCH_BRIDGE_H

#include <stdbool.h>
#include <stdint.h>

typedef struct {
    int32_t identifier;
    int32_t state;
    float x;
    float y;
    float vx;
    float vy;
    float size;
} GLDTouchPoint;

typedef void (*GLDTFrameCallback)(
    const GLDTouchPoint *points,
    int32_t count,
    double timestamp,
    void *context
);

typedef int32_t GLDTStatus;
enum {
    GLDTStatusAvailable = 0,
    GLDTStatusInvalidCallback = 1,
    GLDTStatusFrameworkUnavailable = 2,
    GLDTStatusRequiredSymbolsUnavailable = 3,
    GLDTStatusDefaultDeviceUnavailable = 4,
    GLDTStatusStartFailed = 5
};

GLDTStatus GLDTGetAvailabilityStatus(void);
GLDTStatus GLDTGetLastStartStatus(void);
bool GLDTIsAvailable(void);
bool GLDTStart(GLDTFrameCallback callback, void *context);
void GLDTStop(void);

/// Fewest simultaneous contacts a frame must carry to be forwarded to Swift.
/// Defaults to 3 — the floor for every gesture rule — which keeps one- and
/// two-finger cursor work entirely out of the app. Features that need sparser
/// contact (the corner TrackPoint reads a single finger) lower it to 1 while
/// they are enabled. Clamped to 1...32; safe to call from any thread.
void GLDTSetMinimumContactCount(int32_t count);

#endif
