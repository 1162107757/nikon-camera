#import "HueviaAvatar.h"
#import "HueviaTask.h"
#import <ImageIO/ImageIO.h>
#import "java/io/IOException.h"
#import "java/io/InterruptedIOException.h"
#include <algorithm>

namespace {
void avatarFail(){@throw [[JavaIoIOException alloc] initWithNSString:@"请选择有效图片，原图需小于 20 MB，尺寸至少 64×64。"];
}
void avatarCheck(HueviaTask *task){if(task.cancelled)@throw [[JavaIoInterruptedIOException alloc] initWithNSString:@"头像处理已取消。"];
}
}
@implementation HueviaAvatar
+ (NSData *)prepareFile:(NSString *)path task:(HueviaTask *)task {
  NSDictionary *attributes=[NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
  unsigned long long length=[attributes[NSFileSize] unsignedLongLongValue];
  if(length<4||length>20ULL*1024*1024||![attributes[NSFileType] isEqualToString:NSFileTypeRegular])avatarFail();
  avatarCheck(task);
  CGImageSourceRef source=CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path],(__bridge CFDictionaryRef)@{(__bridge id)kCGImageSourceShouldCache:@NO});
  if(!source)avatarFail();
  CGImageRef thumbnail=NULL,crop=NULL,square=NULL;CGContextRef context=NULL;CGColorSpaceRef colour=NULL;CGImageDestinationRef destination=NULL;
  @try {
    NSDictionary *properties=CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source,0,NULL));
    int w=[properties[(__bridge id)kCGImagePropertyPixelWidth] intValue],h=[properties[(__bridge id)kCGImagePropertyPixelHeight] intValue];
    if(w<64||h<64||w>32768||h>32768||(uint64_t)w*h>128000000)avatarFail();
    // Match the original power-of-two sampling policy before the square crop.
    int sample=1;while(std::max(w,h)/sample>2048)sample*=2;
    int edge=std::max(w,h)/sample;
    thumbnail=CGImageSourceCreateThumbnailAtIndex(source,0,(__bridge CFDictionaryRef)@{(__bridge id)kCGImageSourceCreateThumbnailFromImageAlways:@YES,(__bridge id)kCGImageSourceCreateThumbnailWithTransform:@YES,(__bridge id)kCGImageSourceShouldCacheImmediately:@YES,(__bridge id)kCGImageSourceThumbnailMaxPixelSize:@(edge)});
    if(!thumbnail)avatarFail();avatarCheck(task);
    size_t width=CGImageGetWidth(thumbnail),height=CGImageGetHeight(thumbnail),side=std::min(width,height),size=std::min(size_t(512),std::max(size_t(64),side));
    if(!side)avatarFail();crop=CGImageCreateWithImageInRect(thumbnail,CGRectMake((width-side)/2,(height-side)/2,side,side));if(!crop)avatarFail();
    colour=CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    context=CGBitmapContextCreate(NULL,size,size,8,size*4,colour,kCGBitmapByteOrder32Little|kCGImageAlphaPremultipliedFirst);if(!context)avatarFail();
    CGContextSetRGBFillColor(context,1,1,1,1);CGContextFillRect(context,CGRectMake(0,0,size,size));CGContextSetInterpolationQuality(context,kCGInterpolationHigh);
    CGContextDrawImage(context,CGRectMake(0,0,size,size),crop);square=CGBitmapContextCreateImage(context);if(!square)avatarFail();
    for(int quality=92;quality>=52;quality-=10){
      avatarCheck(task);NSMutableData *jpeg=[NSMutableData data];
      destination=CGImageDestinationCreateWithData((__bridge CFMutableDataRef)jpeg,CFSTR("public.jpeg"),1,NULL);if(!destination)avatarFail();
      CGImageDestinationAddImage(destination,square,(__bridge CFDictionaryRef)@{(__bridge id)kCGImageDestinationLossyCompressionQuality:@(quality/100.0)});
      BOOL encoded=CGImageDestinationFinalize(destination);CFRelease(destination);destination=NULL;if(!encoded)avatarFail();
      if(jpeg.length<=1024*1024)return jpeg;
    }
    avatarFail();return nil;
  }@finally{
    if(destination)CFRelease(destination);if(square)CGImageRelease(square);if(context)CGContextRelease(context);if(colour)CGColorSpaceRelease(colour);if(crop)CGImageRelease(crop);if(thumbnail)CGImageRelease(thumbnail);CFRelease(source);
  }
}
@end
