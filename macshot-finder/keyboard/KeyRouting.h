#include <stdbool.h>

static inline bool MacshotShouldRouteEnter(bool keyDown, unsigned short keyCode,
                                          bool repeat, bool modified, bool editingText) {
    return keyDown && (keyCode == 36 || keyCode == 76) && !repeat && !modified && !editingText;
}
