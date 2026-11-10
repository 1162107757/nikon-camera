#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import "cc/huevia/ncp/SpatialPreviewFilter.h"

@interface HueviaRaster : NSObject <CcHueviaNcpSpatialPreviewFilter_Pixels>
@property(nonatomic,readonly) int pixelWidth;
@property(nonatomic,readonly) int pixelHeight;
@property(nonatomic,readonly) uint32_t *pixels;
@property(nonatomic) int orientation;
- (instancetype)initWithWidth:(int)width height:(int)height root:(NSString *)root;
- (CGContextRef)newContext CF_RETURNS_RETAINED;
- (CGImageRef)newImage CF_RETURNS_RETAINED;
@end
