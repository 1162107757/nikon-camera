#import "HueviaGallery.h"
#import "HueviaAlbumOperations.h"
#import "HueviaPublication.h"
#import "HueviaGalleryPreview.h"
#import <Photos/Photos.h>
#import <PhotosUI/PhotosUI.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <CommonCrypto/CommonDigest.h>
#import "cc/huevia/shared/SharedImport.h"
#import "java/io/FileInputStream.h"
#import "java/io/IOException.h"
#import "java/io/InterruptedIOException.h"

namespace {
void galleryFail(NSString *text){@throw [[JavaIoIOException alloc] initWithNSString:text];}
void galleryCheck(HueviaTask *task){if(task.cancelled)@throw [[JavaIoInterruptedIOException alloc] initWithNSString:@"照片读取已取消。"];}
BOOL canRead(){PHAuthorizationStatus s=[PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelReadWrite];return s==PHAuthorizationStatusAuthorized||s==PHAuthorizationStatusLimited;}
NSString *privateDirectory(NSString *root,NSString *name){NSString *path=[root stringByAppendingPathComponent:name];NSError *error=nil;if(![NSFileManager.defaultManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:&error]||![[path stringByResolvingSymlinksInPath] isEqualToString:[[root stringByResolvingSymlinksInPath] stringByAppendingPathComponent:name]])galleryFail(@"照片缓存目录不可用。");return path;}
NSString *digestText(NSString *text){NSData *d=[text dataUsingEncoding:NSUTF8StringEncoding];uint8_t sum[CC_SHA256_DIGEST_LENGTH];CC_SHA256(d.bytes,(CC_LONG)d.length,sum);NSMutableString *s=[NSMutableString string];for(uint8_t x:sum)[s appendFormat:@"%02x",x];return s;}
BOOL isRaw(PHAssetResource *r){
  UTType *type=[UTType typeWithIdentifier:r.uniformTypeIdentifier];
  return [type conformsToType:[UTType typeWithIdentifier:@"public.camera-raw-image"]]||[@[@"nef",@"nrw",@"dng",@"arw",@"cr2",@"cr3",@"raf",@"rw2",@"orf",@"pef",@"srw"] containsObject:r.originalFilename.pathExtension.lowercaseString];
}
PHAssetResource *originalResource(PHAsset *asset){
  PHAssetResource *photo=nil;
  for(PHAssetResource *resource in [PHAssetResource assetResourcesForAsset:asset]){
    if(asset.mediaType==PHAssetMediaTypeVideo&&(resource.type==PHAssetResourceTypeVideo||resource.type==PHAssetResourceTypeFullSizeVideo))return resource;
    if(resource.type!=PHAssetResourceTypePhoto&&resource.type!=PHAssetResourceTypeAlternatePhoto)continue;
    if(isRaw(resource))return resource;
    if(!photo||resource.type==PHAssetResourceTypePhoto)photo=resource;
  }
  return photo;
}
BOOL waitFor(dispatch_semaphore_t done,HueviaTask *task,NSTimeInterval limit){
  NSTimeInterval until=NSProcessInfo.processInfo.systemUptime+limit;
  while(dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC))!=0){if(task.cancelled||NSProcessInfo.processInfo.systemUptime>=until)return NO;}
  return YES;
}
}

@interface HueviaGallery () <PHPhotoLibraryChangeObserver>
@property(nonatomic,strong) HueviaAlbumOperations *albumOperations;
@property(nonatomic,copy) NSString *root;
@property(nonatomic,strong) PHFetchResult<PHAsset *> *index;
@property(nonatomic,copy) NSString *indexCategory;
@property(nonatomic,copy) NSString *indexOrder;
@property(nonatomic,copy) NSString *indexAlbum;
@property(nonatomic,strong) NSMutableOrderedSet<NSString *> *known;
@property(atomic) BOOL dirty;
@property(nonatomic) BOOL permissionPending;
@property(nonatomic,strong) HueviaPublication *publication;
- (NSDictionary *)thumbnail:(PHAsset *)asset resource:(PHAssetResource *)resource task:(HueviaTask *)task;
- (NSDictionary *)importAsset:(PHAsset *)asset resource:(PHAssetResource *)resource task:(HueviaTask *)task;
- (NSArray *)albumsForTask:(HueviaTask *)task;
@end

