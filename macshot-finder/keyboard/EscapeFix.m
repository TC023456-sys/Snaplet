#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import "KeyRouting.h"

// Route Escape through the existing capture cancellation path, even if a
// toolbar/field editor has focus. Each pass unwinds one transient editor state.
static NSView *CaptureView(NSView *view) {
    if ([NSStringFromClass(view.class) isEqualToString:@"macshot.OverlayView"]) return view;
    for (NSView *child in view.subviews) {
        NSView *result = CaptureView(child);
        if (result) return result;
    }
    return nil;
}

@interface NSApplication (MacshotEscapeFix)
- (void)macshot_escape_sendEvent:(NSEvent *)event;
@end

@implementation NSApplication (MacshotEscapeFix)
- (void)macshot_escape_sendEvent:(NSEvent *)event {
    // Nonactivating capture panels can leave physical keyboard input directed
    // at the previously active app. Acquire focus on the first selection click,
    // before normal AppKit dispatch chooses the clicked control's responder.
    if (event.type == NSEventTypeLeftMouseDown && !self.isActive) {
        for (NSWindow *window in self.orderedWindows) {
            if (!window.isVisible || window.ignoresMouseEvents ||
                ![NSStringFromClass(window.class) isEqualToString:@"macshot.OverlayWindow"]) continue;
            NSView *view = CaptureView(window.contentView);
            if (!view) continue;
            [self activateIgnoringOtherApps:YES];
            [window makeKeyWindow];
            [window makeFirstResponder:view];
            break;
        }
    }
    // keyCode/isARepeat are invalid for mouse and application-defined events.
    // Return before evaluating ANY keyboard-only accessor for those events.
    if (event.type != NSEventTypeKeyDown) {
        [self macshot_escape_sendEvent:event];
        return;
    }
    BOOL escape = event.keyCode == 53;
    NSResponder *responder = self.keyWindow.firstResponder;
    BOOL editingText = [responder isKindOfClass:NSTextView.class] && [(NSTextView *)responder isEditable];
    BOOL enter = MacshotShouldRouteEnter(event.type == NSEventTypeKeyDown,
        event.keyCode, event.isARepeat,
        (event.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagOption |
                              NSEventModifierFlagControl | NSEventModifierFlagShift)) != 0,
        editingText);
    // A save panel or other modal dialog owns its Return key.
    if (enter && (self.modalWindow || self.keyWindow.attachedSheet)) enter = NO;
    if (escape || enter) {
        for (NSWindow *window in self.orderedWindows) {
            if (!window.isVisible || window.ignoresMouseEvents ||
                ![NSStringFromClass(window.class) isEqualToString:@"macshot.OverlayWindow"]) continue;
            NSView *view = CaptureView(window.contentView);
            if (!view) continue;
            if (enter) {
                // Toolbar controls can become first responder and swallow Return.
                // Use the existing quick-save path once; it checks selection and
                // text-editing state and respects the user's output preference.
                [view keyDown:event];
                return;
            }
            // Existing keyDown cancels scroll capture, text/popovers/selections,
            // then invokes the same delegate cancellation used by the X button.
            for (NSUInteger pass = 0; pass < 8 && window.isVisible && !window.ignoresMouseEvents; pass++) {
                [view keyDown:event];
            }
            return;
        }
    }
    [self macshot_escape_sendEvent:event];
}
@end

#ifndef MACSHOT_EVENT_TEST
__attribute__((constructor)) static void InstallEscapeFix(void) {
    Method original = class_getInstanceMethod(NSApplication.class, @selector(sendEvent:));
    Method replacement = class_getInstanceMethod(NSApplication.class, @selector(macshot_escape_sendEvent:));
    method_exchangeImplementations(original, replacement);
}
#endif
