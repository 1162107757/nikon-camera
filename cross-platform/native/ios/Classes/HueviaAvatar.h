#import <Foundation/Foundation.h>
@class HueviaTask;
@interface HueviaAvatar : NSObject
+ (NSData *)prepareFile:(NSString *)path task:(HueviaTask *)task;
@end