@implementation HueviaGallery
- (void)configurePublicationWithRuntime:(CcHueviaSharedSharedRuntime *)runtime {self.publication=[[HueviaPublication alloc] initWithRoot:self.root runtime:runtime];self.albumOperations=[[HueviaAlbumOperations alloc] initWithRoot:self.root runtime:runtime];}
- (void)requestSavePermission:(FlutterResult)reply {
  NSAssert(NSThread.isMainThread,@"Photos permission belongs to the main thread");
  if(self.permissionPending){reply([FlutterError errorWithCode:@"BUSY" message:@"请先完成当前照片权限选择。" details:nil]);return;}
  self.permissionPending=YES;
  [HueviaPublication requestSavePermission:^(NSDictionary *result){
    self.permissionPending=NO;
    reply([[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:result options:0 error:nil] encoding:NSUTF8StringEncoding]);
  }];
}
- (instancetype)initWithRoot:(NSString *)root {
  self=[super init];if(self){_root=[root copy];_known=[NSMutableOrderedSet orderedSet];NSString *incoming=privateDirectory(root,@"incoming");for(NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:incoming error:nil])if([name hasPrefix:@"photokit-"]&&[name hasSuffix:@".part"]){BOOL directory=NO;NSString *path=[incoming stringByAppendingPathComponent:name];if([NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&directory]&&!directory)[NSFileManager.defaultManager removeItemAtPath:path error:nil];}[PHPhotoLibrary.sharedPhotoLibrary registerChangeObserver:self];}return self;
}
- (void)dealloc {[PHPhotoLibrary.sharedPhotoLibrary unregisterChangeObserver:self];}
- (void)photoLibraryDidChange:(PHChange *)change {self.dirty=YES;void (^changed)(void)=self.changed;if(changed)changed();}
- (NSDictionary *)access {
  PHAuthorizationStatus state=[PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelReadWrite];
  NSString *access=state==PHAuthorizationStatusAuthorized?@"full":state==PHAuthorizationStatusLimited?@"limited":@"none";
  return @{@"access":access,@"imageAccess":access,@"videoAccess":@"none",@"canAsk":@(state==PHAuthorizationStatusNotDetermined),@"alternateBasis":@"modified"};
}
- (void)permissionReply:(FlutterResult)reply {
  self.permissionPending=NO;
  reply([[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:[self access] options:0 error:nil] encoding:NSUTF8StringEncoding]);
}
- (void)requestPermissionFrom:(UIViewController *)presenter reply:(FlutterResult)reply {
  NSAssert(NSThread.isMainThread,@"Photos permission belongs to the main thread");
  if(self.permissionPending){reply([FlutterError errorWithCode:@"BUSY" message:@"请先完成当前照片权限选择。" details:nil]);return;}
  self.permissionPending=YES;
  if(!presenter)for(UIScene *scene in UIApplication.sharedApplication.connectedScenes)if([scene isKindOfClass:UIWindowScene.class]&&scene.activationState==UISceneActivationStateForegroundActive){for(UIWindow *window in ((UIWindowScene *)scene).windows)if(window.isKeyWindow){presenter=window.rootViewController;break;}if(presenter)break;}
  PHAuthorizationStatus status=[PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelReadWrite];
  if(status==PHAuthorizationStatusNotDetermined){
    [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelReadWrite handler:^(PHAuthorizationStatus result){dispatch_async(dispatch_get_main_queue(),^{[self permissionReply:reply];});}];return;
  }
  if(status==PHAuthorizationStatusLimited&&presenter){
    while(presenter.presentedViewController)presenter=presenter.presentedViewController;
    [PHPhotoLibrary.sharedPhotoLibrary presentLimitedLibraryPickerFromViewController:presenter completionHandler:^(NSArray<NSString *> *identifiers){dispatch_async(dispatch_get_main_queue(),^{[self permissionReply:reply];});}];return;
  }
  [UIApplication.sharedApplication openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString] options:@{} completionHandler:^(BOOL success){[self permissionReply:reply];}];
}
- (PHAsset *)asset:(NSString *)identifier {
  if(!canRead()||![self.known containsObject:identifier])galleryFail(@"照片访问范围已变化，请刷新相册。");
  PHAsset *asset=[PHAsset fetchAssetsWithLocalIdentifiers:@[identifier] options:nil].firstObject;
  if(!asset||asset.mediaType!=PHAssetMediaTypeImage)galleryFail(@"照片已不可访问，请刷新相册。");
  return asset;
}
- (NSDictionary *)request:(NSString *)operation payload:(NSString *)payload task:(HueviaTask *)task {
  NSDictionary *p=[NSJSONSerialization JSONObjectWithData:[payload dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
  if(![p isKindOfClass:NSDictionary.class])galleryFail(@"相册操作数据无效。");
  galleryCheck(task);
  if([operation isEqualToString:@"gallery.access"])return [self access];
  if([operation isEqualToString:@"gallery.publish"]){if(!self.publication)galleryFail(@"应用尚未准备好。");return [self.publication publish:p task:task];}
  if([operation isEqualToString:@"gallery.publishOriginal"]){if(!self.publication)galleryFail(@"应用尚未准备好。");return [self.publication publishOriginal:p task:task];}
  if([operation isEqual:@"gallery.delete"]||[operation isEqual:@"gallery.publishedCopies"]){if(!self.albumOperations)galleryFail(@"应用尚未准备好。");return [self.albumOperations request:operation payload:p task:task];}
  if(!canRead()){self.index=nil;[self.known removeAllObjects];galleryFail(@"请允许访问照片，或选择指定照片。");}
  if([operation isEqualToString:@"gallery.page"]){
    NSString *category=p[@"category"]?:@"all",*query=p[@"query"]?:@"",*album=p[@"album"]?:@"";
    if(![album isKindOfClass:NSString.class]||album.length>256)galleryFail(@"相册位置无效。");
    if(![category isKindOfClass:NSString.class]||![@[@"all",@"image",@"live",@"raw"] containsObject:category]||![query isKindOfClass:NSString.class]||query.length>256)galleryFail(@"相册分类或搜索内容无效。");
    NSString *order=[NSString stringWithFormat:@"%d:%d",[p[@"added"] boolValue],[p[@"oldest"] boolValue]];
    id requested=p[@"offset"]?:@0;
    if(![requested isKindOfClass:NSNumber.class]||CFGetTypeID((__bridge CFTypeRef)requested)==CFBooleanGetTypeID()||[requested doubleValue]!=[requested longLongValue]||[requested longLongValue]<0||[requested longLongValue]>INT32_MAX)galleryFail(@"照片分页位置无效。");
    if([p[@"refresh"] boolValue]||!self.index||self.dirty||![self.indexCategory isEqual:category]||![self.indexOrder isEqual:order]||![self.indexAlbum isEqual:album]){
      PHFetchOptions *options=[PHFetchOptions new];options.includeHiddenAssets=NO;
      options.predicate=[category isEqual:@"live"]?[NSPredicate predicateWithFormat:@"mediaType == %d AND (mediaSubtypes & %d) != 0",PHAssetMediaTypeImage,PHAssetMediaSubtypePhotoLive]:![category isEqual:@"all"]?[NSPredicate predicateWithFormat:@"mediaType == %d",PHAssetMediaTypeImage]:[NSPredicate predicateWithFormat:@"mediaType == %d",PHAssetMediaTypeImage];
      options.sortDescriptors=@[[NSSortDescriptor sortDescriptorWithKey:[p[@"added"] boolValue]?@"modificationDate":@"creationDate" ascending:[p[@"oldest"] boolValue]]];
      if(album.length){PHAssetCollection *collection=[PHAssetCollection fetchAssetCollectionsWithLocalIdentifiers:@[album] options:nil].firstObject;if(!collection)galleryFail(@"此相册已变化，请重新选择相册。");self.index=[PHAsset fetchAssetsInAssetCollection:collection options:options];}
      else self.index=[PHAsset fetchAssetsWithOptions:options];
      self.indexCategory=category;self.indexOrder=order;self.indexAlbum=album;self.dirty=NO;
    }
    NSUInteger cursor=[requested unsignedIntegerValue];if(cursor>self.index.count)galleryFail(@"相册已变化，请重新加载。");
    NSMutableArray *rows=[NSMutableArray array];NSUInteger scanned=0;
    while(cursor<self.index.count&&rows.count<60&&scanned++<300){
      galleryCheck(task);PHAsset *asset=self.index[cursor++];PHAssetResource *resource=originalResource(asset);if(!resource)continue;
      BOOL raw=isRaw(resource);
      if(([category isEqual:@"raw"]&&!raw)||([category isEqual:@"image"]&&raw)||(query.length>0&&[(resource.originalFilename?:@"") rangeOfString:query options:NSCaseInsensitiveSearch].location==NSNotFound))continue;
      [self.known addObject:asset.localIdentifier];while(self.known.count>600)[self.known removeObjectAtIndex:0];
      NSDate *date=[p[@"added"] boolValue]?asset.modificationDate:asset.creationDate;
      [rows addObject:@{@"id":asset.localIdentifier,@"name":resource.originalFilename?:@"photo",@"raw":@(raw),@"live":@((asset.mediaSubtypes&PHAssetMediaSubtypePhotoLive)!=0),@"mediaType":asset.mediaType==PHAssetMediaTypeVideo?@"video":@"image",@"duration":@((long long)(asset.duration*1000)),@"date":@((long long)((date?:asset.creationDate).timeIntervalSince1970*1000)),@"sizeUnknown":@YES}];
    }
    if(!canRead())galleryFail(@"照片权限已变化，请重新加载。");
    NSMutableDictionary *result=[@{@"items":rows,@"nextOffset":@(cursor),@"hasMore":@(cursor<self.index.count),@"access":[self access][@"access"],@"alternateBasis":@"modified"} mutableCopy];
    if(![category isEqual:@"raw"]&&![category isEqual:@"image"]&&!query.length)result[@"total"]=@(self.index.count);
    if([requested unsignedIntegerValue]==0)result[@"albums"]=[self albumsForTask:task];
    return result;
  }
  NSString *identifier=p[@"id"];if(![identifier isKindOfClass:NSString.class]||identifier.length>2048)galleryFail(@"照片标识无效。");
  PHAsset *asset=([operation isEqual:@"gallery.import"]&&[p[@"batchSelection"] boolValue])?[PHAsset fetchAssetsWithLocalIdentifiers:@[identifier] options:nil].firstObject:[self asset:identifier];if(!asset)galleryFail(@"照片访问范围已变化，请重新选择。");PHAssetResource *resource=originalResource(asset);if(!resource)galleryFail(@"照片原文件暂不可用。");
  if([operation isEqualToString:@"gallery.preview"])return HueviaPreviewGalleryAsset(asset,task);
  if([operation isEqualToString:@"gallery.thumbnail"])return [self thumbnail:asset resource:resource task:task];
  if([operation isEqualToString:@"gallery.import"]){if(asset.mediaType!=PHAssetMediaTypeImage)galleryFail(@"视频可预览，修图和拼接请选择照片。");return [self importAsset:asset resource:resource task:task];}
  galleryFail(@"未知的系统相册操作。");return nil;
}
- (NSArray *)albumsForTask:(HueviaTask *)task {
  PHFetchOptions *options=[PHFetchOptions new];options.includeHiddenAssets=NO;
  options.predicate=[NSPredicate predicateWithFormat:@"mediaType == %d",PHAssetMediaTypeImage];
  options.sortDescriptors=@[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:NO]];
  PHFetchResult<PHAsset *> *all=[PHAsset fetchAssetsWithOptions:options];
  NSMutableArray *rows=[NSMutableArray array];
  NSMutableDictionary *allRow=[@{@"id":@"",@"name":@"全部相册",@"count":@(all.count)} mutableCopy];
  if(all.firstObject){allRow[@"cover"]=all.firstObject.localIdentifier;[self.known addObject:all.firstObject.localIdentifier];}
  [rows addObject:allRow];
  NSMutableArray<PHAssetCollection *> *collections=[NSMutableArray array];
  for(PHAssetCollection *collection in [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeAlbum subtype:PHAssetCollectionSubtypeAny options:nil])[collections addObject:collection];
  for(NSNumber *subtype in @[@(PHAssetCollectionSubtypeSmartAlbumFavorites),@(PHAssetCollectionSubtypeSmartAlbumScreenshots)])for(PHAssetCollection *collection in [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeSmartAlbum subtype:(PHAssetCollectionSubtype)subtype.integerValue options:nil])[collections addObject:collection];
  for(PHAssetCollection *collection in collections){
    galleryCheck(task);PHFetchResult<PHAsset *> *assets=[PHAsset fetchAssetsInAssetCollection:collection options:options];if(!assets.count)continue;
    [rows addObject:@{@"id":collection.localIdentifier,@"name":collection.localizedTitle?:@"相册",@"count":@(assets.count),@"cover":assets.firstObject.localIdentifier}];
    [self.known addObject:assets.firstObject.localIdentifier];
  }
  while(self.known.count>600)[self.known removeObjectAtIndex:0];
  if(!canRead())galleryFail(@"照片权限已变化，请重新加载。");
  return rows;
}
- (NSDictionary *)thumbnail:(PHAsset *)asset resource:(PHAssetResource *)resource task:(HueviaTask *)task {
  NSString *directory=privateDirectory(self.root,@"gallery-thumbnails");NSError *error=nil;
  NSString *key=digestText([NSString stringWithFormat:@"%@:%@:%f:384-v1",asset.localIdentifier,resource.originalFilename,asset.modificationDate.timeIntervalSince1970]);
  NSString *path=[directory stringByAppendingPathComponent:[key stringByAppendingString:@".jpg"]];
  if([[NSFileManager.defaultManager attributesOfItemAtPath:path error:nil][NSFileType] isEqualToString:NSFileTypeSymbolicLink])galleryFail(@"照片缩略图路径无效。");
  if([NSFileManager.defaultManager fileExistsAtPath:path])return @{@"path":path};
  PHImageRequestOptions *options=[PHImageRequestOptions new];options.synchronous=NO;options.networkAccessAllowed=YES;options.deliveryMode=PHImageRequestOptionsDeliveryModeHighQualityFormat;options.resizeMode=PHImageRequestOptionsResizeModeExact;options.version=PHImageRequestOptionsVersionOriginal;
  dispatch_semaphore_t done=dispatch_semaphore_create(0);NSLock *lock=[NSLock new];__block UIImage *image=nil;__block BOOL accepting=YES;
  PHImageRequestID request=[PHImageManager.defaultManager requestImageForAsset:asset targetSize:CGSizeMake(384,384) contentMode:PHImageContentModeAspectFit options:options resultHandler:^(UIImage *result,NSDictionary *info){
    if([info[PHImageResultIsDegradedKey] boolValue])return;
    [lock lock];if(accepting)image=result;[lock unlock];dispatch_semaphore_signal(done);
  }];
  BOOL finished=waitFor(done,task,45);[lock lock];accepting=NO;UIImage *received=image;[lock unlock];
  if(!finished){[PHImageManager.defaultManager cancelImageRequest:request];galleryCheck(task);galleryFail(@"照片缩略图读取超时，请重试。");}
  galleryCheck(task);[self asset:asset.localIdentifier];if(!received)galleryFail(@"暂时无法读取照片缩略图，请检查网络后重试。");
  CGFloat factor=MIN(1,384/MAX(received.size.width,received.size.height));CGSize size=CGSizeMake(MAX(1,round(received.size.width*factor)),MAX(1,round(received.size.height*factor)));
  UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat defaultFormat];format.scale=1;format.opaque=YES;
  UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithSize:size format:format];
  NSData *jpeg=[renderer JPEGDataWithCompressionQuality:.85 actions:^(UIGraphicsImageRendererContext *context){[received drawInRect:(CGRect){CGPointZero,size}];}];
  if(!jpeg||![jpeg writeToFile:path options:NSDataWritingAtomic error:&error])galleryFail(@"缩略图保存失败。");
  NSArray<NSURL *> *files=[NSFileManager.defaultManager contentsOfDirectoryAtURL:[NSURL fileURLWithPath:directory] includingPropertiesForKeys:@[NSURLContentModificationDateKey] options:0 error:nil];
  if(files.count>256){NSArray<NSURL *> *ordered=[files sortedArrayUsingComparator:^NSComparisonResult(NSURL *a,NSURL *b){id aa=nil,bb=nil;[a getResourceValue:&aa forKey:NSURLContentModificationDateKey error:nil];[b getResourceValue:&bb forKey:NSURLContentModificationDateKey error:nil];return [aa compare:bb];}];for(NSUInteger i=0;i<ordered.count-256;i++)if(![ordered[i].path isEqualToString:path])[NSFileManager.defaultManager removeItemAtURL:ordered[i] error:nil];}
  return @{@"path":path};
}
- (NSDictionary *)importAsset:(PHAsset *)asset resource:(PHAssetResource *)resource task:(HueviaTask *)task {
  NSString *directory=privateDirectory(self.root,@"incoming");
  NSString *path=[directory stringByAppendingPathComponent:[NSString stringWithFormat:@"photokit-%@.part",NSUUID.UUID.UUIDString]];
  NSOutputStream *out=[NSOutputStream outputStreamToFileAtPath:path append:NO];[out open];
  dispatch_semaphore_t done=dispatch_semaphore_create(0);NSLock *lock=[NSLock new];__block BOOL accepting=YES;__block NSString *failure=nil;__block uint64_t bytes=0;
  PHAssetResourceRequestOptions *options=[PHAssetResourceRequestOptions new];options.networkAccessAllowed=YES;
  options.progressHandler=^(double progress){if(task.progress)task.progress(progress*.4);};
  PHAssetResourceDataRequestID request=[PHAssetResourceManager.defaultManager requestDataForAssetResource:resource options:options dataReceivedHandler:^(NSData *part){
    [lock lock];
    if(accepting&&!failure){
      if(task.cancelled||!canRead())failure=@"照片访问已取消或权限已变化。";
      else if(part.length>1024ULL*1024*1024-bytes)failure=@"照片大小超过 1 GB，未导入。";
      else {const uint8_t *data=(const uint8_t *)part.bytes;NSUInteger offset=0;while(offset<part.length){NSInteger n=[out write:data+offset maxLength:part.length-offset];if(n<=0){failure=@"照片原文件写入失败。";break;}offset+=(NSUInteger)n;}bytes+=offset;}
    }
    BOOL failed=failure!=nil;[lock unlock];if(failed)dispatch_semaphore_signal(done);
  } completionHandler:^(NSError *problem){[lock lock];if(problem&&!failure)failure=@"无法读取照片原文件，请检查网络后重试。";[lock unlock];dispatch_semaphore_signal(done);}];
  @try {
    BOOL finished=waitFor(done,task,180);[lock lock];accepting=NO;[out close];NSString *problem=failure;uint64_t size=bytes;[lock unlock];
    if(!finished){[PHAssetResourceManager.defaultManager cancelDataRequest:request];galleryCheck(task);galleryFail(@"照片原文件读取超时，请重试。");}
    galleryCheck(task);[self asset:asset.localIdentifier];if(problem){[PHAssetResourceManager.defaultManager cancelDataRequest:request];galleryFail(problem);}if(size<4)galleryFail(@"照片原文件不完整。");
    JavaIoFileInputStream *input=[[JavaIoFileInputStream alloc] initWithNSString:path];
    NSString *receipt=[CcHueviaSharedSharedImport copy__WithJavaIoInputStream:input withNSString:resource.originalFilename.lastPathComponent withBoolean:NO withNSString:self.root withJavaUtilFunctionBooleanSupplier:task];
    return [NSJSONSerialization JSONObjectWithData:[receipt dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
  }@finally{[lock lock];accepting=NO;[out close];[lock unlock];[NSFileManager.defaultManager removeItemAtPath:path error:nil];}
}
@end
