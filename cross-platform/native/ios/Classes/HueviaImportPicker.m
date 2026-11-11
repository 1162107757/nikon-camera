#import "HueviaImportPicker.h"
#import "HueviaTask.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "cc/huevia/shared/SharedImport.h"
#import "java/io/FileInputStream.h"
#import "java/lang/Throwable.h"

@implementation HueviaImportPicker {
  dispatch_queue_t _queue;
  FlutterResult _pending;
  NSString *_root;
  BOOL _preset;
  HueviaTask *_task;
  UIBackgroundTaskIdentifier _background;
}
- (instancetype)initWithQueue:(dispatch_queue_t)queue {self=[super init];if(self){_queue=queue;_background=UIBackgroundTaskInvalid;}return self;}
- (void)finish:(id)value {
  NSAssert(NSThread.isMainThread,@"Picker replies belong to the UI thread");
  FlutterResult reply=_pending;_pending=nil;
  if(_background!=UIBackgroundTaskInvalid){[UIApplication.sharedApplication endBackgroundTask:_background];_background=UIBackgroundTaskInvalid;}
  if(reply)reply(value);
}
- (void)pickPreset:(BOOL)preset root:(NSString *)root presenter:(UIViewController *)presenter reply:(FlutterResult)reply {
  if(_pending){reply([FlutterError errorWithCode:@"BUSY" message:@"文件正在导入，请稍候。" details:nil]);return;}
  if(!presenter){
    for(UIScene *scene in UIApplication.sharedApplication.connectedScenes)if([scene isKindOfClass:UIWindowScene.class]&&scene.activationState==UISceneActivationStateForegroundActive){
      for(UIWindow *window in ((UIWindowScene *)scene).windows)if(window.isKeyWindow){presenter=window.rootViewController;break;}
      if(presenter)break;
    }
  }
  while(presenter.presentedViewController)presenter=presenter.presentedViewController;
  if(!presenter){reply([FlutterError errorWithCode:@"IMPORT_FAILED" message:@"暂时无法打开文件选择器。" details:nil]);return;}
  _pending=[reply copy];_preset=preset;_root=[root copy];_task=[[HueviaTask alloc] init];
  UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeData] asCopy:NO];
  picker.delegate=self;picker.allowsMultipleSelection=NO;picker.shouldShowFileExtensions=YES;
  [presenter presentViewController:picker animated:YES completion:nil];
}
- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {[self finish:@"{\"cancelled\":true}"];}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
  NSURL *url=urls.firstObject;if(!url){[self finish:@"{\"cancelled\":true}"];return;}
  HueviaTask *task=_task;NSString *root=_root;BOOL preset=_preset;
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
          receipt=[CcHueviaSharedSharedImport copy__WithJavaIoInputStream:input withNSString:url.lastPathComponent withBoolean:preset withNSString:root withJavaUtilFunctionBooleanSupplier:task];
        }@catch(id problem){failure=problem;}
      }];
      if(error&&!failure)failure=error;
    }@catch(id problem){failure=problem;}
    @finally{if(scoped)[url stopAccessingSecurityScopedResource];}
    dispatch_async(dispatch_get_main_queue(),^{
      if(failure||!receipt){NSString *message=[failure respondsToSelector:@selector(getMessage)]?[failure getMessage]:@"无法读取所选文件，请重试。";[self finish:[FlutterError errorWithCode:task.cancelled?@"CANCELLED":@"IMPORT_FAILED" message:message details:nil]];}
      else [self finish:receipt];
    });
  }});
}
@end
