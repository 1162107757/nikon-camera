#import <Foundation/Foundation.h>
#import <ImageCaptureCore/ImageCaptureCore.h>
#import "cc/huevia/shared/SharedCamera.h"

/** Device discovery runs on main; shared requests remain on the serial worker. */
@interface HueviaWiredCameras : NSObject <CcHueviaSharedSharedCamera_WiredConnections,ICDeviceBrowserDelegate>
@end
