#import "HueviaCameraPresentation.h"

static BOOL cameraWindowVisible(UIWindow *window) {
  return !window.hidden && window.alpha > 0 && window.windowLevel == UIWindowLevelNormal &&
      !CGRectIsEmpty(window.bounds) && window.rootViewController != nil;
}

static NSArray<UIWindow *> *cameraForegroundWindows(NSUInteger *sceneCount) {
  NSCAssert(NSThread.isMainThread, @"Camera presentation must inspect UIKit on the main thread.");
  NSMutableArray<UIWindow *> *windows = [NSMutableArray array];
  NSUInteger count = 0;
  for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
    if (![scene isKindOfClass:UIWindowScene.class] ||
        scene.activationState != UISceneActivationStateForegroundActive) continue;
    count++;
    for (UIWindow *window in ((UIWindowScene *)scene).windows) {
      if (cameraWindowVisible(window)) [windows addObject:window];
    }
  }
  if (sceneCount) *sceneCount = count;
  return windows;
}

@implementation HueviaCameraPresentation
+ (UIViewController *)presenterInForegroundWindows:(NSArray<UIWindow *> *)windows
                                        registered:(UIViewController *)registered
                             applicationForeground:(BOOL)foreground {
  NSAssert(NSThread.isMainThread, @"Camera presentation must inspect UIKit on the main thread.");
  if (!foreground) return nil;
  UIWindow *registeredWindow = registered.viewIfLoaded.window;
  UIWindow *selected = nil;
  if (registeredWindow.isKeyWindow && [windows containsObject:registeredWindow] && cameraWindowVisible(registeredWindow)) {
    selected = registeredWindow;
  }
  if (!selected) for (UIWindow *window in windows) {
    if (cameraWindowVisible(window) && window.isKeyWindow) { selected = window; break; }
  }
  if (!selected && registeredWindow && [windows containsObject:registeredWindow] && cameraWindowVisible(registeredWindow)) {
    selected = registeredWindow;
  }
  if (!selected) for (UIWindow *window in windows) {
    if (cameraWindowVisible(window)) { selected = window; break; }
  }
  if (!selected) return nil;
  UIViewController *controller = selected.rootViewController;
  for (NSUInteger depth = 0; controller && depth < 32; depth++) {
    UIViewController *next = controller.presentedViewController;
    if (next) {
      if (next.isBeingDismissed) return nil;
      controller = next;
      continue;
    }
    if ([controller isKindOfClass:UINavigationController.class]) {
      next = ((UINavigationController *)controller).visibleViewController;
    } else if ([controller isKindOfClass:UITabBarController.class]) {
      next = ((UITabBarController *)controller).selectedViewController;
    }
    if (!next || next == controller) break;
    controller = next;
  }
  if (controller.isBeingDismissed || controller.isBeingPresented ||
      controller.viewIfLoaded.window != selected) return nil;
  return controller;
}

+ (UIViewController *)presenterWithRegistered:(UIViewController *)registered {
  NSUInteger count = 0;
  NSArray<UIWindow *> *windows = cameraForegroundWindows(&count);
  return [self presenterInForegroundWindows:windows registered:registered
                     applicationForeground:count > 0 && UIApplication.sharedApplication.applicationState != UIApplicationStateBackground];
}

+ (NSDictionary<NSString *,id> *)snapshotWithRegistered:(UIViewController *)registered {
  NSUInteger count = 0;
  NSArray<UIWindow *> *windows = cameraForegroundWindows(&count);
  BOOL applicationForeground = UIApplication.sharedApplication.applicationState != UIApplicationStateBackground;
  BOOL foreground = applicationForeground && count > 0;
  UIViewController *presenter = [self presenterInForegroundWindows:windows registered:registered applicationForeground:foreground];
  return @{@"snapshotOnMainThread":@YES, @"applicationForeground":@(applicationForeground),
           @"foregroundActive":@(foreground), @"activeSceneCount":@(count),
           @"eligibleWindowCount":@(windows.count),
           @"registeredPresenterAttached":(registered.viewIfLoaded.window != nil && [windows containsObject:registered.viewIfLoaded.window] ? @YES : @NO),
           @"presenterAvailable":(presenter != nil ? @YES : @NO)};
}

+ (void)scheduleWhileCurrent:(BOOL (^)(void))isCurrent
                     resolve:(UIViewController * _Nullable (^)(void))resolve
                     present:(void (^)(UIViewController *))present
                 unavailable:(dispatch_block_t)unavailable {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (!isCurrent()) return;
    UIViewController *presenter = resolve();
    if (!isCurrent()) return;
    if (presenter) present(presenter);
    else unavailable();
  });
}
@end
