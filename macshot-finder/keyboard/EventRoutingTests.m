#define MACSHOT_EVENT_TEST 1
#import "EscapeFix.m"
#include <assert.h>

// Exercise the production handler with genuine NSEvents but no app/window/UI.
@interface FakeApplication : NSObject
@property NSUInteger forwarded;
@property NSArray *testWindows;
@property NSWindow *testModal;
@property BOOL isActive;
@property NSUInteger activationCount;
- (void)activateIgnoringOtherApps:(BOOL)flag;
- (void)macshot_escape_sendEvent:(NSEvent *)event;
- (NSWindow *)keyWindow;
- (NSWindow *)modalWindow;
- (NSArray *)orderedWindows;
@end
@implementation FakeApplication
- (void)macshot_escape_sendEvent:(NSEvent *)event { self.forwarded++; }
- (NSWindow *)keyWindow { return nil; }
- (NSWindow *)modalWindow { return self.testModal; }
- (NSArray *)orderedWindows { return self.testWindows ?: @[]; }
- (void)activateIgnoringOtherApps:(BOOL)flag { self.isActive = YES; self.activationCount++; }
@end

@interface FakeWindow : NSObject
@property BOOL isVisible;
@property BOOL ignoresMouseEvents;
@property NSView *contentView;
@property BOOL becameKey;
@property NSResponder *testResponder;
- (void)makeKeyWindow;
- (BOOL)makeFirstResponder:(NSResponder *)responder;
@end
@implementation FakeWindow
- (void)makeKeyWindow { self.becameKey = YES; }
- (BOOL)makeFirstResponder:(NSResponder *)responder { self.testResponder = responder; return YES; }
@end

@interface FakeOverlay : NSView
@property NSUInteger received;
@property FakeWindow *testWindow;
@end
@implementation FakeOverlay
- (void)keyDown:(NSEvent *)event {
    self.received++;
    self.testWindow.isVisible = NO;
}
@end

int main(void) {
    @autoreleasepool {
        FakeApplication *app = [FakeApplication new];
        IMP handler = class_getMethodImplementation(NSApplication.class,
                                                   @selector(macshot_escape_sendEvent:));
        void (*route)(id, SEL, NSEvent *) = (void *)handler;
        NSUInteger count = 0;
        for (NSNumber *type in @[@(NSEventTypeMouseMoved), @(NSEventTypeLeftMouseDown),
                                 @(NSEventTypeLeftMouseUp), @(NSEventTypeLeftMouseDragged)]) {
            NSEvent *event = [NSEvent mouseEventWithType:type.unsignedIntegerValue
                location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0
                context:nil eventNumber:0 clickCount:1 pressure:0];
            route(app, @selector(sendEvent:), event);
            count++;
        }
        for (NSNumber *key in @[@36, @76, @53, @0]) {
            NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint
                modifierFlags:0 timestamp:0 windowNumber:0 context:nil characters:@""
                charactersIgnoringModifiers:@"" isARepeat:NO keyCode:key.unsignedShortValue];
            route(app, @selector(sendEvent:), event);
            count++;
        }
        NSEvent *other = [NSEvent otherEventWithType:NSEventTypeApplicationDefined
            location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil
            subtype:0 data1:0 data2:0];
        route(app, @selector(sendEvent:), other);
        count++;
        assert(app.forwarded == count);
        puts("9 real NSEvent dispatch tests passed (no exceptions)");
        Class windowClass = objc_allocateClassPair(FakeWindow.class, "macshot.OverlayWindow", 0);
        Class viewClass = objc_allocateClassPair(FakeOverlay.class, "macshot.OverlayView", 0);
        objc_registerClassPair(windowClass);
        objc_registerClassPair(viewClass);
        FakeWindow *window = [windowClass new];
        FakeOverlay *view = [[viewClass alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
        window.contentView = view;
        view.testWindow = window;
        app.testWindows = @[window];
        window.isVisible = YES;
        NSEvent *click = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown
            location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0
            context:nil eventNumber:0 clickCount:1 pressure:0];
        route(app, @selector(sendEvent:), click);
        assert(app.isActive && app.activationCount == 1);
        assert(window.becameKey && window.testResponder == view);
        assert(view.received == 0);
        route(app, @selector(sendEvent:), click);
        assert(app.activationCount == 1);
        puts("4 selection-focus checks passed: activation, key window, responder, no repeated activation");
        for (NSNumber *key in @[@36, @76, @53]) {
            window.isVisible = YES;
            NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint
                modifierFlags:0 timestamp:0 windowNumber:0 context:nil characters:@""
                charactersIgnoringModifiers:@"" isARepeat:NO keyCode:key.unsignedShortValue];
            NSUInteger before = view.received;
            route(app, @selector(sendEvent:), event);
            assert(view.received == before + 1);
            assert(!window.isVisible);
        }
        NSEvent *enter = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint
            modifierFlags:0 timestamp:0 windowNumber:0 context:nil characters:@"\r"
            charactersIgnoringModifiers:@"\r" isARepeat:NO keyCode:36];
        NSUInteger before = view.received;
        window.isVisible = NO;
        route(app, @selector(sendEvent:), enter);
        assert(view.received == before);
        window.isVisible = YES;
        window.ignoresMouseEvents = YES;
        route(app, @selector(sendEvent:), enter);
        assert(view.received == before);
        window.ignoresMouseEvents = NO;
        app.testModal = (NSWindow *)(id)window;
        route(app, @selector(sendEvent:), enter);
        assert(view.received == before);
        puts("6 overlay routing checks passed: Return, numpad Enter, Escape, hidden, warmed, modal");
    }
}
