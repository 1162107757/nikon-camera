#import <Foundation/Foundation.h>

/// A completed invocation cannot own a later camera session's cancellation.
@interface HueviaTaskCancellation : NSObject
@property(nonatomic,readonly) BOOL cancelled;
- (BOOL)cancelIfActive;
- (void)finish;
@end
