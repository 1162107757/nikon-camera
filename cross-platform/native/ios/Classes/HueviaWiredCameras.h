#import <Foundation/Foundation.h>
#import <ImageCaptureCore/ImageCaptureCore.h>
#import "cc/huevia/shared/SharedCamera.h"
#import "cc/huevia/shared/SharedSlots.h"
#import "java/util/function/BooleanSupplier.h"

/** Device discovery runs on main; shared requests remain on the serial worker. */
@interface HueviaWiredCameras : NSObject <CcHueviaSharedSharedCamera_WiredConnections,ICDeviceBrowserDelegate>
- (void)prepareRequestWithCancellation:(id<JavaUtilFunctionBooleanSupplier>)cancel;
@end
