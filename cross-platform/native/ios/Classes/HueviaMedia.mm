#import "HueviaMedia.h"
#import "HueviaRaster.h"
#import "HueviaRaw.h"
#import "HueviaFrames.h"
#import <ImageIO/ImageIO.h>
#import <CommonCrypto/CommonDigest.h>
#import "cc/huevia/shared/SharedRecipe.h"
#import "cc/huevia/shared/SharedCaptureInfo.h"
#import "cc/huevia/shared/SharedRawSettings.h"
#import "cc/huevia/shared/SharedCleanup.h"
#import "cc/huevia/shared/SharedExportModel.h"
#import "cc/huevia/shared/SharedAtmosphere.h"
#import "cc/huevia/ncp/RawDevelopmentSettings.h"
#import "cc/huevia/ncp/PhotoGeometry.h"
#import "cc/huevia/ncp/PhotoBorder.h"
#import "cc/huevia/ncp/PresetPreviewProfile.h"
#import "cc/huevia/ncp/PresetPreviewProfiles.h"
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

@interface HueviaExportSession : NSObject
@property(nonatomic,copy) NSString *identifier;
@property(nonatomic,copy) NSString *owner;
@property(nonatomic,copy) NSString *source;
@property(nonatomic,copy) NSString *folder;
@property(nonatomic,copy) NSString *jpeg;
@property(nonatomic,copy) NSString *reference;
@property(nonatomic,copy) NSString *model;
@property(nonatomic,copy) NSString *spec;
@property(nonatomic,strong) CcHueviaAlbumPhotoEditStore_Draft *draft;
@property(nonatomic,strong) HueviaRaster *before;
@property(nonatomic,strong) HueviaRaster *after;
@property(nonatomic,strong) NSDictionary *sourceAttributes;
@end
@implementation HueviaExportSession
@end

