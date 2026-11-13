#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Resolves UIKit at request time; plugin registration may precede scene attachment.
@interface HueviaCameraPresentation : NSObject
+ (nullable UIViewController *)presenterWithRegistered:(nullable UIViewController *)registered;
+ (NSDictionary<NSString *, id> *)snapshotWithRegistered:(nullable UIViewController *)registered;
/// The caller supplies only windows from currently foreground-active scenes.
+ (nullable UIViewController *)presenterInForegroundWindows:(NSArray<UIWindow *> *)windows
                                                registered:(nullable UIViewController *)registered
                                     applicationForeground:(BOOL)foreground;
/// The request must be registered before scheduling. Cancellation invalidates isCurrent.
+ (void)scheduleWhileCurrent:(BOOL (^)(void))isCurrent
                     resolve:(UIViewController * _Nullable (^)(void))resolve
                     present:(void (^)(UIViewController *presenter))present
                 unavailable:(dispatch_block_t)unavailable;
@end

NS_ASSUME_NONNULL_END
