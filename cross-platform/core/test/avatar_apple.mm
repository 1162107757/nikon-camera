#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#import <CoreGraphics/CoreGraphics.h>
#import "HueviaAvatar.h"
#import "HueviaTask.h"
#import "java/io/IOException.h"
#import "java/io/InterruptedIOException.h"

namespace {
int checks = 0;
void check(BOOL value, NSString *message) {
  if (!value) @throw [NSException exceptionWithName:@"AvatarCheck" reason:message userInfo:nil];
  checks++;
}
CGImageRef fixture(size_t width, size_t height, BOOL transparent) {
  NSMutableData *data = [NSMutableData dataWithLength:width * height * 4];
  unsigned char *bytes = (unsigned char *)data.mutableBytes;
  const unsigned char colors[4][3] = {{240,20,20},{20,220,20},{20,20,240},{240,220,20}};
  for (size_t y=0; y<height; y++) for (size_t x=0; x<width; x++) {
    size_t offset=(y*width+x)*4, quadrant=(y>=height/2?2:0)+(x>=width/2?1:0);
    for (int c=0;c<3;c++) bytes[offset+c]=transparent?0:colors[quadrant][c];
    bytes[offset+3]=transparent?0:255;
  }
  CGColorSpaceRef color=CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
  CGDataProviderRef provider=CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
  CGImageRef image=CGImageCreate(width,height,8,32,width*4,color,(CGBitmapInfo)(kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big),provider,NULL,false,kCGRenderingIntentDefault);
  CGDataProviderRelease(provider);CGColorSpaceRelease(color);return image;
}
NSData *encode(CGImageRef image, NSString *type, NSDictionary *properties) {
  NSMutableData *data=[NSMutableData data];
  CGImageDestinationRef destination=CGImageDestinationCreateWithData((__bridge CFMutableDataRef)data,(__bridge CFStringRef)type,1,NULL);
  CGImageDestinationAddImage(destination,image,(__bridge CFDictionaryRef)properties);
  BOOL success=CGImageDestinationFinalize(destination);CFRelease(destination);
  if(!success)@throw [NSException exceptionWithName:@"Fixture" reason:@"Cannot encode owned avatar fixture" userInfo:nil];
  return data;
}
NSData *pixels(CGImageRef image) {
  size_t width=CGImageGetWidth(image),height=CGImageGetHeight(image);
  NSMutableData *data=[NSMutableData dataWithLength:width*height*4];
  CGColorSpaceRef color=CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
  CGContextRef context=CGBitmapContextCreate(data.mutableBytes,width,height,8,width*4,color,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);
  CGContextDrawImage(context,CGRectMake(0,0,width,height),image);
  CGContextRelease(context);CGColorSpaceRelease(color);return data;
}
int quadrantColor(const unsigned char *p) {
  if(p[0]>180&&p[1]<80&&p[2]<80)return 0;
  if(p[0]<80&&p[1]>160&&p[2]<80)return 1;
  if(p[0]<80&&p[1]<80&&p[2]>180)return 2;
  if(p[0]>180&&p[1]>160&&p[2]<80)return 3;
  return -1;
}
}

