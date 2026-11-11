@import XCTest;
@import integration_test;

@interface RunnerTests : XCTestCase
@end

@implementation RunnerTests
- (void)testNativePipeline {
  self.executionTimeAllowance = 360;
  __block NSUInteger completed = 0;
  FLTIntegrationTestRunner *runner = [[FLTIntegrationTestRunner alloc] init];
  [runner testIntegrationTestWithResults:^(SEL selector, BOOL success, NSString *failure) {
    completed++;
    NSLog(@"Huevia native pipeline result: %@ %@", NSStringFromSelector(selector), success ? @"PASS" : @"FAIL");
    XCTAssertTrue(success, @"%@", failure ?: @"Dart native pipeline failed");
  }];
  XCTAssertEqual(completed, (NSUInteger)1, @"The complete Dart pipeline must report one scenario.");
}
@end
