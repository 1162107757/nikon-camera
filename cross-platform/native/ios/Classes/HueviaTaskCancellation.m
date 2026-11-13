#import "HueviaTaskCancellation.h"

@implementation HueviaTaskCancellation {
  BOOL _cancelled;
  BOOL _finished;
}
- (BOOL)cancelled { @synchronized(self) { return _cancelled; } }
- (BOOL)cancelIfActive {
  @synchronized(self) {
    if (_finished || _cancelled) return NO;
    _cancelled = YES;
    return YES;
  }
}
- (void)finish { @synchronized(self) { _finished = YES; } }
@end
