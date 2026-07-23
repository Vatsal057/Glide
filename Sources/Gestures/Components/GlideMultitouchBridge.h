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

#endif
