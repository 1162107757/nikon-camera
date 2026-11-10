#import "HueviaTask.h"
@implementation HueviaTask
- (bool)getAsBoolean {return self.cancelled;}
- (void)acceptWithDouble:(double)value {if(self.progress)self.progress(value);}
@end
