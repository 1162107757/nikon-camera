#import "HueviaMedia.h"
#import "HueviaRaster.h"
#import "HueviaRaw.h"
#import "HueviaFrames.h"
#import <ImageIO/ImageIO.h>
#import <CommonCrypto/CommonDigest.h>
#import "cc/huevia/shared/SharedRecipe.h"
#import "cc/huevia/shared/SharedCaptureInfo.h"
#import "cc/huevia/shared/SharedRawSettings.h"
#import "cc/huevia/ncp/RawDevelopmentSettings.h"
#import "cc/huevia/ncp/PhotoGeometry.h"
#import "cc/huevia/ncp/PhotoBorder.h"
#import "cc/huevia/ncp/PresetPreviewProfile.h"
#import "cc/huevia/ncp/RawJpegColorMatch.h"
#import "cc/huevia/album/PhotoExportSpec.h"
#import "cc/huevia/album/PhotoEditStore.h"
#import "java/io/File.h"
#import "java/io/IOException.h"
#import "java/io/InterruptedIOException.h"
#import "IOSPrimitiveArray.h"
#include <algorithm>
#include <cmath>

namespace {
void fail(NSString *message){@throw [[JavaIoIOException alloc] initWithNSString:message];}
void check(HueviaTask *task){if(task.cancelled)@throw [[JavaIoInterruptedIOException alloc] initWithNSString:@"照片处理已取消。"] ;}
NSString *json(id value){NSData *data=[NSJSONSerialization dataWithJSONObject:value options:0 error:nil];if(!data)fail(@"照片设置数据无效。");return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];}
NSDictionary *properties(NSString *path){CGImageSourceRef source=CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path],(__bridge CFDictionaryRef)@{(__bridge id)kCGImageSourceShouldCache:@NO});if(!source)return @{};NSDictionary *value=CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source,0,NULL));CFRelease(source);return value?:@{};}
BOOL isRaw(NSString *path){return [@[@"nef",@"nrw",@"dng",@"arw",@"cr2",@"cr3",@"raf",@"rw2",@"orf",@"pef",@"srw"] containsObject:path.pathExtension.lowercaseString];}
void validSize(int w,int h,uint64_t limit=60000000){if(w<1||h<1||w>65535||h>65535||uint64_t(w)*h>limit)fail(@"照片尺寸无效或超过处理上限。");}
HueviaRaster *decode(CGImageSourceRef source,NSString *root,int edge){
  if(!source)fail(@"无法打开照片。");NSDictionary *props=CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source,0,NULL));int w=[props[(__bridge id)kCGImagePropertyPixelWidth] intValue],h=[props[(__bridge id)kCGImagePropertyPixelHeight] intValue];validSize(w,h);
  CGImageRef image;
  if(edge>0)image=CGImageSourceCreateThumbnailAtIndex(source,0,(__bridge CFDictionaryRef)@{(__bridge id)kCGImageSourceCreateThumbnailFromImageAlways:@YES,(__bridge id)kCGImageSourceCreateThumbnailWithTransform:@NO,(__bridge id)kCGImageSourceShouldCacheImmediately:@YES,(__bridge id)kCGImageSourceThumbnailMaxPixelSize:@(edge)});
  else image=CGImageSourceCreateImageAtIndex(source,0,(__bridge CFDictionaryRef)@{(__bridge id)kCGImageSourceShouldCacheImmediately:@YES});
  if(!image)fail(@"无法解码照片。");
  HueviaRaster *raster;
  @try {raster=[[HueviaRaster alloc] initWithWidth:int(CGImageGetWidth(image)) height:int(CGImageGetHeight(image)) root:root];raster.orientation=std::clamp([props[(__bridge id)kCGImagePropertyOrientation] intValue],1,8);CGContextRef context=[raster newContext];CGContextDrawImage(context,CGRectMake(0,0,raster.pixelWidth,raster.pixelHeight),image);CGContextRelease(context);}
  @finally{CGImageRelease(image);}
  return raster;
}
HueviaRaster *load(NSString *path,NSString *root,int edge){CGImageSourceRef source=CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path],(__bridge CFDictionaryRef)@{(__bridge id)kCGImageSourceShouldCache:@NO});@try{return decode(source,root,edge);}@finally{if(source)CFRelease(source);}}
HueviaRaster *scaled(HueviaRaster *input,int width,int height,NSString *root){
  if(input.pixelWidth==width&&input.pixelHeight==height)return input;
  HueviaRaster *output=[[HueviaRaster alloc] initWithWidth:width height:height root:root];CGContextRef context=[output newContext];CGContextSetInterpolationQuality(context,kCGInterpolationHigh);CGImageRef image=[input newImage];CGContextDrawImage(context,CGRectMake(0,0,width,height),image);CGImageRelease(image);CGContextRelease(context);output.orientation=input.orientation;return output;
}
HueviaRaster *analysis(HueviaRaster *input,NSString *root){double scale=std::min(1.0,320.0/std::max(input.pixelWidth,input.pixelHeight));return scaled(input,std::max(1,int(std::lround(input.pixelWidth*scale))),std::max(1,int(std::lround(input.pixelHeight*scale))),root);}
IOSIntArray *pixels(HueviaRaster *input){IOSIntArray *array=[IOSIntArray arrayWithLength:input.pixelWidth*input.pixelHeight];[input readWithIntArray:array withInt:0 withInt:input.pixelHeight];return array;}
HueviaRaster *compose(HueviaRaster *input,CcHueviaNcpPhotoGeometry *geometry,NSString *root,HueviaTask *task){
  if([geometry isNeutral]&&input.orientation==1)return input;
  CcHueviaNcpPhotoGeometry_Plan *plan=[geometry planWithInt:input.pixelWidth withInt:input.pixelHeight withInt:input.orientation];
  HueviaRaster *output=[[HueviaRaster alloc] initWithWidth:plan->width_ height:plan->height_ root:root];
  double a=plan->a_,b=plan->b_,c=plan->c_,d=plan->d_,e=plan->e_,f=plan->f_,g=plan->g_,h=plan->h_;
  for(int y=0;y<output.pixelHeight;y++){if((y&15)==0)check(task);for(int x=0;x<output.pixelWidth;x++){
    double px=x+.5,py=y+.5,aa=a-px*g,bb=b-px*h,dd=d-py*g,ee=e-py*h,det=aa*ee-bb*dd;
    if(std::abs(det)<1e-12)continue;double sx=(ee*(px-c)-bb*(py-f))/det-.5,sy=(-dd*(px-c)+aa*(py-f))/det-.5;
    if(sx<-.5||sy<-.5||sx>input.pixelWidth-.5||sy>input.pixelHeight-.5)continue;
    sx=std::clamp(sx,0.0,double(input.pixelWidth-1));sy=std::clamp(sy,0.0,double(input.pixelHeight-1));int ix=int(sx),iy=int(sy),nx=std::min(ix+1,input.pixelWidth-1),ny=std::min(iy+1,input.pixelHeight-1);double u=sx-ix,v=sy-iy;
    uint32_t q[4]={input.pixels[size_t(iy)*input.pixelWidth+ix],input.pixels[size_t(iy)*input.pixelWidth+nx],input.pixels[size_t(ny)*input.pixelWidth+ix],input.pixels[size_t(ny)*input.pixelWidth+nx]},result=0;
    for(int shift=0;shift<32;shift+=8){double value=((q[0]>>shift)&255)*(1-u)*(1-v)+((q[1]>>shift)&255)*u*(1-v)+((q[2]>>shift)&255)*(1-u)*v+((q[3]>>shift)&255)*u*v;result|=uint32_t(std::lround(value))<<shift;}
    output.pixels[size_t(y)*output.pixelWidth+x]=result;
  }}return output;
}
NSDictionary *captureData(NSDictionary *props){
  NSDictionary *tiff=props[(__bridge id)kCGImagePropertyTIFFDictionary]?:@{},*exif=props[(__bridge id)kCGImagePropertyExifDictionary]?:@{};NSMutableDictionary *data=[NSMutableDictionary dictionary];
  for(NSString *key in @[@"Make",@"Model"]){id value=tiff[key];if(value)data[key]=[value description];}
  for(NSString *key in @[@"FocalLength",@"FNumber",@"ExposureTime",@"PhotographicSensitivity",@"ISOSpeedRatings",@"DateTimeOriginal",@"DateTimeDigitized"]){id value=exif[key];if([value isKindOfClass:NSArray.class])value=[value firstObject];if(value)data[key]=[value description];}
  return data;
}
NSDictionary *safeMetadata(NSDictionary *source,int width,int height,double quality){
  NSDictionary *originalExif=source[(__bridge id)kCGImagePropertyExifDictionary]?:@{},*originalTiff=source[(__bridge id)kCGImagePropertyTIFFDictionary]?:@{};
  NSMutableDictionary *exif=[NSMutableDictionary dictionary],*tiff=[NSMutableDictionary dictionary];
  for(NSString *key in @[@"DateTimeOriginal",@"DateTimeDigitized",@"SubsecTime",@"SubsecTimeOriginal",@"SubsecTimeDigitized",@"OffsetTime",@"OffsetTimeOriginal",@"OffsetTimeDigitized",@"LensMake",@"LensModel",@"ExposureTime",@"FNumber",@"ISOSpeedRatings",@"PhotographicSensitivity",@"ExposureProgram",@"ExposureBiasValue",@"MeteringMode",@"Flash",@"FocalLength",@"FocalLenIn35mmFilm",@"WhiteBalance"]){if(originalExif[key])exif[key]=originalExif[key];}
  for(NSString *key in @[@"Make",@"Model",@"DateTime"]){if(originalTiff[key])tiff[key]=originalTiff[key];}
  exif[(__bridge id)kCGImagePropertyExifPixelXDimension]=@(width);exif[(__bridge id)kCGImagePropertyExifPixelYDimension]=@(height);tiff[(__bridge id)kCGImagePropertyTIFFOrientation]=@1;
  return @{(__bridge id)kCGImagePropertyExifDictionary:exif,(__bridge id)kCGImagePropertyTIFFDictionary:tiff,(__bridge id)kCGImagePropertyOrientation:@1,(__bridge id)kCGImageDestinationLossyCompressionQuality:@(quality),(__bridge id)kCGImageDestinationEmbedThumbnail:@NO};
}
void encode(HueviaRaster *raster,NSString *path,BOOL png,NSDictionary *metadata){
  CGImageDestinationRef destination=CGImageDestinationCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path],png?CFSTR("public.png"):CFSTR("public.jpeg"),1,NULL);if(!destination)fail(@"无法创建照片输出文件。");
  @try {CGImageRef image=[raster newImage];CGImageDestinationAddImage(destination,image,(__bridge CFDictionaryRef)metadata);CGImageRelease(image);if(!CGImageDestinationFinalize(destination))fail(@"照片编码失败。");}@finally{CFRelease(destination);}
}
NSString *hashFile(NSString *path,HueviaTask *task){
  CC_SHA256_CTX digest;CC_SHA256_Init(&digest);NSInputStream *input=[NSInputStream inputStreamWithFileAtPath:path];[input open];uint8_t buffer[65536];
  @try {while(true){check(task);NSInteger count=[input read:buffer maxLength:sizeof(buffer)];if(count<0)fail(@"无法校验照片原文件。");if(count==0)break;CC_SHA256_Update(&digest,buffer,CC_LONG(count));}}@finally{[input close];}
  uint8_t bytes[CC_SHA256_DIGEST_LENGTH];CC_SHA256_Final(bytes,&digest);NSMutableString *value=[NSMutableString string];for(uint8_t b:bytes)[value appendFormat:@"%02x",b];return value;
}
NSString *hashText(NSString *value){NSData *data=[value dataUsingEncoding:NSUTF8StringEncoding];uint8_t bytes[CC_SHA256_DIGEST_LENGTH];CC_SHA256(data.bytes,CC_LONG(data.length),bytes);NSMutableString *result=[NSMutableString string];for(uint8_t b:bytes)[result appendFormat:@"%02x",b];return result;}
int rawProgress(void *context,double value){HueviaTask *task=(__bridge HueviaTask *)context;[task acceptWithDouble:value*.3];return task.cancelled?1:0;}
}

