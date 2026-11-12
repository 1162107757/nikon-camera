#import "HueviaPublication.h"
#import <Photos/Photos.h>
#import <ImageIO/ImageIO.h>
#import <CommonCrypto/CommonDigest.h>
#include <cmath>
#import "cc/huevia/shared/SharedRuntime.h"
#import "java/io/IOException.h"
#import "java/io/InterruptedIOException.h"

namespace {
void publicationFail(NSString *message){@throw [[JavaIoIOException alloc] initWithNSString:message];}
void publicationCheck(HueviaTask *task){if(task.cancelled)@throw [[JavaIoInterruptedIOException alloc] initWithNSString:@"保存照片已取消，应用内成品仍然保留。"];}
NSString *publicationJson(NSDictionary *value){return [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:value options:0 error:nil] encoding:NSUTF8StringEncoding];}
BOOL publicationHex(NSString *value,NSUInteger length){return [value isKindOfClass:NSString.class]&&value.length==length&&[value rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"].invertedSet].location==NSNotFound;}
NSString *publicationHash(NSString *text){NSData *data=[text dataUsingEncoding:NSUTF8StringEncoding];unsigned char digest[CC_SHA256_DIGEST_LENGTH];CC_SHA256(data.bytes,(CC_LONG)data.length,digest);NSMutableString *s=[NSMutableString string];for(int i=0;i<CC_SHA256_DIGEST_LENGTH;i++)[s appendFormat:@"%02x",digest[i]];return s;}
NSString *publicationDirectory(NSString *root,NSString *component){
  NSString *base=root.stringByResolvingSymlinksInPath,*path=[base stringByAppendingPathComponent:component];
  NSFileManager *fm=NSFileManager.defaultManager;NSDictionary *attrs=[fm attributesOfItemAtPath:path error:nil];
  if(attrs&&![attrs[NSFileType] isEqual:NSFileTypeDirectory])publicationFail(@"保存记录目录无效。");
  if(![[path stringByResolvingSymlinksInPath] isEqualToString:path])publicationFail(@"保存记录目录不能是链接。");
  NSError *error=nil;if(!attrs&&![fm createDirectoryAtPath:path withIntermediateDirectories:NO attributes:nil error:&error])publicationFail(@"无法创建保存记录，请检查存储空间后重试。");
  return path;
}
NSDictionary *publicationRead(NSString *path){
  NSDictionary *attrs=[NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];if(!attrs)return nil;
  if(![attrs[NSFileType] isEqual:NSFileTypeRegular]||[attrs[NSFileSize] unsignedLongLongValue]>8192)publicationFail(@"保存记录无效，未重复保存。");
  NSData *data=[NSData dataWithContentsOfFile:path];NSDictionary *record=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
  if(![record isKindOfClass:NSDictionary.class]||![record[@"schema"] isEqual:@1])publicationFail(@"保存记录不可读取，未重复保存。");return record;
}
BOOL publicationWrite(NSString *path,NSDictionary *record,NSError **error){
  NSData *data=[NSJSONSerialization dataWithJSONObject:record options:0 error:error];return data&&[data writeToFile:path options:NSDataWritingAtomic error:error];
}
BOOL publicationMatches(NSString *path,NSString *token){
  // This helper runs on PhotoKit's completion queue: never throw across that
  // framework callback, even if a journal becomes unreadable after saving.
  NSDictionary *attrs=[NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
  if(![attrs[NSFileType] isEqual:NSFileTypeRegular]||[attrs[NSFileSize] unsignedLongLongValue]>8192)return NO;
  NSData *data=[NSData dataWithContentsOfFile:path];id record=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
  return [record isKindOfClass:NSDictionary.class]&&[record[@"token"] isEqual:token];
}
NSString *publicationFileHash(NSString *path,HueviaTask *task){
  NSInputStream *input=[NSInputStream inputStreamWithFileAtPath:path];[input open];
  CC_SHA256_CTX context;CC_SHA256_Init(&context);uint8_t buffer[65536];unsigned long long total=0;
  @try {for(;;){publicationCheck(task);NSInteger n=[input read:buffer maxLength:sizeof(buffer)];if(n<0)publicationFail(@"无法核对导出副本。");if(n==0)break;
    total+=n;if(total>512ULL*1024*1024)publicationFail(@"导出副本超出大小限制。");CC_SHA256_Update(&context,buffer,(CC_LONG)n);}}
  @finally {[input close];}
  unsigned char digest[CC_SHA256_DIGEST_LENGTH];CC_SHA256_Final(digest,&context);NSMutableString *result=[NSMutableString string];for(unsigned char b:digest)[result appendFormat:@"%02x",b];return result;
}
void publicationCleanup(NSString *path,NSDictionary *record,HueviaTask *task){
  NSDictionary *attrs=[NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
  if([attrs[NSFileType] isEqual:NSFileTypeRegular]&&[attrs[NSFileSize] isEqual:record[@"bytes"]]&&
      [publicationFileHash(path,task) isEqual:record[@"sha256"]])[NSFileManager.defaultManager removeItemAtPath:path error:nil];
}
void publicationDatedCopy(NSString *source,NSString *target,NSDate *date,HueviaTask *task){
  // Apple's QA1895: CopyImageSource edits JPEG metadata without recompression.
  // https://developer.apple.com/library/archive/qa/qa1895/_index.html
  publicationCheck(task);NSFileManager *fm=NSFileManager.defaultManager;
  if(![target.stringByResolvingSymlinksInPath isEqual:target])publicationFail(@"导出副本不能是链接。");
  NSString *temporary=[target.stringByDeletingLastPathComponent stringByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingString:@".part"]];
  CGImageSourceRef image=CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:source],(__bridge CFDictionaryRef)@{(id)kCGImageSourceShouldCache:@NO});
  if(!image)publicationFail(@"成品图像不能读取。");
  CGImageDestinationRef destination=NULL;CGImageMetadataRef metadata=NULL;CGMutableImageMetadataRef updated=NULL;
  @try {
    if(!CGImageSourceGetType(image)||!CFEqual(CGImageSourceGetType(image),CFSTR("public.jpeg")))publicationFail(@"成品不是 JPEG。");
    metadata=CGImageSourceCopyMetadataAtIndex(image,0,NULL);updated=metadata?CGImageMetadataCreateMutableCopy(metadata):CGImageMetadataCreateMutable();
    NSDateFormatter *format=[NSDateFormatter new];format.locale=[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];format.timeZone=[NSTimeZone timeZoneForSecondsFromGMT:0];format.dateFormat=@"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'";
    NSString *clock=[format stringFromDate:date];
    BOOL valid=updated&&CGImageMetadataSetValueMatchingImageProperty(updated,kCGImagePropertyTIFFDictionary,kCGImagePropertyTIFFDateTime,(__bridge CFTypeRef)clock)
      &&CGImageMetadataSetValueMatchingImageProperty(updated,kCGImagePropertyExifDictionary,kCGImagePropertyExifDateTimeOriginal,(__bridge CFTypeRef)clock)
      &&CGImageMetadataSetValueMatchingImageProperty(updated,kCGImagePropertyExifDictionary,kCGImagePropertyExifDateTimeDigitized,(__bridge CFTypeRef)clock);
    if(!valid)publicationFail(@"无法记录本次导出时间，未保存副本。");
    destination=CGImageDestinationCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:temporary],CFSTR("public.jpeg"),1,NULL);
    // DateTime is mutually exclusive with Metadata (and does not accept NSDate).
    // Supply the three updated date tags through the metadata object alone.
    // https://developer.apple.com/documentation/imageio/kcgimagedestinationdatetime
    CFErrorRef error=NULL;NSDictionary *options=@{(id)kCGImageDestinationMetadata:(__bridge id)updated,(id)kCGImageDestinationMergeMetadata:@YES,(id)kCGImageMetadataShouldExcludeGPS:@YES};
    BOOL copied=destination&&CGImageDestinationCopyImageSource(destination,image,(__bridge CFDictionaryRef)options,&error);if(error)CFRelease(error);
    if(!copied)publicationFail(@"无法写入导出时间，原成品仍保留。");
    CGImageSourceRef checked=CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:temporary],(__bridge CFDictionaryRef)@{(id)kCGImageSourceShouldCache:@NO});
    NSDictionary *properties=checked?CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(checked,0,NULL)):nil;if(checked)CFRelease(checked);
    format.dateFormat=@"yyyy:MM:dd HH:mm:ss";NSString *expected=[format stringFromDate:date];
    NSDictionary *tiff=properties[(id)kCGImagePropertyTIFFDictionary],*exif=properties[(id)kCGImagePropertyExifDictionary];
    if(![tiff[(id)kCGImagePropertyTIFFDateTime] isEqual:expected]||![exif[(id)kCGImagePropertyExifDateTimeOriginal] isEqual:expected]||![exif[(id)kCGImagePropertyExifDateTimeDigitized] isEqual:expected])publicationFail(@"导出时间未能核对，原成品仍保留。");
    publicationCheck(task);
    if([fm fileExistsAtPath:target]){
      if(![publicationFileHash(target,task) isEqual:publicationFileHash(temporary,task)])publicationFail(@"暂存副本已变化，未覆盖或删除。");
    }else if(![fm moveItemAtPath:temporary toPath:target error:nil])publicationFail(@"无法保存导出副本，请检查存储空间。");
  } @finally {if(destination)CFRelease(destination);if(updated)CFRelease(updated);if(metadata)CFRelease(metadata);CFRelease(image);[fm removeItemAtPath:temporary error:nil];}
}
void publicationVerify(PHAsset *asset,NSString *sha,unsigned long long expected,HueviaTask *task){
  PHAssetResource *photo=nil;for(PHAssetResource *resource in [PHAssetResource assetResourcesForAsset:asset]){
    if(resource.type==PHAssetResourceTypeAdjustmentData)publicationFail(@"相册副本已被编辑，未覆盖或重复保存。");
    if(resource.type==PHAssetResourceTypePhoto)photo=resource;
  }
  if(!photo)publicationFail(@"无法核对相册副本，未重复保存。");
  __block CC_SHA256_CTX context;CC_SHA256_Init(&context);__block unsigned long long total=0;__block NSError *failure=nil;
  dispatch_semaphore_t done=dispatch_semaphore_create(0);PHAssetResourceRequestOptions *options=[PHAssetResourceRequestOptions new];options.networkAccessAllowed=NO;
  PHAssetResourceDataRequestID request=[PHAssetResourceManager.defaultManager requestDataForAssetResource:photo options:options dataReceivedHandler:^(NSData *data){
    total+=data.length;if(total>expected){failure=[NSError errorWithDomain:@"HueviaPublication" code:2 userInfo:@{NSLocalizedDescriptionKey:@"相册副本内容已变化。"}];return;}
    CC_SHA256_Update(&context,data.bytes,(CC_LONG)data.length);
  } completionHandler:^(NSError *error){if(error)failure=error;dispatch_semaphore_signal(done);}];
  CFAbsoluteTime deadline=CFAbsoluteTimeGetCurrent()+60;
  while(dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,50*NSEC_PER_MSEC))!=0){
    if(task.cancelled||CFAbsoluteTimeGetCurrent()>deadline){[PHAssetResourceManager.defaultManager cancelDataRequest:request];publicationCheck(task);publicationFail(@"相册副本暂时无法核对，未重复保存，请稍后重试。");}
  }
  publicationCheck(task);if(failure)publicationFail(@"相册副本暂时无法读取或内容已变化，未覆盖或重复保存。");
  unsigned char bytes[CC_SHA256_DIGEST_LENGTH];CC_SHA256_Final(bytes,&context);NSMutableString *actual=[NSMutableString string];for(int i=0;i<CC_SHA256_DIGEST_LENGTH;i++)[actual appendFormat:@"%02x",bytes[i]];
  if(total!=expected||![actual isEqual:sha])publicationFail(@"相册副本内容已变化，未覆盖或重复保存。");
}
NSString *publicationName(NSString *value,NSString *version){
  if(![value isKindOfClass:NSString.class])value=@"";
  NSMutableCharacterSet *bad=[NSCharacterSet.controlCharacterSet mutableCopy];[bad addCharactersInString:@"/\\"];
  NSString *name=[[value componentsSeparatedByCharactersInSet:bad] componentsJoinedByString:@"_"];
  name=[name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  while([name lengthOfBytesUsingEncoding:NSUTF8StringEncoding]>180){NSRange range=[name rangeOfComposedCharacterSequenceAtIndex:name.length-1];name=[name substringToIndex:range.location];}
  if(!name.length)name=[NSString stringWithFormat:@"Huevia-%@.jpg",[version substringToIndex:12]];
  if(![@[@"jpg",@"jpeg"] containsObject:name.pathExtension.lowercaseString])name=[name stringByAppendingString:@".jpg"];return name;
}
NSDate *publicationCaptureDate(NSURL *url){
  CGImageSourceRef image=CGImageSourceCreateWithURL((__bridge CFURLRef)url,(__bridge CFDictionaryRef)@{(id)kCGImageSourceShouldCache:@NO});if(!image)return nil;
  NSDictionary *properties=CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(image,0,NULL));CFRelease(image);
  NSDictionary *exif=properties[(id)kCGImagePropertyExifDictionary],*tiff=properties[(id)kCGImagePropertyTIFFDictionary];
  NSString *clock=exif[(id)kCGImagePropertyExifDateTimeOriginal]?:tiff[(id)kCGImagePropertyTIFFDateTime];
  if(![clock isKindOfClass:NSString.class]||clock.length!=19)return nil;
  NSDateFormatter *format=[NSDateFormatter new];format.locale=[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];format.dateFormat=@"yyyy:MM:dd HH:mm:ss";format.lenient=NO;
  NSString *offset=exif[@"OffsetTimeOriginal"];format.timeZone=NSTimeZone.localTimeZone;
  if([offset isKindOfClass:NSString.class]&&offset.length==6&&[offset rangeOfString:@"^[+-][0-9]{2}:[0-9]{2}$" options:NSRegularExpressionSearch].location!=NSNotFound){
    NSInteger hours=[[offset substringWithRange:NSMakeRange(1,2)] integerValue],minutes=[[offset substringFromIndex:4] integerValue];
    if(hours<=14&&minutes<60&&(hours<14||minutes==0)){NSInteger seconds=(hours*60+minutes)*60;if([offset hasPrefix:@"-"])seconds=-seconds;format.timeZone=[NSTimeZone timeZoneForSecondsFromGMT:seconds];}
  }
  return [format dateFromString:clock];
}
}