@implementation HueviaMedia {
  CcHueviaSharedSharedRuntime *_runtime;
  NSString *_root;
  HueviaExportSession *_exportSession;
}
- (instancetype)initWithRuntime:(CcHueviaSharedSharedRuntime *)runtime root:(NSString *)root {self=[super init];if(self){_runtime=runtime;_root=root;
  NSString *previews=[root stringByAppendingPathComponent:@"previews"];
  NSArray<NSString *> *abandoned=[[previews stringByResolvingSymlinksInPath] isEqual:previews]?[NSFileManager.defaultManager contentsOfDirectoryAtPath:previews error:nil]:nil;
  for(NSString *name in abandoned){
    if([name hasPrefix:@"export-"]&&[[NSUUID alloc] initWithUUIDString:[name substringFromIndex:7]]){
      NSString *path=[previews stringByAppendingPathComponent:name];NSDictionary *a=[NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
      if(![a[NSFileType] isEqual:NSFileTypeSymbolicLink])[NSFileManager.defaultManager removeItemAtPath:path error:nil];
    }
  }
}return self;}
- (void)closeExportPreview {
  HueviaExportSession *session=_exportSession;_exportSession=nil;
  if(session)[NSFileManager.defaultManager removeItemAtPath:session.folder error:nil];
}
- (void)validateExportPreview:(HueviaExportSession *)session {
  [_runtime guardOwnerWithNSString:session.owner];
  [_runtime privateFileWithNSString:session.source];
  NSDictionary *now=[NSFileManager.defaultManager attributesOfItemAtPath:session.source error:nil];
  if(!now||![now[NSFileSize] isEqual:session.sourceAttributes[NSFileSize]]||![now[NSFileModificationDate] isEqual:session.sourceAttributes[NSFileModificationDate]])fail(@"原图已变化，请重新打开成品预览。");
}
- (NSString *)exportFrame:(HueviaRaster *)source width:(int)width height:(int)height scale:(double)scale cx:(double)cx cy:(double)cy folder:(NSString *)folder task:(HueviaTask *)task {
  HueviaRaster *output=[[HueviaRaster alloc] initWithWidth:width height:height root:_root];
  // Exact one-source-pixel sampling at 100%; both modes use identical mapping.
  for(int y=0;y<height;y++){
    if((y&15)==0)check(task);
    int sy=(int)std::floor(cy+(y+.5-height/2.0)/scale);
    for(int x=0;x<width;x++){
      int sx=(int)std::floor(cx+(x+.5-width/2.0)/scale);
      output.pixels[y*width+x]=(sx>=0&&sy>=0&&sx<source.pixelWidth&&sy<source.pixelHeight)?source.pixels[sy*source.pixelWidth+sx]:0xff0a0908;
    }
  }
  NSString *path=[folder stringByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingString:@".png"]];
  @try{encode(output,path,YES,@{});check(task);return path;}@catch(id error){[NSFileManager.defaultManager removeItemAtPath:path error:nil];@throw error;}
}
- (NSDictionary *)exportPreviewRequest:(NSString *)operation payload:(NSDictionary *)p task:(HueviaTask *)task {
  NSString *identifier=p[@"id"];if(![identifier isKindOfClass:NSString.class]||identifier.length>64)fail(@"成品预览标识无效。");
  HueviaExportSession *session=_exportSession;
  if([operation isEqual:@"media.exportPreviewClose"]){if([session.identifier isEqual:identifier])[self closeExportPreview];return @{};}
  if(!session||![session.identifier isEqual:identifier])fail(@"成品预览已失效，请重新打开。");
  [self validateExportPreview:session];check(task);
  if([operation isEqual:@"media.exportPreviewCommit"]){
    [_runtime validateSourceWithNSString:session.source withNSString:session.draft->sourceSha_];
    NSDictionary *attributes=[NSFileManager.defaultManager attributesOfItemAtPath:session.jpeg error:nil];
    NSDictionary *metadata=@{@"path":session.jpeg,@"width":@(session.before.pixelWidth),@"height":@(session.before.pixelHeight),@"bytes":attributes[NSFileSize]?:@0,@"preview":@NO,@"model":session.model,@"exportSpec":session.spec};
    NSString *directory=[_root stringByAppendingPathComponent:@"exports"];
    if(![[directory stringByResolvingSymlinksInPath] isEqual:directory]||![NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil])fail(@"成品输出目录不可用。");
    NSString *staged=[directory stringByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingString:@".jpg"]],*expected=hashFile(session.jpeg,task),*saved=nil;
    @try{
      if(![NSFileManager.defaultManager copyItemAtPath:session.jpeg toPath:staged error:nil])fail(@"无法暂存确认的成品。");
      saved=[_runtime commitVersionWithNSString:session.source withNSString:session.owner withCcHueviaAlbumPhotoEditStore_Draft:session.draft withNSString:staged withNSString:json(metadata) withJavaUtilFunctionBooleanSupplier:task];
    }@finally{[NSFileManager.defaultManager removeItemAtPath:staged error:nil];}
    NSDictionary *receipt=[NSJSONSerialization JSONObjectWithData:[saved dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    if(![expected isEqual:receipt[@"sha256"]])fail(@"已有同设置成品与本次预览不同，请先在成品版本中核对旧结果。");
    [_runtime markEditExportedWithNSString:session.owner withCcHueviaAlbumPhotoEditStore_Draft:session.draft];
    [self closeExportPreview];return [NSJSONSerialization JSONObjectWithData:[saved dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
  }
  if(![operation isEqual:@"media.exportPreviewFrame"])fail(@"未知的成品预览操作。");
  for(NSString *key in @[@"width",@"height",@"scale",@"cx",@"cy"]){id value=p[key];if(value&&(![value isKindOfClass:NSNumber.class]||CFGetTypeID((__bridge CFTypeRef)value)==CFBooleanGetTypeID()||!std::isfinite([value doubleValue])))fail(@"预览视口数据无效。");}
  int width=[p[@"width"] intValue],height=[p[@"height"] intValue];
  if(width<1||height<1||width>4096||height>4096||uint64_t(width)*height>12000000||[p[@"width"] doubleValue]!=width||[p[@"height"] doubleValue]!=height)fail(@"预览视口尺寸过大。");
  double fit=std::min(width/double(session.before.pixelWidth),height/double(session.before.pixelHeight));
  double scale=p[@"scale"]?[p[@"scale"] doubleValue]:fit,cx=p[@"cx"]?[p[@"cx"] doubleValue]:.5,cy=p[@"cy"]?[p[@"cy"] doubleValue]:.5;
  if(scale<std::min(fit,.00001)||scale>32||cx<0||cx>1||cy<0||cy>1)fail(@"预览视口数据超出范围。");
  NSString *before=nil,*jpeg=nil;
  @try{
    before=[self exportFrame:session.before width:width height:height scale:scale cx:cx*session.before.pixelWidth cy:cy*session.before.pixelHeight folder:session.folder task:task];
    jpeg=[self exportFrame:session.after width:width height:height scale:scale cx:cx*session.after.pixelWidth cy:cy*session.after.pixelHeight folder:session.folder task:task];
    [self validateExportPreview:session];return @{@"before":before,@"jpeg":jpeg,@"width":@(width),@"height":@(height)};
  }@catch(id error){if(before)[NSFileManager.defaultManager removeItemAtPath:before error:nil];if(jpeg)[NSFileManager.defaultManager removeItemAtPath:jpeg error:nil];@throw error;}
}
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
  NSDictionary *p=[NSJSONSerialization JSONObjectWithData:[payload dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];if(![p isKindOfClass:NSDictionary.class])fail(@"照片请求数据无效。");
  if([operation hasPrefix:@"media.exportPreview"]&&![operation isEqual:@"media.exportPreview"])return [self exportPreviewRequest:operation payload:p task:task];
  NSString *templateDirectory=[_root stringByAppendingPathComponent:@"preview-template"],*customTemplate=[templateDirectory stringByAppendingPathComponent:@"custom.jpg"];
  if(([operation hasPrefix:@"media.template"]||[operation isEqualToString:@"media.showcase"])&&(![[templateDirectory stringByResolvingSymlinksInPath] isEqualToString:[[_root stringByResolvingSymlinksInPath] stringByAppendingPathComponent:@"preview-template"]]||![[customTemplate stringByResolvingSymlinksInPath] isEqualToString:[[templateDirectory stringByResolvingSymlinksInPath] stringByAppendingPathComponent:@"custom.jpg"]]))fail(@"模板目录不可用。");
  if([operation hasPrefix:@"media.template"]){
    if([operation isEqualToString:@"media.templateSet"]){
      NSString *source=[[_runtime privateFileWithNSString:p[@"path"]] getPath];unsigned long long size=[[NSFileManager.defaultManager attributesOfItemAtPath:source error:nil] fileSize];
      if(size<4||size>20*1024*1024||isRaw(source))fail(@"请选择 20MB 以内的普通照片作为模板。");
      if(![NSFileManager.defaultManager createDirectoryAtPath:templateDirectory withIntermediateDirectories:YES attributes:nil error:nil])fail(@"无法创建模板目录。");
      NSString *temporary=[templateDirectory stringByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingString:@".part"]];
      @try{HueviaRaster *image=compose(load(source,_root,960),CcHueviaNcpPhotoGeometry_get_NONE(),_root,task);
        // The original Android template normalizes EXIF and composites alpha
        // onto white before encoding the private JPEG.
        for(size_t i=0,n=size_t(image.pixelWidth)*image.pixelHeight;i<n;i++){uint32_t v=image.pixels[i],white=255-(v>>24);image.pixels[i]=0xff000000U|std::min(255U,((v>>16)&255)+white)<<16|std::min(255U,((v>>8)&255)+white)<<8|std::min(255U,(v&255)+white);}
        check(task);encode(image,temporary,NO,@{(__bridge id)kCGImageDestinationLossyCompressionQuality:@.95});check(task);
        NSData *bytes=[NSData dataWithContentsOfFile:temporary options:NSDataReadingMappedIfSafe error:nil];if(!bytes||bytes.length>8*1024*1024||![bytes writeToFile:customTemplate options:NSDataWritingAtomic error:nil])fail(@"模板未能保存，原模板仍可使用。");
      }@finally{[NSFileManager.defaultManager removeItemAtPath:temporary error:nil];}
    }else if([operation isEqualToString:@"media.templateReset"]){
      if([NSFileManager.defaultManager fileExistsAtPath:customTemplate]&&![NSFileManager.defaultManager removeItemAtPath:customTemplate error:nil])fail(@"无法恢复内置样片，原模板仍可使用。");
    }else if([operation isEqualToString:@"media.templateSource"]){
      int index=p[@"index"]?[p[@"index"] intValue]:0;BOOL custom=[NSFileManager.defaultManager fileExistsAtPath:customTemplate];
      NSArray *names=@[@"portrait-smile",@"portrait-man",@"alpine-lake",@"sunlit-forest",@"city-skyline",@"neon-street",@"coastal-water",@"pink-tulips",@"breakfast",@"rainy-tokyo"];
      NSArray *labels=@[@"微笑人像",@"男士人像",@"高山湖泊",@"阳光森林",@"城市天际线",@"霓虹街道",@"海岸浪花",@"粉色郁金香",@"早餐静物",@"雨夜街头"];
      if(index<0||index>=(custom?1:10))fail(@"模板样片索引无效。");
      if(custom)return @{@"path":customTemplate,@"label":@"自选模板",@"credit":@""};
      NSURL *url=[NSBundle.mainBundle URLForResource:@"HueviaNativeAssets" withExtension:@"bundle"]?:[[NSBundle bundleForClass:HueviaMedia.class] URLForResource:@"HueviaNativeAssets" withExtension:@"bundle"];NSURL *image=[[NSBundle bundleWithURL:url] URLForResource:names[index] withExtension:@"jpg"];if(!image)fail(@"摄影样片尚未安装。");
      return @{@"path":image.path,@"label":labels[index],@"credit":@"Pexels · 内置摄影样片"};
    }else if(![operation isEqualToString:@"media.templateInfo"])fail(@"未知的模板操作。");
    BOOL custom=[NSFileManager.defaultManager fileExistsAtPath:customTemplate];return @{@"custom":@(custom),@"count":custom?@1:@10,@"version":custom?hashFile(customTemplate,task):@"photography-v1"};
  }
  if([operation isEqualToString:@"media.showcase"]){
    NSString *owner=p[@"owner"]?:@"",*presetID=p[@"id"],*category=p[@"category"]?:@"";
    if(![owner isKindOfClass:NSString.class]||![presetID isKindOfClass:NSString.class]||![category isKindOfClass:NSString.class])fail(@"预设预览数据无效。");
    [_runtime guardOwnerWithNSString:owner];IOSByteArray *bytes=[_runtime presetWithNSString:presetID];
    if(presetID.length!=64||bytes.length==0)fail(@"请选择预设。");
    NSArray<NSString *> *names=@[@"portrait-smile",@"portrait-man",@"alpine-lake",@"sunlit-forest",@"city-skyline",@"neon-street",@"coastal-water",@"pink-tulips",@"breakfast",@"rainy-tokyo"];
    NSArray<NSNumber *> *pool=@[@0,@1,@2,@3,@4,@5,@6,@7,@8,@9];NSString *tag=[[category stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];
    if([@[@"人像",@"portrait"] containsObject:tag])pool=@[@0,@1];else if([@[@"风景",@"landscape"] containsObject:tag])pool=@[@2,@3,@6];else if([@[@"夜景",@"night"] containsObject:tag])pool=@[@5,@9];else if([@[@"日常",@"daily"] containsObject:tag])pool=@[@0,@4,@6,@7,@8];
    unsigned long long seed=0;[[NSScanner scannerWithString:[presetID substringToIndex:8]] scanHexLongLong:&seed];NSString *scene=names[pool[seed%pool.count].unsignedIntegerValue];
    NSURL *bundleURL=[NSBundle.mainBundle URLForResource:@"HueviaNativeAssets" withExtension:@"bundle"]?:[[NSBundle bundleForClass:HueviaMedia.class] URLForResource:@"HueviaNativeAssets" withExtension:@"bundle"];
    NSBundle *bundle=bundleURL?[NSBundle bundleWithURL:bundleURL]:nil;NSURL *imageURL=[bundle URLForResource:scene withExtension:@"jpg"];
    BOOL custom=[NSFileManager.defaultManager fileExistsAtPath:customTemplate];if(custom){imageURL=[NSURL fileURLWithPath:customTemplate];scene=[@"custom-" stringByAppendingString:hashFile(customTemplate,task)];}
    if(!imageURL)fail(@"摄影样片尚未安装。");
    id<CcHueviaNcpPresetPreviewProfile> profile=[CcHueviaNcpPresetPreviewProfiles fromPresetWithByteArray:bytes];
    NSString *directory=[_root stringByAppendingPathComponent:@"preset-previews"];if(![NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil])fail(@"无法创建预设预览目录。");
    NSString *model=[[profile modelVersion] stringByReplacingOccurrencesOfString:@"[^a-zA-Z0-9_-]" withString:@"_" options:NSRegularExpressionSearch range:NSMakeRange(0,[[profile modelVersion] length])];
    BOOL original=[p[@"original"] boolValue];int edge=p[@"edge"]?[p[@"edge"] intValue]:480;if(edge!=480&&edge!=960)fail(@"预览尺寸无效。");
    NSString *cacheKey=hashText([NSString stringWithFormat:@"showcase-v2:%@:%@:%@:%d:%d",presetID,scene,model,edge,original]);
    NSString *target=[directory stringByAppendingPathComponent:[cacheKey stringByAppendingString:@".jpg"]];
    if(![NSFileManager.defaultManager fileExistsAtPath:target]){
      HueviaRaster *raster=load(imageURL.path,_root,edge);if(!original)[profile renderPixelsWithCcHueviaNcpSpatialPreviewFilter_Pixels:raster withJavaUtilFunctionBooleanSupplier:task withJavaUtilFunctionDoubleConsumer:task];
      NSString *temporary=[directory stringByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingString:@".part"]];
      @try{check(task);encode(raster,temporary,NO,@{(__bridge id)kCGImageDestinationLossyCompressionQuality:@.9});[_runtime guardOwnerWithNSString:owner];if(![NSFileManager.defaultManager moveItemAtPath:temporary toPath:target error:nil])fail(@"无法保存预设预览。");}@finally{[NSFileManager.defaultManager removeItemAtPath:temporary error:nil];}
    }
    return @{@"path":target,@"scene":scene};
  }
  if(![p[@"path"] isKindOfClass:NSString.class])fail(@"照片路径无效。");
  NSString *path=[[_runtime privateFileWithNSString:p[@"path"]] getPath];BOOL raw=isRaw(path);NSDictionary *metadata=properties(path);check(task);
  if([operation isEqualToString:@"media.atmosphere"]){
    [_runtime guardOwnerWithNSString:p[@"owner"]?:@""];
    if(![path hasPrefix:[[_root stringByAppendingPathComponent:@"previews"] stringByAppendingString:@"/"]]||std::max([metadata[(__bridge id)kCGImagePropertyPixelWidth] intValue],[metadata[(__bridge id)kCGImagePropertyPixelHeight] intValue])>1280)fail(@"编辑背景只能读取有界预览。");
    HueviaRaster *small=load(path,_root,64);IOSIntArray *blurred=[CcHueviaSharedSharedAtmosphere blurWithIntArray:pixels(small) withInt:small.pixelWidth withInt:small.pixelHeight];
    for(int i=0;i<blurred.length;i++)small.pixels[i]=uint32_t(IOSIntArray_Get(blurred,i));
    NSString *target=[[_root stringByAppendingPathComponent:@"previews"] stringByAppendingPathComponent:[NSString stringWithFormat:@"atmosphere-%@.png",NSUUID.UUID.UUIDString]];
    @try{check(task);encode(small,target,YES,@{});return @{@"path":target};}@catch(id error){[NSFileManager.defaultManager removeItemAtPath:target error:nil];@throw error;}
  }
  if([operation isEqualToString:@"media.info"]){
    if(raw){HueviaRawInfo info;char error[1024];if(HueviaRawInspect(path.fileSystemRepresentation,&info,error,sizeof(error)))fail([NSString stringWithUTF8String:error]);return @{@"width":@(info.width),@"height":@(info.height),@"raw":@YES,@"make":[NSString stringWithUTF8String:info.make]?:@"",@"model":[NSString stringWithUTF8String:info.model]?:@""};}
    int width=[metadata[(__bridge id)kCGImagePropertyPixelWidth] intValue],height=[metadata[(__bridge id)kCGImagePropertyPixelHeight] intValue],orientation=[metadata[(__bridge id)kCGImagePropertyOrientation] intValue];if(orientation<1||orientation>8)orientation=1;validSize(width,height);return @{@"width":@(width),@"height":@(height),@"raw":@NO,@"orientation":@(orientation)};
  }
  if([operation isEqualToString:@"media.borderInfo"]){
    NSString *owner=p[@"owner"]?:@"";if(![owner isKindOfClass:NSString.class]||owner.length>64)fail(@"编辑账号数据无效。");[_runtime guardOwnerWithNSString:owner];
    CcHueviaSharedSharedCaptureInfo *capture=[[CcHueviaSharedSharedCaptureInfo alloc] initWithNSString:json(captureData(metadata))];NSMutableArray *fields=[NSMutableArray array];
    for(int i=0;i<5;i++)[fields addObject:[capture fieldWithCcHueviaNcpPhotoBorder:CcHueviaNcpPhotoBorder_get_NONE() withInt:i]];
    check(task);[_runtime guardOwnerWithNSString:owner];return @{@"brand":capture->brand_,@"model":capture->model_,@"fields":fields};
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
  if([operation isEqualToString:@"media.cleanupAnalyze"]){
    NSString *owner=p[@"owner"]?:@"";if(![owner isKindOfClass:NSString.class])fail(@"编辑账号数据无效。");[_runtime guardOwnerWithNSString:owner];
    NSString *sha=[_runtime sourceIdentityWithNSString:path withBoolean:true],*status=@"";
    HueviaRaster *source=raw?[self raw:path owner:owner settings:[CcHueviaSharedSharedRawSettings parseWithNSString:@"{}"] task:task status:&status]:load(path,_root,0);
    int sample=1;while((std::max(source.pixelWidth,source.pixelHeight)+sample-1)/sample>512)sample*=2;
    HueviaRaster *small=scaled(source,(source.pixelWidth+sample-1)/sample,(source.pixelHeight+sample-1)/sample,_root);
    HueviaRaster *overview=compose(small,CcHueviaNcpPhotoGeometry_get_NONE(),_root,task);
    NSString *value=[CcHueviaSharedSharedCleanup analyzeWithCcHueviaNcpSpatialPreviewFilter_Pixels:source withCcHueviaNcpSpatialPreviewFilter_Pixels:overview withJavaUtilFunctionBooleanSupplier:task];
    check(task);[_runtime guardOwnerWithNSString:owner];[_runtime validateSourceWithNSString:path withNSString:sha];
    return [NSJSONSerialization JSONObjectWithData:[value dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
  }
  BOOL paired=[operation isEqual:@"media.exportPreview"];if(paired)[self closeExportPreview];
  BOOL originalView=[operation isEqualToString:@"media.originalPreview"],preview=originalView||[operation isEqualToString:@"media.preview"];if(!preview&&![operation isEqualToString:@"media.export"]&&!paired)fail(@"未知的照片操作。");
  id requestedEdge=p[@"maxEdge"];if(requestedEdge&&![requestedEdge isKindOfClass:NSNumber.class])fail(@"预览边长无效。");
  double edge=requestedEdge?[requestedEdge doubleValue]:1280;if(!std::isfinite(edge)||edge!=std::floor(edge)||edge<128||edge>1280)fail(@"预览边长必须在 128 到 1280 之间。");int previewEdge=(int)edge;
  if(!originalView&&![p[@"recipe"] isKindOfClass:NSDictionary.class])fail(@"编辑设置无效。");
  NSString *owner=p[@"owner"]?:@"";if(![owner isKindOfClass:NSString.class]||owner.length>64)fail(@"编辑账号数据无效。");
  CcHueviaAlbumPhotoEditStore_Draft *frozen=originalView?[_runtime originalViewWithNSString:path withNSString:owner]:[_runtime freezeEditWithNSString:path withNSString:owner withNSString:json(p[@"recipe"])];
  if(!preview)[_runtime validateSourceWithNSString:path withNSString:frozen->sourceSha_];
  NSString *colorStatus=@"";HueviaRaster *working=raw?[self raw:path owner:owner settings:[CcHueviaSharedSharedRawSettings parseWithNSString:@"{}"] task:task status:&colorStatus]:load(path,_root,preview?previewEdge:0);
  if(raw&&preview){double scale=std::min(1.0,previewEdge/(double)std::max(working.pixelWidth,working.pixelHeight));working=scaled(working,std::max(1,int(std::lround(working.pixelWidth*scale))),std::max(1,int(std::lround(working.pixelHeight*scale))),_root);}
  id<CcHueviaNcpPresetPreviewProfile> profile=[frozen profile];
  int fullWidth=[metadata[(__bridge id)kCGImagePropertyPixelWidth] intValue],fullHeight=[metadata[(__bridge id)kCGImagePropertyPixelHeight] intValue];
  int exif=[metadata[(__bridge id)kCGImagePropertyOrientation] intValue];if(exif<1||exif>8)exif=1;
  CcHueviaNcpPhotoGeometry_Plan *fullPlan=[frozen->geometry_ planWithInt:(fullWidth>0?fullWidth:working.pixelWidth) withInt:(fullHeight>0?fullHeight:working.pixelHeight) withInt:exif];
  [profile renderPixelsWithCcHueviaNcpSpatialPreviewFilter_Pixels:working withJavaUtilFunctionBooleanSupplier:task withJavaUtilFunctionDoubleConsumer:task];
  check(task);working=compose(working,frozen->geometry_,_root,task);
  working=[HueviaFrames apply:working border:frozen->border_ capture:[[CcHueviaSharedSharedCaptureInfo alloc] initWithNSString:json(captureData(metadata))] root:_root task:task];
  CcHueviaAlbumPhotoExportSpec *spec=preview||[p[@"size"] isEqual:@"share"]?[CcHueviaAlbumPhotoExportSpec share]:[CcHueviaAlbumPhotoExportSpec full];
  if(!preview&&[p[@"size"] isEqual:@"custom"]){if(![p[@"longEdge"] isKindOfClass:NSNumber.class]||![p[@"quality"] isKindOfClass:NSNumber.class])fail(@"自定义导出设置无效。");spec=[CcHueviaAlbumPhotoExportSpec customWithInt:[p[@"longEdge"] intValue] withInt:[p[@"quality"] intValue]];}
  CcHueviaAlbumPhotoExportSpec_Resolved *resolved=[spec resolveWithInt:working.pixelWidth withInt:working.pixelHeight];working=scaled(working,resolved->width_,resolved->height_,_root);check(task);
  NSString *directory=[_root stringByAppendingPathComponent:preview?@"previews":@"exports"];if(![NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil])fail(@"无法创建照片导出目录。");
  NSString *name=NSUUID.UUID.UUIDString,*temporary=[directory stringByAppendingPathComponent:[name stringByAppendingString:@".part"]],*target=[directory stringByAppendingPathComponent:[name stringByAppendingString:@".jpg"]];
  if(paired){
    [self closeExportPreview];HueviaExportSession *session=[HueviaExportSession new];session.identifier=NSUUID.UUID.UUIDString;session.owner=owner;session.source=path;session.draft=frozen;
    session.folder=[[_root stringByAppendingPathComponent:@"previews"] stringByAppendingPathComponent:[@"export-" stringByAppendingString:session.identifier]];
    if(![[session.folder stringByResolvingSymlinksInPath] isEqual:session.folder])fail(@"成品预览目录不可用。");
    if(![NSFileManager.defaultManager createDirectoryAtPath:session.folder withIntermediateDirectories:YES attributes:nil error:nil])fail(@"无法创建成品预览目录。");
    session.jpeg=[session.folder stringByAppendingPathComponent:@"encoded.jpg"];session.reference=[session.folder stringByAppendingPathComponent:@"reference.png"];
    @try{
      encode(working,session.reference,YES,@{});check(task);
      encode(working,session.jpeg,NO,safeMetadata(metadata,working.pixelWidth,working.pixelHeight,resolved->quality_/100.0));check(task);
      [_runtime guardOwnerWithNSString:owner];[_runtime validateSourceWithNSString:path withNSString:frozen->sourceSha_];
      session.before=working;session.after=load(session.jpeg,_root,0);session.sourceAttributes=[NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
      if(session.before.pixelWidth!=session.after.pixelWidth||session.before.pixelHeight!=session.after.pixelHeight)fail(@"成品与编码前尺寸不符。");
      session.model=[CcHueviaSharedSharedExportModel ofWithCcHueviaNcpPresetPreviewProfile:profile withCcHueviaAlbumPhotoExportSpec_Resolved:resolved];session.spec=[resolved identity];
      double overviewScale=std::min(1.0,256.0/std::max(working.pixelWidth,working.pixelHeight));
      int ow=std::max(1,(int)std::round(working.pixelWidth*overviewScale)),oh=std::max(1,(int)std::round(working.pixelHeight*overviewScale));
      NSString *overview=[self exportFrame:session.after width:ow height:oh scale:std::min(ow/(double)working.pixelWidth,oh/(double)working.pixelHeight) cx:working.pixelWidth/2.0 cy:working.pixelHeight/2.0 folder:session.folder task:task];
      _exportSession=session;return @{@"id":session.identifier,@"width":@(working.pixelWidth),@"height":@(working.pixelHeight),@"overview":overview,@"bytes":[NSFileManager.defaultManager attributesOfItemAtPath:session.jpeg error:nil][NSFileSize]?:@0,@"quality":@(resolved->quality_),@"sha256":hashFile(session.jpeg,task),@"exportSpec":session.spec};
    }@catch(id error){if(_exportSession==session)_exportSession=nil;[NSFileManager.defaultManager removeItemAtPath:session.folder error:nil];@throw error;}
  }
  @try{encode(working,temporary,NO,safeMetadata(metadata,working.pixelWidth,working.pixelHeight,resolved->quality_/100.0));check(task);[_runtime guardOwnerWithNSString:owner];if(!preview)[_runtime validateSourceWithNSString:path withNSString:frozen->sourceSha_];if(![NSFileManager.defaultManager moveItemAtPath:temporary toPath:target error:nil])fail(@"无法保存效果图。");}@finally{[NSFileManager.defaultManager removeItemAtPath:temporary error:nil];}
  [task acceptWithDouble:1];NSDictionary *attributes=[NSFileManager.defaultManager attributesOfItemAtPath:target error:nil];NSDictionary *result=@{@"path":target,@"width":@(working.pixelWidth),@"height":@(working.pixelHeight),@"geometryWidth":@(fullPlan->width_),@"geometryHeight":@(fullPlan->height_),@"bytes":attributes[NSFileSize]?:@0,@"preview":@(preview),@"model":preview?[profile modelVersion]:[CcHueviaSharedSharedExportModel ofWithCcHueviaNcpPresetPreviewProfile:profile withCcHueviaAlbumPhotoExportSpec_Resolved:resolved],@"exportSpec":preview?@"":[resolved identity],@"rawColorStatus":colorStatus};
  if(!preview){@try{NSString *saved=[_runtime commitVersionWithNSString:path withNSString:owner withCcHueviaAlbumPhotoEditStore_Draft:frozen withNSString:target withNSString:json(result) withJavaUtilFunctionBooleanSupplier:task];[_runtime markEditExportedWithNSString:owner withCcHueviaAlbumPhotoEditStore_Draft:frozen];return [NSJSONSerialization JSONObjectWithData:[saved dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];}@finally{[NSFileManager.defaultManager removeItemAtPath:target error:nil];}}
  return result;
}
@end
