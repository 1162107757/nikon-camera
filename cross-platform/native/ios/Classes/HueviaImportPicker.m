#import "HueviaImportPicker.h"
#import "HueviaTask.h"
#import "HueviaAvatar.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "cc/huevia/shared/SharedImport.h"
#import "cc/huevia/shared/SharedRuntime.h"
#import "IOSPrimitiveArray.h"
#import "java/io/FileInputStream.h"
#import "java/lang/Throwable.h"

@interface HueviaImportPicker ()
- (void)beginPreset:(BOOL)preset kind:(NSString *)kind owner:(NSString *)owner root:(NSString *)root presenter:(UIViewController *)presenter reply:(FlutterResult)reply;
- (void)finish:(id)value generation:(NSUInteger)generation;
- (void)processAvatarStage:(NSString *)staged failure:(id)failure generation:(NSUInteger)generation task:(HueviaTask *)task runtime:(CcHueviaSharedSharedRuntime *)runtime owner:(NSString *)owner updatedAt:(NSString *)updatedAt;
@end

@implementation HueviaImportPicker {
  dispatch_queue_t _queue;
  FlutterResult _pending;
  NSString *_root;
  BOOL _preset;
  NSString *_submissionKind,*_owner;
  NSString *_avatarUpdatedAt;
  CcHueviaSharedSharedRuntime *_avatarRuntime;
  NSUInteger _generation;
  UIDocumentPickerViewController *_activePicker;
  PHPickerViewController *_photoPicker;
  NSProgress *_avatarLoad;
  HueviaTask *_task;
  UIBackgroundTaskIdentifier _background;
}
- (instancetype)initWithQueue:(dispatch_queue_t)queue {self=[super init];if(self){_queue=queue;_background=UIBackgroundTaskInvalid;}return self;}
- (void)finish:(id)value generation:(NSUInteger)generation {
  NSAssert(NSThread.isMainThread,@"Picker replies belong to the UI thread");
  if(generation!=_generation)return;
  FlutterResult reply=_pending;_pending=nil;
  _activePicker=nil;
  _photoPicker=nil;_avatarLoad=nil;
  if(_background!=UIBackgroundTaskInvalid){[UIApplication.sharedApplication endBackgroundTask:_background];_background=UIBackgroundTaskInvalid;}
  if(reply)reply(value);
}
- (void)pickPreset:(BOOL)preset root:(NSString *)root presenter:(UIViewController *)presenter reply:(FlutterResult)reply {
  [self beginPreset:preset kind:nil owner:nil root:root presenter:presenter reply:reply];
}
- (void)pickSubmission:(NSString *)kind owner:(NSString *)owner root:(NSString *)root presenter:(UIViewController *)presenter reply:(FlutterResult)reply {
  [self beginPreset:[kind isEqualToString:@"ncp"] kind:kind owner:owner root:root presenter:presenter reply:reply];
}
- (void)pickAvatarForOwner:(NSString *)owner updatedAt:(NSString *)updatedAt runtime:(CcHueviaSharedSharedRuntime *)runtime root:(NSString *)root presenter:(UIViewController *)presenter reply:(FlutterResult)reply {
  if(_pending){reply([FlutterError errorWithCode:@"BUSY" message:@"文件正在导入，请稍候。" details:nil]);return;}
  _avatarUpdatedAt=[updatedAt copy];_avatarRuntime=runtime;
  [self beginPreset:NO kind:@"avatar" owner:owner root:root presenter:presenter reply:reply];
}
- (void)beginPreset:(BOOL)preset kind:(NSString *)kind owner:(NSString *)owner root:(NSString *)root presenter:(UIViewController *)presenter reply:(FlutterResult)reply {
  if(_pending){reply([FlutterError errorWithCode:@"BUSY" message:@"文件正在导入，请稍候。" details:nil]);return;}
  if(!presenter){
    for(UIScene *scene in UIApplication.sharedApplication.connectedScenes)if([scene isKindOfClass:UIWindowScene.class]&&scene.activationState==UISceneActivationStateForegroundActive){
      for(UIWindow *window in ((UIWindowScene *)scene).windows)if(window.isKeyWindow){presenter=window.rootViewController;break;}
      if(presenter)break;
    }
  }
  while(presenter.presentedViewController)presenter=presenter.presentedViewController;
  if(!presenter){reply([FlutterError errorWithCode:@"IMPORT_FAILED" message:@"暂时无法打开文件选择器。" details:nil]);return;}
  _pending=[reply copy];_preset=preset;_root=[root copy];_submissionKind=[kind copy];_owner=[owner copy];_task=[[HueviaTask alloc] init];_generation++;
  if([kind isEqualToString:@"avatar"]){
    PHPickerConfiguration *configuration=[[PHPickerConfiguration alloc] initWithPhotoLibrary:PHPhotoLibrary.sharedPhotoLibrary];
    configuration.filter=PHPickerFilter.imagesFilter;configuration.selectionLimit=1;configuration.preferredAssetRepresentationMode=PHPickerConfigurationAssetRepresentationModeCurrent;
    PHPickerViewController *picker=[[PHPickerViewController alloc] initWithConfiguration:configuration];picker.delegate=self;_photoPicker=picker;
    [presenter presentViewController:picker animated:YES completion:nil];return;
  }
  UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeData] asCopy:NO];
  picker.delegate=self;picker.allowsMultipleSelection=NO;picker.shouldShowFileExtensions=YES;
  _activePicker=picker;
  [presenter presentViewController:picker animated:YES completion:nil];
}
- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {if(controller!=_activePicker)return;_task.cancelled=YES;[self finish:@"{\"cancelled\":true}" generation:_generation];}
- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
  if(picker!=_photoPicker)return;_photoPicker=nil;[picker dismissViewControllerAnimated:YES completion:nil];
  NSUInteger generation=_generation;HueviaTask *task=_task;
  if(!results.count){task.cancelled=YES;[self finish:@"{\"cancelled\":true}" generation:generation];return;}
  NSString *root=_root,*owner=_owner,*updatedAt=_avatarUpdatedAt;CcHueviaSharedSharedRuntime *runtime=_avatarRuntime;
  NSItemProvider *provider=results.firstObject.itemProvider;
  if(![provider hasItemConformingToTypeIdentifier:UTTypeImage.identifier]){[self finish:[FlutterError errorWithCode:@"AVATAR_FAILED" message:@"请选择照片作为头像。" details:nil] generation:generation];return;}
  __weak HueviaImportPicker *weakSelf=self;__block NSProgress *loading=nil;
  _background=[UIApplication.sharedApplication beginBackgroundTaskWithName:@"Huevia avatar import" expirationHandler:^{
    task.cancelled=YES;[loading cancel];dispatch_async(dispatch_get_main_queue(),^{[weakSelf finish:[FlutterError errorWithCode:@"CANCELLED" message:@"头像选择已取消，请回到应用后重试。" details:nil] generation:generation];});
  }];
  loading=[provider loadFileRepresentationForTypeIdentifier:UTTypeImage.identifier completionHandler:^(NSURL *url,NSError *error){@autoreleasepool{
    HueviaImportPicker *strongSelf=weakSelf;if(!strongSelf||task.cancelled)return;
    NSString *staged=nil;id failure=error;
    if(url&&!failure){
      // Provider temporary URLs expire when this callback returns. Retain only
      // a bounded owned copy, then decode on the serial worker.
      BOOL scoped=[url startAccessingSecurityScopedResource];
      @try{JavaIoFileInputStream *input=[[JavaIoFileInputStream alloc] initWithNSString:url.path];
        staged=[CcHueviaSharedSharedImport stageAvatarWithJavaIoInputStream:input withNSString:url.lastPathComponent withNSString:owner withNSString:root withJavaUtilFunctionBooleanSupplier:task];
      }@catch(id problem){failure=problem;}@finally{if(scoped)[url stopAccessingSecurityScopedResource];}
    }
    [strongSelf processAvatarStage:staged failure:failure generation:generation task:task runtime:runtime owner:owner updatedAt:updatedAt];
  }}];_avatarLoad=loading;
}
- (void)processAvatarStage:(NSString *)staged failure:(id)initialFailure generation:(NSUInteger)generation task:(HueviaTask *)task runtime:(CcHueviaSharedSharedRuntime *)runtime owner:(NSString *)owner updatedAt:(NSString *)updatedAt {
  dispatch_async(_queue,^{@autoreleasepool{
    NSString *receipt=nil;id failure=initialFailure;NSString *path=nil;
    @try{
      if(!failure&&staged){
        NSDictionary *entry=[NSJSONSerialization JSONObjectWithData:[staged dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];path=entry[@"path"];
        if(path.length){[runtime guardProfileWithNSString:owner withNSString:updatedAt];NSData *jpeg=[HueviaAvatar prepareFile:path task:task];
          if(!task.cancelled)receipt=[runtime prepareAvatarWithNSString:owner withNSString:updatedAt withByteArray:[IOSByteArray arrayWithBytes:jpeg.bytes count:(jint)jpeg.length]];
        }
      }
    }@catch(id problem){failure=problem;}@finally{if(path.length)[NSFileManager.defaultManager removeItemAtPath:path error:nil];}
    dispatch_async(dispatch_get_main_queue(),^{
      if(failure||!receipt||task.cancelled){NSString *message=[failure respondsToSelector:@selector(getMessage)]?[failure getMessage]:@"无法读取所选照片，请重试。";
        [self finish:[FlutterError errorWithCode:task.cancelled?@"CANCELLED":@"AVATAR_FAILED" message:message details:nil] generation:generation];
      }else [self finish:receipt generation:generation];
    });
  }});
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
  if(controller!=_activePicker)return;
  NSUInteger generation=_generation;NSURL *url=urls.firstObject;if(!url){[self finish:@"{\"cancelled\":true}" generation:generation];return;}
  HueviaTask *task=_task;NSString *root=_root,*kind=_submissionKind,*owner=_owner;BOOL preset=_preset;
  _background=[UIApplication.sharedApplication beginBackgroundTaskWithName:@"Huevia file import" expirationHandler:^{task.cancelled=YES;}];
  dispatch_async(_queue,^{@autoreleasepool{
    __block NSString *receipt=nil;__block id failure=nil;
    BOOL scoped=[url startAccessingSecurityScopedResource];
    @try {
      NSError *error=nil;NSFileCoordinator *coordinator=[[NSFileCoordinator alloc] initWithFilePresenter:nil];
      [coordinator coordinateReadingItemAtURL:url options:0 error:&error byAccessor:^(NSURL *file){
        @try {
          JavaIoFileInputStream *input=[[JavaIoFileInputStream alloc] initWithNSString:file.path];
          // J2ObjC escapes NSObject's reserved `copy` message as `copy__`.
          receipt=kind.length?[CcHueviaSharedSharedImport stageSubmissionWithJavaIoInputStream:input withNSString:url.lastPathComponent withNSString:kind withNSString:owner withNSString:root withJavaUtilFunctionBooleanSupplier:task]:[CcHueviaSharedSharedImport copy__WithJavaIoInputStream:input withNSString:url.lastPathComponent withBoolean:preset withNSString:root withJavaUtilFunctionBooleanSupplier:task];
        }@catch(id problem){failure=problem;}
      }];
      if(error&&!failure)failure=error;
    }@catch(id problem){failure=problem;}
    @finally{if(scoped)[url stopAccessingSecurityScopedResource];}
    dispatch_async(dispatch_get_main_queue(),^{
      if(failure||!receipt||task.cancelled){NSString *message=[failure respondsToSelector:@selector(getMessage)]?[failure getMessage]:@"无法读取所选文件，请重试。";[self finish:[FlutterError errorWithCode:task.cancelled?@"CANCELLED":@"IMPORT_FAILED" message:message details:nil] generation:generation];}
      else [self finish:receipt generation:generation];
    });
  }});
}
@end
