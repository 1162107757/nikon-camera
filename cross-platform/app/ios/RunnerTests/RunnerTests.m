@import XCTest;

@interface RunnerTests : XCTestCase
@end

@implementation RunnerTests
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