int main(void) {@autoreleasepool {
  NSString *root=[NSTemporaryDirectory() stringByAppendingPathComponent:[@"huevia-avatar-" stringByAppendingString:NSUUID.UUID.UUIDString]];
  [NSFileManager.defaultManager createDirectoryAtPath:root withIntermediateDirectories:NO attributes:nil error:nil];
  int result=0;
  @try {
    CGImageRef original=fixture(800,600,NO);
    const int expected[8][4]={{0,1,2,3},{1,0,3,2},{3,2,1,0},{2,3,0,1},{0,2,1,3},{2,0,3,1},{3,1,2,0},{1,3,0,2}};
    for(int orientation=1;orientation<=8;orientation++) {
      NSDictionary *metadata=@{(__bridge id)kCGImagePropertyOrientation:@(orientation),
        (__bridge id)kCGImagePropertyTIFFDictionary:@{(__bridge id)kCGImagePropertyTIFFMake:@"Private camera",(__bridge id)kCGImagePropertyTIFFModel:@"Private model"},
        (__bridge id)kCGImagePropertyExifDictionary:@{(__bridge id)kCGImagePropertyExifDateTimeOriginal:@"2020:01:02 03:04:05"},
        (__bridge id)kCGImagePropertyGPSDictionary:@{(__bridge id)kCGImagePropertyGPSLatitude:@31.2,(__bridge id)kCGImagePropertyGPSLatitudeRef:@"N"}};
      NSData *input=encode(original,@"public.jpeg",metadata);
      NSString *path=[root stringByAppendingPathComponent:[NSString stringWithFormat:@"orientation-%d.jpg",orientation]];
      [input writeToFile:path atomically:YES];
      NSData *jpeg=[HueviaAvatar prepareFile:path task:[[HueviaTask alloc] init]];
      CGImageSourceRef source=CGImageSourceCreateWithData((__bridge CFDataRef)jpeg,NULL);
      CGImageRef image=source?CGImageSourceCreateImageAtIndex(source,0,NULL):NULL;
      check(image&&CGImageGetWidth(image)==512&&CGImageGetHeight(image)==512&&jpeg.length<=1024*1024,@"Avatar must be a bounded 512px square JPEG");
      NSDictionary *properties=CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source,0,NULL));
      NSDictionary *tiff=properties[(__bridge id)kCGImagePropertyTIFFDictionary],*exif=properties[(__bridge id)kCGImagePropertyExifDictionary];
      int marker=[properties[(__bridge id)kCGImagePropertyOrientation] intValue];
      check(marker<=1&&!properties[(__bridge id)kCGImagePropertyGPSDictionary]&&!tiff[(__bridge id)kCGImagePropertyTIFFMake]&&!tiff[(__bridge id)kCGImagePropertyTIFFModel]&&!exif[(__bridge id)kCGImagePropertyExifDateTimeOriginal],@"Avatar must remove source metadata and normalize orientation");
      NSData *rgba=pixels(image);const unsigned char *bytes=(const unsigned char *)rgba.bytes;BOOL matches=YES;NSMutableArray *observed=[NSMutableArray array];
      for(int q=0;q<4;q++){size_t x=q%2?384:128,y=q/2?384:128;int actual=quadrantColor(bytes+(y*512+x)*4);[observed addObject:@(actual)];matches &= actual==expected[orientation-1][q];}
      check(matches,[NSString stringWithFormat:@"EXIF %d quadrants %@ must match [%d,%d,%d,%d]",orientation,observed,expected[orientation-1][0],expected[orientation-1][1],expected[orientation-1][2],expected[orientation-1][3]]);
      check([[NSData dataWithContentsOfFile:path] isEqualToData:input],@"Avatar preparation must preserve the original bytes");
      CGImageRelease(image);CFRelease(source);
    }
    CGImageRelease(original);
    NSString *path=[root stringByAppendingPathComponent:@"tiny.png"];
    CGImageRef tiny=fixture(63,64,NO);[encode(tiny,@"public.png",@{}) writeToFile:path atomically:YES];CGImageRelease(tiny);
    BOOL refused=NO;@try{[HueviaAvatar prepareFile:path task:[[HueviaTask alloc] init]];}@catch(JavaIoIOException *failure){refused=YES;}
    check(refused,@"A source below 64 pixels must be rejected");
    HueviaTask *cancelled=[[HueviaTask alloc] init];cancelled.cancelled=YES;refused=NO;
    @try{[HueviaAvatar prepareFile:path task:cancelled];}@catch(JavaIoInterruptedIOException *failure){refused=YES;}
    check(refused,@"Cancelled avatar work must stop before decoding");
    path=[root stringByAppendingPathComponent:@"transparent.png"];
    CGImageRef transparent=fixture(128,128,YES);[encode(transparent,@"public.png",@{}) writeToFile:path atomically:YES];CGImageRelease(transparent);
    NSData *jpeg=[HueviaAvatar prepareFile:path task:[[HueviaTask alloc] init]];
    CGImageSourceRef source=CGImageSourceCreateWithData((__bridge CFDataRef)jpeg,NULL);CGImageRef image=CGImageSourceCreateImageAtIndex(source,0,NULL);
    NSData *rgba=pixels(image);const unsigned char *p=(const unsigned char *)rgba.bytes+(64*128+64)*4;
    check(p[0]>245&&p[1]>245&&p[2]>245,@"Transparent pixels must flatten onto the original white background");
    CGImageRelease(image);CFRelease(source);
    path=[root stringByAppendingPathComponent:@"empty.jpg"];[[NSData data] writeToFile:path atomically:YES];refused=NO;
    @try{[HueviaAvatar prepareFile:path task:[[HueviaTask alloc] init]];}@catch(JavaIoIOException *failure){refused=YES;}
    check(refused,@"An empty avatar source must be rejected");
    printf("PASS %d Apple native avatar checks; eight EXIF transforms, dimensions, metadata, unchanged source, cancellation and white background\n",checks);
  } @catch(id failure) {NSLog(@"Avatar verification failed: %@",failure);result=1;}
  @finally {[NSFileManager.defaultManager removeItemAtPath:root error:nil];}
  return result;
}}