@implementation HueviaImageValidator
- (void)validateWithByteArray:(IOSByteArray *)bytes {
  if(!bytes||bytes->size_<4||bytes->size_>8*1024*1024)fail(@"样片文件大小无效。");
  NSData *data=[NSData dataWithBytes:bytes->buffer_ length:bytes->size_];CGImageSourceRef source=CGImageSourceCreateWithData((__bridge CFDataRef)data,NULL);
  if(!source)fail(@"样片不是可解码的照片。");
  @try {NSDictionary *p=CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source,0,NULL));validSize([p[(__bridge id)kCGImagePropertyPixelWidth] intValue],[p[(__bridge id)kCGImagePropertyPixelHeight] intValue],64000000);CGImageRef decoded=CGImageSourceCreateThumbnailAtIndex(source,0,(__bridge CFDictionaryRef)@{(__bridge id)kCGImageSourceCreateThumbnailFromImageAlways:@YES,(__bridge id)kCGImageSourceThumbnailMaxPixelSize:@1024});if(!decoded)fail(@"样片无法安全解码。");CGImageRelease(decoded);}@finally{CFRelease(source);}
}
@end

@implementation HueviaMedia {
  CcHueviaSharedSharedRuntime *_runtime;
  NSString *_root;
}
- (instancetype)initWithRuntime:(CcHueviaSharedSharedRuntime *)runtime root:(NSString *)root {self=[super init];if(self){_runtime=runtime;_root=root;}return self;}
- (HueviaRaster *)raw:(NSString *)path owner:(NSString *)owner settings:(CcHueviaNcpRawDevelopmentSettings *)controls task:(HueviaTask *)task status:(NSString **)status {
  NSData *scope=[owner dataUsingEncoding:NSUTF8StringEncoding];unsigned char digest[CC_SHA256_DIGEST_LENGTH];CC_SHA256(scope.bytes,CC_LONG(scope.length),digest);NSMutableString *scopeHash=[NSMutableString string];for(unsigned char b:digest)[scopeHash appendFormat:@"%02x",b];
  NSString *sourceHash=hashFile(path,task),*directory=[[_root stringByAppendingPathComponent:@"raw-development"] stringByAppendingPathComponent:scopeHash];
  if(![NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil])fail(@"无法创建 RAW 显影目录。");
  NSString *identity=hashText([NSString stringWithFormat:@"%@-%@-%s-camera-jpeg-white-v2",sourceHash,[controls identity],HueviaRawVersion()]),*cached=[directory stringByAppendingPathComponent:[identity stringByAppendingString:@".png"]],*receipt=[directory stringByAppendingPathComponent:[identity stringByAppendingString:@".json"]];
  if([NSFileManager.defaultManager fileExistsAtPath:cached]){@try{
    NSDictionary *attrs=[NSFileManager.defaultManager attributesOfItemAtPath:receipt error:nil];if([attrs[NSFileSize] unsignedLongLongValue]>4096)fail(@"RAW 缓存记录无效。");
    NSData *data=[NSData dataWithContentsOfFile:receipt];NSDictionary *record=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
    if(![record isKindOfClass:NSDictionary.class]||![record[@"identity"] isEqual:identity]||![record[@"sha256"] isEqual:hashFile(cached,task)]||![record[@"status"] isKindOfClass:NSString.class])fail(@"RAW 缓存校验失败。");
    HueviaRaster *r=load(cached,_root,0);if(![sourceHash isEqual:hashFile(path,task)])fail(@"RAW 原图发生变化。");*status=record[@"status"];return r;
  }@catch(JavaIoInterruptedIOException *cancelled){@throw cancelled;}@catch(id invalid){[NSFileManager.defaultManager removeItemAtPath:cached error:nil];[NSFileManager.defaultManager removeItemAtPath:receipt error:nil];}}
  HueviaRawInfo info;char error[1024];if(HueviaRawInspect(path.fileSystemRepresentation,&info,error,sizeof(error)))fail([NSString stringWithUTF8String:error]);
  HueviaRaster *raster=[[HueviaRaster alloc] initWithWidth:info.width height:info.height root:_root];HueviaRawSettings settings={[controls->whiteBalance_ ordinal],controls->temperatureKelvin_,controls->tint_,controls->exposureTenths_,controls->highlightMode_,controls->demosaicQuality_};
  if(HueviaRawDevelop(path.fileSystemRepresentation,&settings,raster.pixels,raster.pixelWidth,raster.pixelHeight,rawProgress,(__bridge void *)task,error,sizeof(error)))fail([NSString stringWithUTF8String:error]);
  check(task);*status=[controls->colorMode_ ordinal]==0?@"NO_REFERENCE":@"NEUTRAL";uint8_t *jpeg=NULL;int length=0;
  if([controls->colorMode_ ordinal]==0&&HueviaRawEmbeddedJpeg(path.fileSystemRepresentation,&jpeg,&length)==0){
    NSData *data=[NSData dataWithBytesNoCopy:jpeg length:length freeWhenDone:YES];CGImageSourceRef source=CGImageSourceCreateWithData((__bridge CFDataRef)data,NULL);
    if(source){@try{
      HueviaRaster *base=raster;
      if(settings.whiteBalance!=0||settings.kelvin!=5500||settings.tint!=0||settings.exposureTenths!=0||settings.highlights!=2||settings.quality!=3){
        base=[[HueviaRaster alloc] initWithWidth:info.width height:info.height root:_root];HueviaRawSettings neutralSettings={0,5500,0,0,2,3};
        if(HueviaRawDevelop(path.fileSystemRepresentation,&neutralSettings,base.pixels,base.pixelWidth,base.pixelHeight,rawProgress,(__bridge void *)task,error,sizeof(error)))fail([NSString stringWithUTF8String:error]);
      }
      HueviaRaster *reference=analysis(compose(decode(source,_root,640),CcHueviaNcpPhotoGeometry_get_NONE(),_root,task),_root),*neutral=analysis(base,_root);base=nil;
      CcHueviaNcpRawJpegColorMatch_Fit *fit=[CcHueviaNcpRawJpegColorMatch fitWithIntArray:pixels(neutral) withInt:neutral.pixelWidth withInt:neutral.pixelHeight withIntArray:pixels(reference) withInt:reference.pixelWidth withInt:reference.pixelHeight withJavaUtilFunctionBooleanSupplier:task];
      *status=fit->reason_;
      if(fit->accepted_){for(int y=0;y<raster.pixelHeight;y++){if((y&31)==0)check(task);for(int x=0;x<raster.pixelWidth;x++){size_t i=size_t(y)*raster.pixelWidth+x;raster.pixels[i]=uint32_t([fit applyArgbWithInt:int32_t(raster.pixels[i])]);}}}
    }@catch(JavaIoInterruptedIOException *cancelled){@throw cancelled;}@catch(id unusable){*status=@"UNRELIABLE_FIT";}@finally{CFRelease(source);}}
  }
  check(task);if(![sourceHash isEqualToString:hashFile(path,task)])fail(@"RAW 原文件发生变化，未保存结果。");
  NSString *temporary=[directory stringByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingString:@".part"]];
  @try{encode(raster,temporary,YES,@{});check(task);NSString *sha=hashFile(temporary,task);if(![NSFileManager.defaultManager moveItemAtPath:temporary toPath:cached error:nil])fail(@"无法保存 RAW 显影结果。");NSData *record=[NSJSONSerialization dataWithJSONObject:@{@"identity":identity,@"sha256":sha,@"status":*status} options:0 error:nil];if(![record writeToFile:receipt options:NSDataWritingAtomic error:nil])fail(@"无法保存 RAW 缓存校验记录。");}@finally{[NSFileManager.defaultManager removeItemAtPath:temporary error:nil];}
  return raster;
}
- (NSDictionary *)request:(NSString *)operation payload:(NSString *)payload task:(HueviaTask *)task {
  NSDictionary *p=[NSJSONSerialization JSONObjectWithData:[payload dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];if(![p isKindOfClass:NSDictionary.class]||![p[@"path"] isKindOfClass:NSString.class])fail(@"照片请求数据无效。");
  NSString *path=[[_runtime privateFileWithNSString:p[@"path"]] getPath];BOOL raw=isRaw(path);NSDictionary *metadata=properties(path);check(task);
  if([operation isEqualToString:@"media.info"]){
    if(raw){HueviaRawInfo info;char error[1024];if(HueviaRawInspect(path.fileSystemRepresentation,&info,error,sizeof(error)))fail([NSString stringWithUTF8String:error]);return @{@"width":@(info.width),@"height":@(info.height),@"raw":@YES,@"make":[NSString stringWithUTF8String:info.make]?:@"",@"model":[NSString stringWithUTF8String:info.model]?:@""};}
    int width=[metadata[(__bridge id)kCGImagePropertyPixelWidth] intValue],height=[metadata[(__bridge id)kCGImagePropertyPixelHeight] intValue];validSize(width,height);return @{@"width":@(width),@"height":@(height),@"raw":@NO,@"orientation":metadata[(__bridge id)kCGImagePropertyOrientation]?:@1};
  }
  if([operation isEqualToString:@"media.rawPreview"]||[operation isEqualToString:@"media.rawDevelop"]){
    if(!raw||![p[@"settings"] isKindOfClass:NSDictionary.class])fail(@"RAW 显影请求无效。");
    NSString *owner=p[@"owner"]?:@"";if(![owner isKindOfClass:NSString.class]||owner.length>64)fail(@"编辑账号数据无效。");[_runtime guardOwnerWithNSString:owner];
    CcHueviaNcpRawDevelopmentSettings *controls=[CcHueviaSharedSharedRawSettings parseWithNSString:json(p[@"settings"])];NSString *status=@"",*sourceSha=hashFile(path,task);
    HueviaRaster *working=[self raw:path owner:owner settings:controls task:task status:&status];BOOL preview=[operation isEqualToString:@"media.rawPreview"];
    if(preview){double scale=std::min(1.0,1280.0/std::max(working.pixelWidth,working.pixelHeight));working=scaled(working,std::max(1,int(std::lround(working.pixelWidth*scale))),std::max(1,int(std::lround(working.pixelHeight*scale))),_root);}
    NSString *directory=[_root stringByAppendingPathComponent:preview?@"previews":@"raw-editor"];if(![NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil])fail(@"无法创建 RAW 编辑目录。");
    NSString *name=NSUUID.UUID.UUIDString,*temporary=[directory stringByAppendingPathComponent:[name stringByAppendingString:@".part"]],*target=[directory stringByAppendingPathComponent:[name stringByAppendingString:@".jpg"]];
    @try{encode(working,temporary,NO,safeMetadata(metadata,working.pixelWidth,working.pixelHeight,preview?.98:1.0));check(task);[_runtime guardOwnerWithNSString:owner];[_runtime validateSourceWithNSString:path withNSString:sourceSha];if(![NSFileManager.defaultManager moveItemAtPath:temporary toPath:target error:nil])fail(@"无法保存 RAW 编辑副本。");}@finally{[NSFileManager.defaultManager removeItemAtPath:temporary error:nil];}
    NSDictionary *settings=[NSJSONSerialization JSONObjectWithData:[[CcHueviaSharedSharedRawSettings jsonWithCcHueviaNcpRawDevelopmentSettings:controls] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];return @{@"path":target,@"width":@(working.pixelWidth),@"height":@(working.pixelHeight),@"sourceSha":sourceSha,@"settings":settings,@"rawColorStatus":status};
  }
  BOOL preview=[operation isEqualToString:@"media.preview"];if(!preview&&![operation isEqualToString:@"media.export"])fail(@"未知的照片操作。");
  if(![p[@"recipe"] isKindOfClass:NSDictionary.class])fail(@"编辑设置无效。");
  NSString *owner=p[@"owner"]?:@"";if(![owner isKindOfClass:NSString.class]||owner.length>64)fail(@"编辑账号数据无效。");
  CcHueviaAlbumPhotoEditStore_Draft *frozen=[_runtime freezeEditWithNSString:path withNSString:owner withNSString:json(p[@"recipe"])];
  if(!preview)[_runtime validateSourceWithNSString:path withNSString:frozen->sourceSha_];
  NSString *colorStatus=@"";HueviaRaster *working=raw?[self raw:path owner:owner settings:[CcHueviaSharedSharedRawSettings parseWithNSString:@"{}"] task:task status:&colorStatus]:load(path,_root,preview?1280:0);
  if(raw&&preview){double scale=std::min(1.0,1280.0/std::max(working.pixelWidth,working.pixelHeight));working=scaled(working,std::max(1,int(std::lround(working.pixelWidth*scale))),std::max(1,int(std::lround(working.pixelHeight*scale))),_root);}
  id<CcHueviaNcpPresetPreviewProfile> profile=[frozen profile];
  [profile renderPixelsWithCcHueviaNcpSpatialPreviewFilter_Pixels:working withJavaUtilFunctionBooleanSupplier:task withJavaUtilFunctionDoubleConsumer:task];
  check(task);working=compose(working,frozen->geometry_,_root,task);
  working=[HueviaFrames apply:working border:frozen->border_ capture:[[CcHueviaSharedSharedCaptureInfo alloc] initWithNSString:json(captureData(metadata))] root:_root task:task];
  CcHueviaAlbumPhotoExportSpec *spec=preview||[p[@"size"] isEqual:@"share"]?[CcHueviaAlbumPhotoExportSpec share]:[CcHueviaAlbumPhotoExportSpec full];
  if(!preview&&[p[@"size"] isEqual:@"custom"]){if(![p[@"longEdge"] isKindOfClass:NSNumber.class]||![p[@"quality"] isKindOfClass:NSNumber.class])fail(@"自定义导出设置无效。");spec=[CcHueviaAlbumPhotoExportSpec customWithInt:[p[@"longEdge"] intValue] withInt:[p[@"quality"] intValue]];}
  CcHueviaAlbumPhotoExportSpec_Resolved *resolved=[spec resolveWithInt:working.pixelWidth withInt:working.pixelHeight];working=scaled(working,resolved->width_,resolved->height_,_root);check(task);
  NSString *directory=[_root stringByAppendingPathComponent:preview?@"previews":@"exports"];if(![NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil])fail(@"无法创建照片导出目录。");
  NSString *name=NSUUID.UUID.UUIDString,*temporary=[directory stringByAppendingPathComponent:[name stringByAppendingString:@".part"]],*target=[directory stringByAppendingPathComponent:[name stringByAppendingString:@".jpg"]];
  @try{encode(working,temporary,NO,safeMetadata(metadata,working.pixelWidth,working.pixelHeight,resolved->quality_/100.0));check(task);[_runtime guardOwnerWithNSString:owner];if(!preview)[_runtime validateSourceWithNSString:path withNSString:frozen->sourceSha_];if(![NSFileManager.defaultManager moveItemAtPath:temporary toPath:target error:nil])fail(@"无法保存效果图。");if(!preview)[_runtime markEditExportedWithNSString:owner withCcHueviaAlbumPhotoEditStore_Draft:frozen];}@finally{[NSFileManager.defaultManager removeItemAtPath:temporary error:nil];}
  [task acceptWithDouble:1];NSDictionary *attributes=[NSFileManager.defaultManager attributesOfItemAtPath:target error:nil];return @{@"path":target,@"width":@(working.pixelWidth),@"height":@(working.pixelHeight),@"bytes":attributes[NSFileSize]?:@0,@"preview":@(preview),@"model":[profile modelVersion],@"rawColorStatus":colorStatus};
}
@end
