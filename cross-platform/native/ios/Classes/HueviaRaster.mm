#import "HueviaRaster.h"
#import "IOSPrimitiveArray.h"
#import "java/io/File.h"
#import "java/io/IOException.h"
#include <sys/mman.h>
#include <sys/statvfs.h>
#include <fcntl.h>
#include <unistd.h>
#include <algorithm>

@implementation HueviaRaster {
  int _descriptor;
  size_t _length;
  NSString *_path;
  NSString *_root;
}
- (instancetype)initWithWidth:(int)width height:(int)height root:(NSString *)root {
  self=[super init];if(!self)return nil;_descriptor=-1;
  if(width<1||height<1||width>65535||height>65535||uint64_t(width)*height>100000000)@throw [[JavaIoIOException alloc] initWithNSString:@"照片表面尺寸超出范围。"];
  NSString *directory=[root stringByAppendingPathComponent:@"raster-tmp"];
  if(![NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:@{NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} error:nil])@throw [[JavaIoIOException alloc] initWithNSString:@"照片暂存目录不可用。"];
  _length=size_t(width)*height*4;struct statvfs space;
  if(statvfs(directory.fileSystemRepresentation,&space)!=0||uint64_t(space.f_bavail)*space.f_frsize<_length+32*1024*1024)@throw [[JavaIoIOException alloc] initWithNSString:@"储存空间不足，无法处理完整照片。"];
  _path=[directory stringByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingString:@".pixels"]];_root=root;
  _descriptor=open(_path.fileSystemRepresentation,O_CREAT|O_EXCL|O_RDWR,0600);
  if(_descriptor<0||ftruncate(_descriptor,off_t(_length))!=0)@throw [[JavaIoIOException alloc] initWithNSString:@"无法创建照片暂存表面。"];
  void *memory=mmap(NULL,_length,PROT_READ|PROT_WRITE,MAP_SHARED,_descriptor,0);
  if(memory==MAP_FAILED)@throw [[JavaIoIOException alloc] initWithNSString:@"无法分配照片表面。"];
  _pixels=static_cast<uint32_t *>(memory);_pixelWidth=width;_pixelHeight=height;_orientation=1;
  return self;
}
- (void)dealloc {if(_pixels)munmap(_pixels,_length);if(_descriptor>=0)close(_descriptor);if(_path)unlink(_path.fileSystemRepresentation);}
- (int32_t)width {return _pixelWidth;}
- (int32_t)height {return _pixelHeight;}
- (int32_t)exifOrientation {return _orientation;}
- (JavaIoFile *)scratchDirectory {return [[JavaIoFile alloc] initWithNSString:[_root stringByAppendingPathComponent:@"adjustment-branches"]];}
- (void)check:(IOSIntArray *)array row:(int)first count:(int)rows {
  if(!array||first<0||rows<0||first>_pixelHeight-rows||int64_t(array->size_)<int64_t(_pixelWidth)*rows)@throw [[JavaIoIOException alloc] initWithNSString:@"照片行缓冲区无效。"];
}
- (void)readWithIntArray:(IOSIntArray *)dest withInt:(int32_t)first withInt:(int32_t)rows {
  [self check:dest row:first count:rows];const uint32_t *input=_pixels+size_t(first)*_pixelWidth;
  for(size_t i=0,n=size_t(rows)*_pixelWidth;i<n;i++){uint32_t p=input[i],a=p>>24;if(a&&a<255){uint32_t r=std::min(255U,(((p>>16)&255)*255+a/2)/a),g=std::min(255U,(((p>>8)&255)*255+a/2)/a),b=std::min(255U,((p&255)*255+a/2)/a);p=a<<24|r<<16|g<<8|b;}dest->buffer_[i]=int32_t(p);}
}
- (void)writeWithIntArray:(IOSIntArray *)source withInt:(int32_t)first withInt:(int32_t)rows {
  [self check:source row:first count:rows];uint32_t *output=_pixels+size_t(first)*_pixelWidth;
  for(size_t i=0,n=size_t(rows)*_pixelWidth;i<n;i++){uint32_t p=uint32_t(source->buffer_[i]),a=p>>24;if(a<255){uint32_t r=(((p>>16)&255)*a+127)/255,g=(((p>>8)&255)*a+127)/255,b=((p&255)*a+127)/255;p=a<<24|r<<16|g<<8|b;}output[i]=p;}
}
- (CGContextRef)newContext {
  CGColorSpaceRef color=CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
  CGContextRef context=CGBitmapContextCreate(_pixels,_pixelWidth,_pixelHeight,8,size_t(_pixelWidth)*4,color,kCGBitmapByteOrder32Little|kCGImageAlphaPremultipliedFirst);CGColorSpaceRelease(color);
  if(!context)@throw [[JavaIoIOException alloc] initWithNSString:@"无法打开 sRGB 照片表面。"];
  return context;
}
static void releaseRaster(void *info,const void *data,size_t size){CFBridgingRelease(info);}
- (CGImageRef)newImage {
  CGDataProviderRef data=CGDataProviderCreateWithData((void *)CFBridgingRetain(self),_pixels,_length,releaseRaster);
  CGColorSpaceRef color=CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
  CGImageRef image=CGImageCreate(_pixelWidth,_pixelHeight,8,32,size_t(_pixelWidth)*4,color,kCGBitmapByteOrder32Little|kCGImageAlphaPremultipliedFirst,data,NULL,true,kCGRenderingIntentDefault);
  CGColorSpaceRelease(color);CGDataProviderRelease(data);
  if(!image)@throw [[JavaIoIOException alloc] initWithNSString:@"无法读取照片表面。"];
  return image;
}
@end
