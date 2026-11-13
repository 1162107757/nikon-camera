#import "HueviaTask.h"
#import "HueviaTaskCancellation.h"
#include <math.h>
@implementation HueviaTask {double _lastEmission;double _lastValue;BOOL _emitted;HueviaTaskCancellation *_cancellation;}
- (instancetype)init { if((self=[super init]))_cancellation=[HueviaTaskCancellation new];return self; }
- (BOOL)cancelled {return _cancellation.cancelled;}
- (BOOL)cancelIfActive {return [_cancellation cancelIfActive];}
- (void)finish {[_cancellation finish];}
- (bool)getAsBoolean {return self.cancelled;}
- (id<JavaUtilFunctionDoubleConsumer>)andThenWithJavaUtilFunctionDoubleConsumer:(id<JavaUtilFunctionDoubleConsumer>)after {
  return JavaUtilFunctionDoubleConsumer_andThenWithJavaUtilFunctionDoubleConsumer_(self,after);
}
- (void)acceptWithDouble:(double)value {
  if(!isfinite(value))return;value=fmax(0,fmin(1,value));double now=NSProcessInfo.processInfo.systemUptime;
  if(_emitted&&(value==_lastValue||(value<1&&now-_lastEmission<.06)))return;
  _emitted=YES;_lastEmission=now;_lastValue=value;if(self.progress)self.progress(value);
}
@end
