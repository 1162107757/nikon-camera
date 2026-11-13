@import XCTest;
@import UIKit;
@import CoreFoundation;

// Compile the production resolver in the UI-test runner too. The application
// has its own process; this local name also avoids any inherited pod collision.
#define HueviaCameraPresentation HueviaCameraPresentationUnderTest
#import "../../../native/ios/Classes/HueviaCameraPresentation.m"
#undef HueviaCameraPresentation
#define HueviaTaskCancellation HueviaTaskCancellationUnderTest
#import "../../../native/ios/Classes/HueviaTaskCancellation.m"
#undef HueviaTaskCancellation

@interface RunnerTests : XCTestCase
@end

@implementation RunnerTests
- (void)cameraOnMain:(dispatch_block_t)body {
  if (NSThread.isMainThread) body();
  else dispatch_sync(dispatch_get_main_queue(), body);
}
- (UIWindow *)cameraWindowWithRoot:(UIViewController *)root {
  UIWindowScene *scene = nil;
  for (UIScene *candidate in UIApplication.sharedApplication.connectedScenes) {
    if ([candidate isKindOfClass:UIWindowScene.class]) { scene = (UIWindowScene *)candidate; break; }
  }
  UIWindow *window = scene ? [[UIWindow alloc] initWithWindowScene:scene] : [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 240, 320)];
  window.frame = CGRectMake(0, 0, 240, 320);
  window.rootViewController = root;
  root.view.frame = window.bounds;
  [window addSubview:root.view];
  window.hidden = NO;
  return window;
}
- (void)testCameraPresenterRecoversFromMissingAndDetachedRegistration {
  [self cameraOnMain:^{
    UIViewController *front = [UIViewController new];
    UIWindow *window = [self cameraWindowWithRoot:front];
    UIViewController *detached = [UIViewController new];
    UIViewController *other = [UIViewController new];
    UIWindow *otherWindow = [self cameraWindowWithRoot:other];
    @try {
      XCTAssertEqual(front.viewIfLoaded.window, window, @"The fixture must have a real UIKit window attachment.");
      XCTAssertNil(detached.viewIfLoaded.window);
      XCTAssertEqual([HueviaCameraPresentationUnderTest presenterInForegroundWindows:@[window] registered:nil applicationForeground:YES], front);
      XCTAssertEqual([HueviaCameraPresentationUnderTest presenterInForegroundWindows:@[window] registered:detached applicationForeground:YES], front);
      // An attached cache belonging to another scene must not override this
      // request's foreground scene/window set.
      XCTAssertEqual(other.viewIfLoaded.window, otherWindow);
      XCTAssertEqual([HueviaCameraPresentationUnderTest presenterInForegroundWindows:@[window] registered:other applicationForeground:YES], front);
      // The UI-test runner need not have an active scene. Every public flag
      // must still be a JSON boolean, rather than a boxed C comparison int.
      NSDictionary *snapshot=[HueviaCameraPresentationUnderTest snapshotWithRegistered:detached];
      NSArray<NSString *> *boolKeys=@[@"snapshotOnMainThread",@"applicationForeground",@"foregroundActive",@"registeredPresenterAttached",@"presenterAvailable"];
      NSError *jsonError=nil;
      NSData *encoded=[NSJSONSerialization dataWithJSONObject:snapshot options:0 error:&jsonError];
      XCTAssertNil(jsonError);XCTAssertNotNil(encoded);
      NSDictionary *decoded=encoded?[NSJSONSerialization JSONObjectWithData:encoded options:0 error:&jsonError]:nil;
      XCTAssertNil(jsonError);XCTAssertNotNil(decoded);
      for(NSString *key in boolKeys){
        id value=snapshot[key],roundTrip=decoded[key];
        XCTAssertNotNil(value);XCTAssertNotNil(roundTrip);
        if(value)XCTAssertEqual(CFGetTypeID((__bridge CFTypeRef)value),CFBooleanGetTypeID(),@"%@ must have the public boolean type",key);
        if(roundTrip)XCTAssertEqual(CFGetTypeID((__bridge CFTypeRef)roundTrip),CFBooleanGetTypeID(),@"%@ must remain boolean after JSON serialization",key);
        XCTAssertEqualObjects(value,roundTrip);
      }
      for(NSString *key in @[@"activeSceneCount",@"eligibleWindowCount"]){
        id value=snapshot[key],roundTrip=decoded[key];
        XCTAssertNotNil(value);XCTAssertNotNil(roundTrip);
        if(value)XCTAssertEqual(CFGetTypeID((__bridge CFTypeRef)value),CFNumberGetTypeID(),@"%@ is a count, not a boolean",key);
        if(roundTrip)XCTAssertEqual(CFGetTypeID((__bridge CFTypeRef)roundTrip),CFNumberGetTypeID());
        XCTAssertGreaterThanOrEqual([value longLongValue],0LL);XCTAssertEqualObjects(value,roundTrip);
      }
    } @finally { window.hidden = YES; otherWindow.hidden = YES; }
  }];
}
- (void)testCameraPresenterRejectsBackgroundAndHiddenWindows {
  [self cameraOnMain:^{
    UIViewController *front = [UIViewController new];
    UIWindow *window = [self cameraWindowWithRoot:front];
    @try {
      XCTAssertNil([HueviaCameraPresentationUnderTest presenterInForegroundWindows:@[window] registered:front applicationForeground:NO]);
      XCTAssertNil([HueviaCameraPresentationUnderTest presenterInForegroundWindows:@[] registered:front applicationForeground:YES]);
      window.hidden = YES;
      XCTAssertNil([HueviaCameraPresentationUnderTest presenterInForegroundWindows:@[window] registered:front applicationForeground:YES]);
      window.hidden = NO; window.alpha = 0;
      XCTAssertNil([HueviaCameraPresentationUnderTest presenterInForegroundWindows:@[window] registered:front applicationForeground:YES]);
      window.alpha = 1; window.windowLevel = UIWindowLevelAlert;
      XCTAssertNil([HueviaCameraPresentationUnderTest presenterInForegroundWindows:@[window] registered:front applicationForeground:YES]);
    } @finally { window.hidden = YES; }
  }];
}
- (void)testCameraPresentationCancellationPreventsQueuedPresentation {
  __block BOOL current = YES;
  __block NSUInteger resolutions = 0, presentations = 0, failures = 0;
  XCTestExpectation *drained = [self expectationWithDescription:@"cancelled camera presentation queue drained"];
  [self cameraOnMain:^{
    [HueviaCameraPresentationUnderTest scheduleWhileCurrent:^BOOL { return current; }
      resolve:^UIViewController * { resolutions++; return [UIViewController new]; }
      present:^(UIViewController *presenter) { presentations++; }
      unavailable:^{ failures++; }];
    current = NO;
    dispatch_async(dispatch_get_main_queue(), ^{ [drained fulfill]; });
  }];
  XCTAssertEqual([XCTWaiter waitForExpectations:@[drained] timeout:5], XCTWaiterResultCompleted);
  XCTAssertEqual(resolutions, 0u); XCTAssertEqual(presentations, 0u); XCTAssertEqual(failures, 0u);

  XCTestExpectation *cancelledDuringResolution = [self expectationWithDescription:@"cancellation during resolution drained"];
  [self cameraOnMain:^{
    current = YES;
    [HueviaCameraPresentationUnderTest scheduleWhileCurrent:^BOOL { return current; }
      resolve:^UIViewController * { resolutions++; current = NO; return [UIViewController new]; }
      present:^(UIViewController *presenter) { presentations++; }
      unavailable:^{ failures++; }];
    dispatch_async(dispatch_get_main_queue(), ^{ [cancelledDuringResolution fulfill]; });
  }];
  XCTAssertEqual([XCTWaiter waitForExpectations:@[cancelledDuringResolution] timeout:5], XCTWaiterResultCompleted);
  XCTAssertEqual(resolutions, 1u); XCTAssertEqual(presentations, 0u); XCTAssertEqual(failures, 0u);

  XCTestExpectation *live = [self expectationWithDescription:@"live camera presentation dispatched"];
  [self cameraOnMain:^{
    current = YES;
    [HueviaCameraPresentationUnderTest scheduleWhileCurrent:^BOOL { return current; }
      resolve:^UIViewController * { return [UIViewController new]; }
      present:^(UIViewController *presenter) { XCTAssertNotNil(presenter); presentations++; [live fulfill]; }
      unavailable:^{ XCTFail(@"A current, resolved presenter must be dispatched."); }];
  }];
  XCTAssertEqual([XCTWaiter waitForExpectations:@[live] timeout:5], XCTWaiterResultCompleted);
  XCTAssertEqual(presentations, 1u);
}
- (void)testNativeTaskCancellationRetiresBeforeDelivery {
  HueviaTaskCancellationUnderTest *active = [HueviaTaskCancellationUnderTest new];
  XCTAssertTrue([active cancelIfActive]);
  XCTAssertTrue(active.cancelled);
  XCTAssertFalse([active cancelIfActive], @"A repeated cancellation must not close a transport twice.");
  [active finish];
  XCTAssertFalse([active cancelIfActive]);
  XCTAssertTrue(active.cancelled, @"Finishing retains the cancellation outcome.");

  HueviaTaskCancellationUnderTest *old = [HueviaTaskCancellationUnderTest new];
  HueviaTaskCancellationUnderTest *replacement = [HueviaTaskCancellationUnderTest new];
  __block NSUInteger closes = 0;
  XCTestExpectation *drained = [self expectationWithDescription:@"late completed job cancellation drained"];
  [self cameraOnMain:^{
    // Native work is already finished while its result is awaiting the UI queue.
    [old finish];
    dispatch_async(dispatch_get_main_queue(), ^{
      if ([old cancelIfActive]) closes++;
      XCTAssertFalse(old.cancelled);
      XCTAssertFalse(replacement.cancelled, @"The next operation cannot be cancelled by an old result.");
      if ([replacement cancelIfActive]) closes++;
      if ([replacement cancelIfActive]) closes++;
      [drained fulfill];
    });
  }];
  XCTAssertEqual([XCTWaiter waitForExpectations:@[drained] timeout:5], XCTWaiterResultCompleted);
  XCTAssertEqual(closes, 1u);

  // Background protection uses this same token. Ending an earlier OS lease
  // must retire its already-queued expiration without affecting a new lease.
  HueviaTaskCancellationUnderTest *oldLease = [HueviaTaskCancellationUnderTest new];
  [oldLease finish];
  HueviaTaskCancellationUnderTest *newLease = [HueviaTaskCancellationUnderTest new];
  XCTAssertFalse([oldLease cancelIfActive]);
  XCTAssertFalse(newLease.cancelled);
  XCTAssertTrue([newLease cancelIfActive], @"The current lease expiration still owns cancellation.");
  XCTAssertFalse([newLease cancelIfActive]);
}
- (void)testPhotoLibraryConsent {
  self.continueAfterFailure = NO;
  self.executionTimeAllowance = 120;
  XCUIApplication *app = [[XCUIApplication alloc] initWithBundleIdentifier:@"cc.huevia.next"];
  [app launch];
  // Exercise the actual iOS consent sheet. A successful simctl TCC write does
  // not establish effective PhotoKit read/write access on every runtime.
  XCUIApplication *system = [[XCUIApplication alloc] initWithBundleIdentifier:@"com.apple.springboard"];
  NSPredicate *fullAccess = [NSPredicate predicateWithFormat:@"label CONTAINS[c] 'Full Access' OR label == 'Allow Access to All Photos'"];
  XCUIElement *allow = [[system.buttons matchingPredicate:fullAccess] firstMatch];
  BOOL presented = [allow waitForExistenceWithTimeout:60];
  if (!presented) NSLog(@"Photos consent UI: %@", system.debugDescription);
  XCTAssertTrue(presented, @"The real full-library permission choice must be presented.");
  [allow tap];
  XCTAssertTrue([app waitForState:XCUIApplicationStateRunningForeground timeout:15], @"The target must remain in the foreground after consent.");
}
@end
