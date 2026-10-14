#include <assert.h>
#include <stdio.h>
#include "KeyRouting.h"

int main(void) {
    assert(MacshotShouldRouteEnter(true, 36, false, false, false));
    assert(MacshotShouldRouteEnter(true, 76, false, false, false));
    assert(!MacshotShouldRouteEnter(true, 53, false, false, false));
    assert(!MacshotShouldRouteEnter(true, 0, false, false, false));
    assert(!MacshotShouldRouteEnter(false, 36, false, false, false));
    assert(!MacshotShouldRouteEnter(true, 36, true, false, false));
    assert(!MacshotShouldRouteEnter(true, 36, false, true, false));
    assert(!MacshotShouldRouteEnter(true, 36, false, false, true));
    assert(!MacshotShouldRouteEnter(true, 76, false, false, true));
    puts("9 keyboard routing checks passed");
}