@interface HueviaPublication ()
@property(nonatomic,copy) NSString *root;
@property(nonatomic,strong) CcHueviaSharedSharedRuntime *runtime;
- (NSDictionary *)publish:(NSDictionary *)p task:(HueviaTask *)task original:(BOOL)original;
@end
@implementation HueviaPublication
- (instancetype)initWithRoot:(NSString *)root runtime:(CcHueviaSharedSharedRuntime *)runtime {self=[super init];if(self){_root=[root copy];_runtime=runtime;}return self;}
+ (NSDictionary *)saveAccess {PHAuthorizationStatus state=[PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelAddOnly];return @{@"granted":@(state==PHAuthorizationStatusAuthorized||state==PHAuthorizationStatusLimited),@"canAsk":@(state==PHAuthorizationStatusNotDetermined)};}
+ (void)requestSavePermission:(void (^)(NSDictionary *))reply {
  if([PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelAddOnly]!=PHAuthorizationStatusNotDetermined){reply([self saveAccess]);return;}
  [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelAddOnly handler:^(PHAuthorizationStatus state){dispatch_async(dispatch_get_main_queue(),^{reply([self saveAccess]);});}];
}
- (NSDictionary *)publish:(NSDictionary *)p task:(HueviaTask *)task {
  return [self publish:p task:task original:NO];
}
- (NSDictionary *)publishOriginal:(NSDictionary *)p task:(HueviaTask *)task {
  return [self publish:p task:task original:YES];
}
- (NSDictionary *)publish:(NSDictionary *)p task:(HueviaTask *)task original:(BOOL)original {
  @synchronized(self){
    publicationCheck(task);NSString *owner=p[@"owner"],*version=p[@"id"];
    if(![owner isKindOfClass:NSString.class]||owner.length>64||(!original&&!publicationHex(version,64)))publicationFail(@"成品保存标识无效。");
    id extra=p[@"extraCopy"];if(extra&&CFGetTypeID((__bridge CFTypeRef)extra)!=CFBooleanGetTypeID())publicationFail(@"导出副本选项无效。");
    BOOL another=[extra boolValue];NSString *operation=p[@"operationId"];if(another&&!publicationHex(operation,32))publicationFail(@"副本保存标识无效，请重新操作。");
    if(original&&another)publicationFail(@"原始文件不能重新编码或改写拍摄信息。");
    [_runtime guardOwnerWithNSString:owner];
    if(![[self.class saveAccess][@"granted"] boolValue])publicationFail(@"请允许添加照片到系统相册后重试，应用内成品仍然保留。");
    NSString *opened=original?[_runtime prepareOriginalPublicationWithNSString:publicationJson(p) withJavaUtilFunctionBooleanSupplier:task]:[_runtime requestWithNSString:@"version.open" withNSString:publicationJson(@{@"owner":owner,@"id":version}) withJavaUtilFunctionBooleanSupplier:task withJavaUtilFunctionDoubleConsumer:task];
    NSDictionary *saved=[NSJSONSerialization JSONObjectWithData:[opened dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    if(original){version=saved[@"id"];if(!publicationHex(version,64))publicationFail(@"原始文件保存记录无效。");}
    NSString *source=saved[@"path"],*sha=saved[@"sha256"];unsigned long long bytes=[saved[@"bytes"] unsignedLongLongValue];
    if(![source isKindOfClass:NSString.class]||!publicationHex(sha,64)||bytes<4||bytes>512ULL*1024*1024)publicationFail(@"成品内容无效。");
    if(![[self.class saveAccess][@"granted"] boolValue])publicationFail(@"请允许添加照片到系统相册后重试，应用内成品仍然保留。");
    NSString *directory=publicationDirectory(publicationDirectory(self.root,@"gallery-publications"),publicationHash(owner));
    NSString *key=another?[NSString stringWithFormat:@"%@-%@",version,operation]:version,*journal=[directory stringByAppendingPathComponent:[key stringByAppendingString:@".json"]];
    NSDictionary *prior=publicationRead(journal);
    NSString *originalSha=sha,*frozen=[directory stringByAppendingPathComponent:[key stringByAppendingString:@".jpg"]];unsigned long long originalBytes=bytes;NSDate *capture=nil;
    if(another){
      if(prior&&(![prior[@"sourceSha"] isEqual:originalSha]||[prior[@"sourceBytes"] unsignedLongLongValue]!=originalBytes))publicationFail(@"导出记录与此成品不匹配，未重复保存。");
      id time=prior[@"date"];if(time&&(![time isKindOfClass:NSNumber.class]||!std::isfinite([time doubleValue])||[time doubleValue]<0||[time doubleValue]>7258118400.0))publicationFail(@"导出时间记录无效。");
      capture=time?[NSDate dateWithTimeIntervalSince1970:[time doubleValue]]:NSDate.date;
      if(!prior||[prior[@"state"] isEqual:@"preparing"]){
        if(!prior&&[NSFileManager.defaultManager fileExistsAtPath:frozen])publicationFail(@"导出暂存缺少记录，未覆盖或删除。");
        NSMutableDictionary *prepared=[@{@"schema":@1,@"state":@"preparing",@"asset":@"",@"sourceSha":originalSha,@"sourceBytes":@(originalBytes),@"date":@([capture timeIntervalSince1970])} mutableCopy];
        NSError *error=nil;if(!publicationWrite(journal,prepared,&error))publicationFail(@"无法记录导出副本，请检查存储空间。");
        publicationDatedCopy(source,frozen,capture,task);sha=publicationFileHash(frozen,task);bytes=[[NSFileManager.defaultManager attributesOfItemAtPath:frozen error:nil][NSFileSize] unsignedLongLongValue];
        if(bytes<4||bytes>512ULL*1024*1024)publicationFail(@"导出副本大小无效。");
        prepared[@"sha256"]=sha;prepared[@"bytes"]=@(bytes);prepared[@"state"]=@"prepared";
        if(!publicationWrite(journal,prepared,&error))publicationFail(@"导出副本记录暂不可写，请稍后重试。");prior=prepared;
      }else{sha=prior[@"sha256"];bytes=[prior[@"bytes"] unsignedLongLongValue];if(!publicationHex(sha,64)||bytes<4||bytes>512ULL*1024*1024)publicationFail(@"导出副本记录无效。");}
      source=frozen;
    }
    if(prior){
      if(![prior[@"sha256"] isEqual:sha]||[prior[@"bytes"] unsignedLongLongValue]!=bytes)publicationFail(@"保存记录与此成品不匹配，未覆盖或重复保存。");
      NSString *identifier=prior[@"asset"];BOOL complete=[prior[@"state"] isEqual:@"complete"];
      if(![identifier isKindOfClass:NSString.class])publicationFail(@"保存记录无效。");
      PHAuthorizationStatus read=[PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelReadWrite];
      if(identifier.length&&(read==PHAuthorizationStatusAuthorized||read==PHAuthorizationStatusLimited)){
        PHAsset *asset=[PHAsset fetchAssetsWithLocalIdentifiers:@[identifier] options:nil].firstObject;
        if(asset){
          publicationVerify(asset,sha,bytes,task);NSMutableDictionary *confirmed=[prior mutableCopy];confirmed[@"state"]=@"complete";
          NSError *error=nil;if(!publicationWrite(journal,confirmed,&error))publicationFail(@"相册副本已核对，但保存记录暂不可写，请稍后重试。");
          if(another)publicationCleanup(frozen,confirmed,task);
          if(original)[_runtime releaseOriginalPublicationWithNSString:publicationJson(@{@"owner":owner,@"operationId":operation,@"sha256":sha,@"bytes":@(bytes)})];
          [_runtime guardOwnerWithNSString:owner];return @{@"id":version,@"published":@YES,@"identifier":identifier,@"existing":@YES,@"verified":@YES};
        }
        if(read==PHAuthorizationStatusLimited)publicationFail(@"这份相册副本当前不在允许访问的范围内，未重复保存。");
        if(!complete)publicationFail(@"上次保存尚待系统确认，请稍后查看相册或重试。");
        publicationFail(@"此前保存的相册副本已不可访问，请重新发起导出。");
      }else if(identifier.length){
        if(complete){if(another)publicationCleanup(frozen,prior,task);if(original)[_runtime releaseOriginalPublicationWithNSString:publicationJson(@{@"owner":owner,@"operationId":operation,@"sha256":sha,@"bytes":@(bytes)})];[_runtime guardOwnerWithNSString:owner];return @{@"id":version,@"published":@YES,@"identifier":identifier,@"existing":@YES,@"verified":@NO};}
        publicationFail(@"上次保存尚待确认，请允许访问照片后重试，未重复保存。");
      }else if(!complete){[NSFileManager.defaultManager removeItemAtPath:journal error:nil];}
      else publicationFail(@"保存记录缺少相册标识，未重复保存。");
    }
    publicationCheck(task);[_runtime guardOwnerWithNSString:owner];
    NSString *token=NSUUID.UUID.UUIDString;NSMutableDictionary *record=[@{@"schema":@1,@"token":token,@"state":@"pending",@"asset":@"",@"sha256":sha,@"bytes":@(bytes)} mutableCopy];
    if(another){
      record[@"sourceSha"]=originalSha;record[@"sourceBytes"]=@(originalBytes);record[@"date"]=@([capture timeIntervalSince1970]);
      NSDictionary *attrs=[NSFileManager.defaultManager attributesOfItemAtPath:frozen error:nil];
      if(![attrs[NSFileType] isEqual:NSFileTypeRegular]||[attrs[NSFileSize] unsignedLongLongValue]!=bytes||![publicationFileHash(frozen,task) isEqual:sha])publicationFail(@"导出副本已变化，未覆盖或重复保存。");
    }
    NSError *error=nil;if(!publicationWrite(journal,record,&error))publicationFail(@"无法写入保存记录，请检查存储空间后重试。");
    NSString *name=publicationName(p[@"filename"],version);NSURL *url=[NSURL fileURLWithPath:source];if(!another)capture=publicationCaptureDate(url);
    __block NSString *identifier=nil;__block NSError *failure=nil;dispatch_semaphore_t done=dispatch_semaphore_create(0);
    [PHPhotoLibrary.sharedPhotoLibrary performChanges:^{
      @try {
      if(task.cancelled)return;
      PHAssetCreationRequest *request=[PHAssetCreationRequest creationRequestForAsset];identifier=request.placeholderForCreatedAsset.localIdentifier;
      if(!identifier.length){failure=[NSError errorWithDomain:@"HueviaPublication" code:3 userInfo:@{NSLocalizedDescriptionKey:@"系统未返回照片保存标识。"}];return;}
      record[@"asset"]=identifier;
      NSError *writeError=nil;if(!publicationWrite(journal,record,&writeError)){failure=writeError;return;}
      PHAssetResourceCreationOptions *options=[PHAssetResourceCreationOptions new];options.originalFilename=name;options.shouldMoveFile=NO;
      if(capture)request.creationDate=capture;
      request.location=nil;[request addResourceWithType:PHAssetResourceTypePhoto fileURL:url options:options];
      } @catch(NSException *exception) {failure=[NSError errorWithDomain:@"HueviaPublication" code:7 userInfo:@{NSLocalizedDescriptionKey:@"无法提交照片保存，请稍后重试。"}];}
    } completionHandler:^(BOOL success,NSError *saveError){
      @try {
        if(!success||failure||!identifier.length){
          failure=failure?:saveError?:[NSError errorWithDomain:@"HueviaPublication" code:4 userInfo:@{NSLocalizedDescriptionKey:@"照片尚未保存。"}];
          if(publicationMatches(journal,token))[NSFileManager.defaultManager removeItemAtPath:journal error:nil];
        }else{
          record[@"state"]=@"complete";NSError *writeError=nil;
          if(!publicationMatches(journal,token))failure=[NSError errorWithDomain:@"HueviaPublication" code:6 userInfo:@{NSLocalizedDescriptionKey:@"系统保存记录尚待确认。"}];
          else if(!publicationWrite(journal,record,&writeError))failure=writeError;
        }
      } @catch(NSException *exception) {failure=[NSError errorWithDomain:@"HueviaPublication" code:5 userInfo:@{NSLocalizedDescriptionKey:@"系统保存结果尚待确认，应用内成品仍然保留。"}];}
      dispatch_semaphore_signal(done);
    }];
    CFAbsoluteTime deadline=CFAbsoluteTimeGetCurrent()+120;
    while(dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,50*NSEC_PER_MSEC))!=0){
      // PhotoKit transactions cannot be undone once submitted. Its completion
      // persists the captured receipt even if the caller has left or cancelled.
      if(CFAbsoluteTimeGetCurrent()>deadline)publicationFail(@"系统仍在确认保存结果，请稍后查看相册或重试。");
    }
    publicationCheck(task);if(failure)publicationFail(@"保存到相册未完成或记录尚待确认，应用内成品仍然保留，请重试。");
    if(another)publicationCleanup(frozen,record,task);
    if(original)[_runtime releaseOriginalPublicationWithNSString:publicationJson(@{@"owner":owner,@"operationId":operation,@"sha256":sha,@"bytes":@(bytes)})];
    [_runtime guardOwnerWithNSString:owner];return @{@"id":version,@"published":@YES,@"identifier":identifier,@"existing":@NO,@"verified":@YES};
  }
}
@end
