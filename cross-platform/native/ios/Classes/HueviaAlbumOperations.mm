#import "HueviaAlbumOperations.h"
#import <Photos/Photos.h>
#import <CommonCrypto/CommonDigest.h>
#import "cc/huevia/shared/SharedRuntime.h"
#import "java/io/IOException.h"
#import "java/io/InterruptedIOException.h"
namespace {
void fail(NSString *s){@throw [[JavaIoIOException alloc] initWithNSString:s];}
void check(HueviaTask *t){if(t.cancelled)@throw [[JavaIoInterruptedIOException alloc] initWithNSString:@"删除已停止，已完成的系统操作仍然保留。"] ;}
NSString *hash(NSString *s){NSData *d=[s dataUsingEncoding:NSUTF8StringEncoding];unsigned char digest[CC_SHA256_DIGEST_LENGTH];CC_SHA256(d.bytes,(CC_LONG)d.length,digest);NSMutableString *out=[NSMutableString string];for(int i=0;i<CC_SHA256_DIGEST_LENGTH;i++)[out appendFormat:@"%02x",digest[i]];return out;}
void write(NSString *path,NSDictionary *v){NSData *data=[NSJSONSerialization dataWithJSONObject:v options:0 error:nil];NSError *error=nil;if(!data||![data writeToFile:path options:NSDataWritingAtomic error:&error])fail(error.localizedDescription?:@"无法保存删除任务。");}
BOOL readAccess(){PHAuthorizationStatus s=[PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelReadWrite];return s==PHAuthorizationStatusAuthorized||s==PHAuthorizationStatusLimited;}
void verify(PHAsset *asset,NSDictionary *row,HueviaTask *task){
  NSString *expected=row[@"sha256"];unsigned long long bytes=[row[@"bytes"] unsignedLongLongValue];if(![expected isKindOfClass:NSString.class]||expected.length!=64||bytes<4||bytes>512ULL*1024*1024)fail(@"系统副本校验记录无效。");
  PHAssetResource *resource=nil;for(PHAssetResource *candidate in [PHAssetResource assetResourcesForAsset:asset])if(candidate.type==PHAssetResourceTypePhoto){resource=candidate;break;}if(!resource)fail(@"无法读取系统副本原始资源。");
  __block CC_SHA256_CTX digest;CC_SHA256_Init(&digest);__block unsigned long long total=0;__block BOOL accepting=YES;__block NSError *failure=nil;NSLock *lock=[NSLock new];dispatch_semaphore_t done=dispatch_semaphore_create(0);PHAssetResourceRequestOptions *options=[PHAssetResourceRequestOptions new];options.networkAccessAllowed=YES;
  PHAssetResourceDataRequestID request=[PHAssetResourceManager.defaultManager requestDataForAssetResource:resource options:options dataReceivedHandler:^(NSData *data){[lock lock];if(accepting){total+=data.length;if(total>bytes){failure=[NSError errorWithDomain:@"HueviaDelete" code:1 userInfo:nil];accepting=NO;}else CC_SHA256_Update(&digest,data.bytes,(CC_LONG)data.length);}[lock unlock];} completionHandler:^(NSError *error){[lock lock];if(error)failure=error;accepting=NO;[lock unlock];dispatch_semaphore_signal(done);}];
  while(dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC))!=0){if(task.cancelled){[lock lock];accepting=NO;[lock unlock];[PHAssetResourceManager.defaultManager cancelDataRequest:request];check(task);}}
  check(task);if(failure||total!=bytes)fail(@"系统副本内容或授权已变化，未加入删除范围。");unsigned char hashBytes[CC_SHA256_DIGEST_LENGTH];CC_SHA256_Final(hashBytes,&digest);NSMutableString *actual=[NSMutableString string];for(int i=0;i<CC_SHA256_DIGEST_LENGTH;i++)[actual appendFormat:@"%02x",hashBytes[i]];if(![actual isEqual:expected])fail(@"系统副本已被修改，未加入删除范围。");
}
}
@interface HueviaAlbumOperations ()
@property(nonatomic,copy) NSString *root;
@property(nonatomic,strong) CcHueviaSharedSharedRuntime *runtime;
@end
@implementation HueviaAlbumOperations
- (instancetype)initWithRoot:(NSString *)root runtime:(CcHueviaSharedSharedRuntime *)runtime {self=[super init];if(self){_root=[root copy];_runtime=runtime;}return self;}
- (NSDictionary *)request:(NSString *)operation payload:(NSDictionary *)p task:(HueviaTask *)task {
  NSString *owner=p[@"owner"];if(![owner isKindOfClass:NSString.class]||owner.length>64)fail(@"删除账号无效。");[self.runtime guardOwnerWithNSString:owner];check(task);
  if([operation isEqual:@"gallery.publishedCopies"]){
    if(!readAccess())fail(@"请允许读取系统相册后核对待删除副本。");
    NSArray *versions=p[@"versionIds"];if(![versions isKindOfClass:NSArray.class]||versions.count>1000)fail(@"成品范围无效。");NSMutableSet *selected=[NSMutableSet setWithArray:versions];NSMutableArray *ids=[NSMutableArray array];
    NSString *sourcePath=p[@"path"],*sourceSha=p[@"sourceSha"];if(sourcePath){if(![sourcePath isKindOfClass:NSString.class]||![sourceSha isKindOfClass:NSString.class]||sourceSha.length!=64)fail(@"原图删除范围无效。");NSString *originals=[self.root stringByAppendingPathComponent:@"originals"];if(![[sourcePath stringByDeletingLastPathComponent] isEqual:originals])fail(@"只能选择应用内原始照片。");[self.runtime validateSourceWithNSString:sourcePath withNSString:sourceSha];NSString *records=[[self.root stringByAppendingPathComponent:@"source-publications"] stringByAppendingPathComponent:hash(owner)];if(![[records stringByResolvingSymlinksInPath] isEqual:records])fail(@"原图保存记录路径无效。");for(NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:records error:nil]){if(![name hasSuffix:@".json"])continue;NSString *file=[records stringByAppendingPathComponent:name];NSDictionary *attrs=[NSFileManager.defaultManager attributesOfItemAtPath:file error:nil];if(![attrs[NSFileType] isEqual:NSFileTypeRegular]||[attrs[NSFileSize] unsignedLongLongValue]>8192)continue;NSDictionary *row=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:file] options:0 error:nil];if([row[@"sourceSha"] isEqual:sourceSha]&&[row[@"id"] isKindOfClass:NSString.class])[selected addObject:row[@"id"]];}}
    NSString *folder=[[self.root stringByAppendingPathComponent:@"gallery-publications"] stringByAppendingPathComponent:hash(owner)];if(![[folder stringByResolvingSymlinksInPath] isEqual:folder])fail(@"相册保存记录路径无效。");
    for(NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:folder error:nil]){check(task);if(![name hasSuffix:@".json"])continue;NSString *path=[folder stringByAppendingPathComponent:name];NSDictionary *attrs=[NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];if(![attrs[NSFileType] isEqual:NSFileTypeRegular]||[attrs[NSFileSize] unsignedLongLongValue]>32768)continue;NSDictionary *row=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:path] options:0 error:nil];NSString *version=[name componentsSeparatedByString:@"-"].firstObject;version=[version stringByDeletingPathExtension];NSString *identifier=row[@"asset"];if([selected containsObject:version]&&[row[@"state"] isEqual:@"complete"]&&[identifier isKindOfClass:NSString.class]&&identifier.length){PHAsset *asset=[PHAsset fetchAssetsWithLocalIdentifiers:@[identifier] options:nil].firstObject;if(!asset){if([PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelReadWrite]==PHAuthorizationStatusLimited)fail(@"部分副本不在当前照片授权范围内，请调整授权后重试。");continue;}verify(asset,row,task);if(![ids containsObject:identifier])[ids addObject:identifier];}}
    return @{@"ids":ids,@"scope":@"recorded-export-copies"};
  }
  if(![operation isEqual:@"gallery.delete"])fail(@"未知的系统相册任务。");
  NSString *identity=p[@"operationId"];NSArray *ids=p[@"ids"];NSRegularExpression *pattern=[NSRegularExpression regularExpressionWithPattern:@"^[0-9a-f]{32}$" options:0 error:nil];
  if(![identity isKindOfClass:NSString.class]||[pattern numberOfMatchesInString:identity options:0 range:NSMakeRange(0,identity.length)]!=1||![ids isKindOfClass:NSArray.class]||ids.count<1||ids.count>100||[NSSet setWithArray:ids].count!=ids.count)fail(@"删除任务或照片范围无效。");
  for(id identifier in ids)if(![identifier isKindOfClass:NSString.class]||[identifier length]<1||[identifier length]>2048)fail(@"系统照片标识无效。");
  NSString *directory=[self.root stringByAppendingPathComponent:@"system-album-deletions"];if(![[directory stringByResolvingSymlinksInPath] isEqual:directory]||![NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil])fail(@"无法创建删除任务记录。");
  NSString *path=[directory stringByAppendingPathComponent:[identity stringByAppendingString:@".json"]];if(![[path stringByResolvingSymlinksInPath] isEqual:path])fail(@"删除任务路径无效。");
  NSMutableDictionary *plan=nil;NSData *saved=[NSData dataWithContentsOfFile:path];if(saved){if(saved.length>32768)fail(@"删除任务记录过大。");plan=[[NSJSONSerialization JSONObjectWithData:saved options:0 error:nil] mutableCopy];if(![plan[@"owner"] isEqual:owner]||![plan[@"ids"] isEqual:ids])fail(@"删除任务与当前范围不符。");if([plan[@"deleted"] boolValue])return plan;}
  if(!readAccess())fail(@"请允许读写系统照片后重试删除。");
  PHFetchResult<PHAsset *> *assets=[PHAsset fetchAssetsWithLocalIdentifiers:ids options:nil];
  if(!plan&&assets.count!=ids.count)fail(@"照片访问范围已变化，请刷新后重新选择。");
  if(!plan){plan=[@{@"owner":owner,@"ids":ids,@"deleted":@NO} mutableCopy];write(path,plan);}
  if(assets.count){
    check(task);[self.runtime guardOwnerWithNSString:owner];__block NSError *failure=nil;__block BOOL success=NO;dispatch_semaphore_t done=dispatch_semaphore_create(0);
    [PHPhotoLibrary.sharedPhotoLibrary performChanges:^{[PHAssetChangeRequest deleteAssets:assets];} completionHandler:^(BOOL ok,NSError *error){success=ok;failure=error;dispatch_semaphore_signal(done);}];
    // PhotoKit's user confirmation owns this transaction. Preserve its receipt even
    // if the page cancels while the system confirmation is visible.
    while(dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC))!=0){}
    if(!success)fail(failure.localizedDescription?:@"系统删除已取消。");
  }
  if(!readAccess())fail(@"照片权限已变化，删除结果尚待核对。");
  if([PHAsset fetchAssetsWithLocalIdentifiers:ids options:nil].count)fail(@"系统仍保留部分照片，请重试。");
  plan[@"deleted"]=@YES;write(path,plan);return plan;
}
@end
