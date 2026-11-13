#import <Foundation/Foundation.h>
#import "HueviaTask.h"
#import "HueviaRaster.h"
@interface HueviaRetouch : NSObject
+ (NSDictionary *)request:(NSString *)operation payload:(NSDictionary *)payload image:(HueviaRaster *)image task:(HueviaTask *)task;
@end
