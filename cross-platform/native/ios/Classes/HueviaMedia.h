#import <Foundation/Foundation.h>
#import "HueviaTask.h"
#import "cc/huevia/shared/SharedRuntime.h"
#import "cc/huevia/shared/MediaValidation.h"

@interface HueviaImageValidator : NSObject <CcHueviaSharedMediaValidation_Decoder>
@end
@interface HueviaMedia : NSObject
- (instancetype)initWithRuntime:(CcHueviaSharedSharedRuntime *)runtime root:(NSString *)root;
- (NSDictionary *)request:(NSString *)operation payload:(NSString *)payload task:(HueviaTask *)task;
@end
