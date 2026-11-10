#import "HueviaTask.h"
#include <math.h>
@implementation HueviaTask {double _lastEmission;double _lastValue;BOOL _emitted;}
- (bool)getAsBoolean {return self.cancelled;}
- (void)acceptWithDouble:(double)value {
  if(!isfinite(value))return;value=fmax(0,fmin(1,value));double now=NSProcessInfo.processInfo.systemUptime;
  if(_emitted&&(value==_lastValue||(value<1&&now-_lastEmission<.06)))return;
  _emitted=YES;_lastEmission=now;_lastValue=value;if(self.progress)self.progress(value);
}
@end
