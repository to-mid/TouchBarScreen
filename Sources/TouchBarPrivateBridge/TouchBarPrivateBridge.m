#import "TouchBarPrivateBridge.h"
#import <objc/message.h>

BOOL TBPresentSystemModalTouchBar(
    NSTouchBar *touchBar
) {
    Class touchBarClass = [NSTouchBar class];
    NSArray<NSString *> *selectorsWithPlacement = @[
        @"presentSystemModalTouchBar:placement:systemTrayItemIdentifier:",
        @"presentSystemModalFunctionBar:placement:systemTrayItemIdentifier:"
    ];

    for (NSString *selectorName in selectorsWithPlacement) {
        SEL selector = NSSelectorFromString(selectorName);
        if ([touchBarClass respondsToSelector:selector]) {
            ((void (*)(id, SEL, id, long long, id))objc_msgSend)(
                touchBarClass,
                selector,
                touchBar,
                0,
                nil
            );
            return YES;
        }
    }

    NSArray<NSString *> *selectors = @[
        @"presentSystemModalTouchBar:systemTrayItemIdentifier:",
        @"presentSystemModalFunctionBar:systemTrayItemIdentifier:"
    ];

    for (NSString *selectorName in selectors) {
        SEL selector = NSSelectorFromString(selectorName);
        if ([touchBarClass respondsToSelector:selector]) {
            ((void (*)(id, SEL, id, id))objc_msgSend)(
                touchBarClass,
                selector,
                touchBar,
                nil
            );
            return YES;
        }
    }

    return NO;
}

void TBDismissSystemModalTouchBar(NSTouchBar *touchBar) {
    Class touchBarClass = [NSTouchBar class];
    NSArray<NSString *> *selectors = @[
        @"dismissSystemModalTouchBar:",
        @"dismissSystemModalFunctionBar:"
    ];

    for (NSString *selectorName in selectors) {
        SEL selector = NSSelectorFromString(selectorName);
        if ([touchBarClass respondsToSelector:selector]) {
            ((void (*)(id, SEL, id))objc_msgSend)(
                touchBarClass,
                selector,
                touchBar
            );
            return;
        }
    }
}
