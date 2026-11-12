#import <Foundation/Foundation.h>
#import "HueviaTask.h"
@class CcHueviaSharedSharedRuntime;

@interface HueviaPublication : NSObject
- (instancetype)initWithRoot:(NSString *)root runtime:(CcHueviaSharedSharedRuntime *)runtime;
+ (NSDictionary *)saveAccess;
+ (void)requestSavePermission:(void (^)(NSDictionary *result))reply;
- (NSDictionary *)publish:(NSDictionary *)parameters task:(HueviaTask *)task;
- (NSDictionary *)publishOriginal:(NSDictionary *)parameters task:(HueviaTask *)task;
@end
