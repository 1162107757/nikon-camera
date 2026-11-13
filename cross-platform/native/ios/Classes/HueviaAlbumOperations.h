#import <Foundation/Foundation.h>
#import "HueviaTask.h"
@class CcHueviaSharedSharedRuntime;
@interface HueviaAlbumOperations : NSObject
- (instancetype)initWithRoot:(NSString *)root runtime:(CcHueviaSharedSharedRuntime *)runtime;
- (NSDictionary *)request:(NSString *)operation payload:(NSDictionary *)payload task:(HueviaTask *)task;
@end
