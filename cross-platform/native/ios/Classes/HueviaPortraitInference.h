#import <Foundation/Foundation.h>
#import "HueviaRaster.h"
#import "HueviaTask.h"
@interface HueviaPortraitInference : NSObject
+ (NSDictionary *)analyze:(NSDictionary *)payload candidates:(NSArray<NSDictionary *> *)faces image:(HueviaRaster *)image task:(HueviaTask *)task;
@end
