#import "HueviaRaster.h"
#import "HueviaTask.h"
#import "cc/huevia/ncp/PhotoBorder.h"
#import "cc/huevia/shared/SharedCaptureInfo.h"

@interface HueviaFrames : NSObject
+ (HueviaRaster *)apply:(HueviaRaster *)photo border:(CcHueviaNcpPhotoBorder *)border capture:(CcHueviaSharedSharedCaptureInfo *)capture root:(NSString *)root task:(HueviaTask *)task;
@end
