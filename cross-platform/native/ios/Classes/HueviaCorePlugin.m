#import "HueviaCorePlugin.h"
#import "HueviaKeychain.h"
#import "HueviaMedia.h"
#import "HueviaImportPicker.h"
#import "HueviaGallery.h"
#import "cc/huevia/account/AccountHttpTransport.h"
#import "cc/huevia/shared/CoreEngine.h"
#import "cc/huevia/shared/SharedCamera.h"
#import "cc/huevia/album/PtpIpClient.h"
#import "java/net/Socket.h"
#import "java/net/InetSocketAddress.h"
#import "java/io/IOException.h"
#import "java/io/File.h"
#import "java/lang/Throwable.h"
#import "IOSPrimitiveArray.h"
#import "HueviaCoreBootstrap.h"
#import "HueviaWifiSocket.h"
#import "HueviaStability.h"
#import "HueviaQqAuthorization.h"
#import "HueviaDistribution.h"
#import "HueviaLegacyFiles.h"
#import "HueviaWiredCameras.h"
#import "HueviaOriginalFiles.h"
#import "HueviaAlbumOperations.h"
#import "HueviaConnectionProtection.h"
#import "HueviaCameraPresentation.h"
#import "cc/huevia/account/AccountException.h"
#import "java/lang/Runnable.h"

@interface HueviaCameraMaintenanceObserver : NSObject <JavaLangRunnable>
@property(nonatomic,copy) dispatch_block_t changed;
@end
@implementation HueviaCameraMaintenanceObserver
- (void)run {if(self.changed)self.changed();}
@end

@interface HueviaCorePlugin ()
@property(nonatomic,strong) dispatch_queue_t queue;
@property(nonatomic,strong) NSMutableDictionary<NSString *,HueviaTask *> *tasks;
@property(nonatomic,copy) FlutterEventSink events;
@property(nonatomic,strong) CcHueviaSharedSharedRuntime *runtime;
@property(nonatomic,strong) CcHueviaSharedSharedCamera *camera;
@property(nonatomic,strong) HueviaWiredCameras *wired;
@property(nonatomic,strong) HueviaSockets *sockets;
@property(nonatomic,strong) UIAlertController *networkIntroduction;
@property(nonatomic,copy) NSString *networkIntroductionJob;
@property(nonatomic,copy) FlutterResult networkIntroductionReply;
@property(nonatomic,strong) FlutterMethodCall *networkIntroductionCall;
@property(nonatomic,strong) HueviaMedia *media;
@property(nonatomic,copy) NSString *root;
@property(nonatomic,strong) HueviaImportPicker *importPicker;
@property(nonatomic,strong) HueviaGallery *gallery;
@property(nonatomic,strong) HueviaOriginalFiles *originalFiles;
@property(nonatomic,strong) HueviaAlbumOperations *albumOperations;
@property(nonatomic,strong) HueviaConnectionProtection *protection;
@property(atomic) BOOL maintenanceAllowed;
@property(nonatomic) BOOL maintenanceDetached;
@property(nonatomic) BOOL maintenanceObserved;
@property(nonatomic,strong) HueviaCameraMaintenanceObserver *cameraMaintenanceObserver;
@property(nonatomic,strong) FlutterMethodChannel *filesChannel;
@property(nonatomic,weak) UIViewController *presenter;
- (void)finishNetworkIntroduction:(FlutterError *)failure resume:(BOOL)resume;
@end

@implementation HueviaCorePlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
  [HueviaStability registerWithRegistrar:registrar];
  [HueviaQqAuthorization registerWithRegistrar:registrar];
  [HueviaDistribution registerWithRegistrar:registrar];
  [HueviaLegacyFiles registerWithRegistrar:registrar];
  HueviaCorePlugin *host=[[self alloc] init];
  host.queue=dispatch_queue_create("cc.huevia.shared.worker",DISPATCH_QUEUE_SERIAL);
  host.tasks=[NSMutableDictionary dictionary];
  __weak HueviaCorePlugin *weakHost=host;
  host.protection=[[HueviaConnectionProtection alloc] initWithMessenger:registrar.messenger cancel:^{
    HueviaCorePlugin *owner=weakHost;
    [owner finishNetworkIntroduction:[FlutterError errorWithCode:@"CANCELLED" message:@"连接已取消，请保持应用在前台后重试。" details:nil] resume:NO];
    for(NSString *job in owner.tasks.allKeys){if([owner.tasks[job] cancelIfActive])[owner.camera cancelWithNSString:job];}
  }];
  host.maintenanceAllowed=host.protection.maintenanceAllowed;
  host.protection.maintenanceChanged=^(BOOL allowed){
    HueviaCorePlugin *owner=weakHost;
    if(!owner)return;
    @synchronized(owner){
      if(owner.maintenanceDetached)return;
      owner.maintenanceAllowed=allowed;
      [owner.camera setMaintenanceAllowedWithBoolean:allowed];
    }
  };
  host.filesChannel=[FlutterMethodChannel methodChannelWithName:@"cc.huevia/file-publication" binaryMessenger:registrar.messenger];
  [host.filesChannel setMethodCallHandler:^(FlutterMethodCall *call,FlutterResult result){
    HueviaCorePlugin *owner=weakHost;if(!owner.originalFiles){result([FlutterError errorWithCode:@"NOT_READY" message:@"文件保存尚未准备好。" details:nil]);return;}[owner.originalFiles handleMethodCall:call result:result];
  }];
  host.importPicker=[[HueviaImportPicker alloc] initWithQueue:host.queue];
  host.presenter=registrar.viewController;
  FlutterMethodChannel *channel=[FlutterMethodChannel methodChannelWithName:@"cc.huevia/core" binaryMessenger:registrar.messenger];
  [registrar addMethodCallDelegate:host channel:channel];
  // Flutter delivers engine-detach cleanup to the published plugin instance.
  [registrar publish:host];
  FlutterEventChannel *events=[FlutterEventChannel eventChannelWithName:@"cc.huevia/events" binaryMessenger:registrar.messenger];
  [events setStreamHandler:host];
}
- (FlutterError *)onListenWithArguments:(id)arguments eventSink:(FlutterEventSink)events {self.events=events;return nil;}
- (FlutterError *)onCancelWithArguments:(id)arguments {self.events=nil;return nil;}
- (void)finishNetworkIntroduction:(FlutterError *)failure resume:(BOOL)resume {
  FlutterResult reply=self.networkIntroductionReply;if(!reply)return;
  FlutterMethodCall *call=self.networkIntroductionCall;UIAlertController *alert=self.networkIntroduction;
  self.networkIntroductionReply=nil;self.networkIntroductionCall=nil;self.networkIntroductionJob=nil;self.networkIntroduction=nil;
  if(!resume){if(alert.presentingViewController&&!alert.beingDismissed)[alert dismissViewControllerAnimated:YES completion:nil];reply(failure);return;}
  [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"HueviaCameraNetworkIntroduction"];
  [self handleMethodCall:call result:reply];
}
- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)reply {
  @synchronized(self){
    if(self.maintenanceDetached){reply([FlutterError errorWithCode:@"CANCELLED" message:@"应用连接已关闭。" details:nil]);return;}
  }
  NSDictionary *args=[call.arguments isKindOfClass:NSDictionary.class]?call.arguments:@{};
  if([call.method isEqualToString:@"cameraUsbPermission"]){reply(@"{\"granted\":true}");return;}
  if([call.method isEqualToString:@"cameraSettings"]){
    [UIApplication.sharedApplication openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString] options:@{} completionHandler:^(BOOL success){
      reply(success?nil:[FlutterError errorWithCode:@"SETTINGS_FAILED" message:@"请在 iPhone 设置中打开本应用的本地网络权限。" details:nil]);
    }];return;
  }
  NSDictionary *connectionPayload=[args[@"payload"] isKindOfClass:NSString.class]?[NSJSONSerialization JSONObjectWithData:[args[@"payload"] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil]:nil;
  if([call.method isEqualToString:@"request"]&&[args[@"operation"] isEqualToString:@"camera.connect"]&&![connectionPayload[@"transport"] isEqual:@"usb"]&&![NSUserDefaults.standardUserDefaults boolForKey:@"HueviaCameraNetworkIntroduction"]){
    if(self.networkIntroduction){reply([FlutterError errorWithCode:@"BUSY" message:@"请先完成或取消当前本地网络连接提示。" details:nil]);return;}
    UIAlertController *intro=[UIAlertController alertControllerWithTitle:@"允许访问相机的本地网络" message:@"请先连接相机 Wi-Fi。接下来的系统授权弹窗请选择“允许”，才能读取和下载相机照片。\n\n如果此前选择了“不允许”，请到 iPhone 设置 → Huevia → 本地网络中开启后重试。" preferredStyle:UIAlertControllerStyleAlert];
    self.networkIntroduction=intro;self.networkIntroductionCall=call;self.networkIntroductionReply=reply;
    self.networkIntroductionJob=[args[@"jobId"] isKindOfClass:NSString.class]?args[@"jobId"]:NSUUID.UUID.UUIDString;
    if(self.events)self.events(@{@"jobId":self.networkIntroductionJob,@"progress":@(0.02)});
    __weak UIAlertController *expectedIntro=intro;
    [intro addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action){if(!expectedIntro||self.networkIntroduction!=expectedIntro)return;[self finishNetworkIntroduction:[FlutterError errorWithCode:@"CANCELLED" message:@"已取消连接。" details:nil] resume:NO];}]];
    [intro addAction:[UIAlertAction actionWithTitle:@"继续连接" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
      if(!expectedIntro||self.networkIntroduction!=expectedIntro)return;
      // This records only that the explanation was shown, never permission state.
      [self finishNetworkIntroduction:nil resume:YES];
    }]];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,45*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(self.networkIntroduction==intro)[self finishNetworkIntroduction:[FlutterError errorWithCode:@"TIMEOUT" message:@"等待连接确认已超时，请重新点击连接并完成本地网络授权。" details:nil] resume:NO];});
    // The implicit engine can register before a FlutterViewController has a
    // window. Resolve the active scene at the time of presentation instead of
    // treating that one registration snapshot as the application's lifecycle.
    [HueviaCameraPresentation scheduleWhileCurrent:^BOOL {
      return self.networkIntroduction == intro && self.networkIntroductionReply != nil;
    } resolve:^UIViewController * {
      return [HueviaCameraPresentation presenterWithRegistered:self.presenter];
    } present:^(UIViewController *presenter) {
      [presenter presentViewController:intro animated:YES completion:^{
        if(self.networkIntroduction != intro && intro.presentingViewController && !intro.beingDismissed)
          [intro dismissViewControllerAnimated:NO completion:nil];
      }];
    } unavailable:^{
      NSDictionary *visibility=[HueviaCameraPresentation snapshotWithRegistered:self.presenter];
      BOOL foreground=[visibility[@"foregroundActive"] boolValue];
      [self finishNetworkIntroduction:[FlutterError errorWithCode:foreground?@"PRESENTATION_UNAVAILABLE":@"NOT_VISIBLE"
        message:foreground?@"暂时无法显示相机连接说明，请关闭当前弹窗后重试。":@"请回到应用前台后重新连接相机。"
        details:visibility] resume:NO];
    }];return;
  }
  if([call.method isEqualToString:@"gallerySavePermission"]){
    if(!self.gallery){reply([FlutterError errorWithCode:@"NOT_READY" message:@"应用尚未准备好。" details:nil]);return;}
    [self.gallery requestSavePermission:reply];return;
  }
  if([call.method isEqualToString:@"galleryPermission"]){
    if(!self.gallery){reply([FlutterError errorWithCode:@"NOT_READY" message:@"应用尚未准备好。" details:nil]);return;}
    [self.gallery requestPermissionFrom:self.presenter reply:reply];return;
  }
  if([call.method isEqualToString:@"pickAvatar"]){
    NSString *owner=args[@"owner"],*updatedAt=args[@"updatedAt"];
    if(!self.runtime||![owner isKindOfClass:NSString.class]||![updatedAt isKindOfClass:NSString.class]){reply([FlutterError errorWithCode:@"INVALID_ARGUMENT" message:@"账号尚未准备好。" details:nil]);return;}
    dispatch_async(self.queue,^{@autoreleasepool{
      @try{[self.runtime guardProfileWithNSString:owner withNSString:updatedAt];dispatch_async(dispatch_get_main_queue(),^{[self.importPicker pickAvatarForOwner:owner updatedAt:updatedAt runtime:self.runtime root:self.root presenter:self.presenter reply:reply];});}
      @catch(id failure){NSString *message=[failure respondsToSelector:@selector(getMessage)]?[failure getMessage]:@"账号资料已改变，请重试。";dispatch_async(dispatch_get_main_queue(),^{reply([FlutterError errorWithCode:@"AVATAR_FAILED" message:message details:nil]);});}
    }});return;
  }
  if([call.method isEqualToString:@"pickFile"]){
    if(!self.runtime||![args[@"preset"] isKindOfClass:NSNumber.class]){reply([FlutterError errorWithCode:@"INVALID_ARGUMENT" message:@"应用尚未准备好或导入类型无效。" details:nil]);return;}
    if(args[@"submissionKind"]){
      NSString *kind=args[@"submissionKind"],*owner=args[@"owner"];
      if(![kind isKindOfClass:NSString.class]||![@[@"ncp",@"preview"] containsObject:kind]||![owner isKindOfClass:NSString.class]||[args[@"preset"] boolValue]!=[kind isEqualToString:@"ncp"]){reply([FlutterError errorWithCode:@"INVALID_ARGUMENT" message:@"投稿文件类型无效。" details:nil]);return;}
      dispatch_async(self.queue,^{@autoreleasepool{
        @try{[self.runtime guardOwnerWithNSString:owner];dispatch_async(dispatch_get_main_queue(),^{[self.importPicker pickSubmission:kind owner:owner root:self.root presenter:self.presenter reply:reply];});}
        @catch(id failure){NSString *message=[failure respondsToSelector:@selector(getMessage)]?[failure getMessage]:@"账号或投稿已变化，请重试。";dispatch_async(dispatch_get_main_queue(),^{reply([FlutterError errorWithCode:@"IMPORT_FAILED" message:message details:nil]);});}
      }});return;
    }
    [self.importPicker pickPreset:[args[@"preset"] boolValue] root:self.root presenter:self.presenter reply:reply];return;
  }
  if([call.method isEqualToString:@"cancel"]){NSString *job=args[@"jobId"];if([job isKindOfClass:NSString.class]){if([job isEqualToString:self.networkIntroductionJob])[self finishNetworkIntroduction:[FlutterError errorWithCode:@"CANCELLED" message:@"已取消连接。" details:nil] resume:NO];HueviaTask *task=self.tasks[job];if([task cancelIfActive])[self.camera cancelWithNSString:job];}reply(nil);return;}
  if(![call.method isEqualToString:@"initialize"]&&![call.method isEqualToString:@"request"]){reply(FlutterMethodNotImplemented);return;}
  NSString *job=[args[@"jobId"] isKindOfClass:NSString.class]?args[@"jobId"]:NSUUID.UUID.UUIDString;
  if(self.tasks.count>=9||self.tasks[job]){reply([FlutterError errorWithCode:@"BUSY" message:@"任务较多，请等待当前操作完成。" details:nil]);return;}
  HueviaTask *task=[[HueviaTask alloc] init];self.tasks[job]=task;
  NSDictionary *cameraPresentation=[args[@"operation"] isKindOfClass:NSString.class]&&[args[@"operation"] isEqualToString:@"camera.diagnostics"]
    ?[HueviaCameraPresentation snapshotWithRegistered:self.presenter]:nil;
  __weak HueviaCorePlugin *weakSelf=self;
  task.progress=^(double value){dispatch_async(dispatch_get_main_queue(),^{HueviaCorePlugin *host=weakSelf;if(host.events)host.events(@{@"jobId":job,@"progress":@(value)});});};
  dispatch_async(self.queue,^{@autoreleasepool{
    NSString *stage=@"application operation";
    @try {
      @synchronized(self){
        if(self.maintenanceDetached||task.cancelled)@throw [[JavaIoIOException alloc] initWithNSString:@"操作已取消。"];
      }
      NSString *value;
      if([call.method isEqualToString:@"initialize"]){
        if(!self.runtime){
          stage=@"runtime modules";
          HueviaLinkCoreModules();
          stage=@"application storage";
          NSURL *directory=[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
          directory=[directory URLByAppendingPathComponent:@"Huevia" isDirectory:YES];
          NSError *error=nil;
          if(![NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:@{NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} error:&error])@throw [[JavaIoIOException alloc] initWithNSString:@"无法打开应用资料目录。"];
          [directory setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];self.root=directory.path;
          stage=@"image validation";
          [CcHueviaSharedMediaValidation installWithCcHueviaSharedMediaValidation_Decoder:[[HueviaImageValidator alloc] init]];
          stage=@"account and preset runtime";
          CcHueviaSharedSharedRuntime *runtime=[[CcHueviaSharedSharedRuntime alloc] initWithNSString:self.root withCcHueviaAccountAccountRepository_Store:[[HueviaKeychain alloc] init] withCcHueviaAccountAccountRepository_Transport:[[CcHueviaAccountAccountHttpTransport alloc] init]];
          // Return the same canonical root used by guarded Java file access.
          // Physical iOS devices may expose /var and /private/var aliases.
          self.root=[[runtime root] getPath];
          stage=@"camera runtime";
          self.wired=[[HueviaWiredCameras alloc] init];
          self.sockets=[[HueviaSockets alloc] init];
          CcHueviaSharedSharedCamera *camera=[[CcHueviaSharedSharedCamera alloc] initWithNSString:self.root withCcHueviaSharedSharedCamera_Connectors:self.sockets withCcHueviaSharedSharedCamera_WiredConnections:self.wired];
          stage=@"media runtime";
          HueviaMedia *media=[[HueviaMedia alloc] initWithRuntime:runtime root:self.root];
          HueviaGallery *gallery=[[HueviaGallery alloc] initWithRoot:self.root];
          [gallery configurePublicationWithRuntime:runtime];
          __weak HueviaCorePlugin *weakHost=self;
          gallery.changed=^{dispatch_async(dispatch_get_main_queue(),^{HueviaCorePlugin *host=weakHost;if(host.events)host.events(@{@"kind":@"galleryChanged"});});};
          self.runtime=runtime;self.media=media;self.gallery=gallery;
          @synchronized(self){
            if(self.maintenanceDetached||task.cancelled){
              [camera setMaintenanceAllowedWithBoolean:NO];[camera closeTransport];
              @throw [[JavaIoIOException alloc] initWithNSString:@"操作已取消。"];
            }
            self.camera=camera;[camera setMaintenanceAllowedWithBoolean:self.maintenanceAllowed];
          }
          HueviaCameraMaintenanceObserver *observer=[HueviaCameraMaintenanceObserver new];
          observer.changed=^{dispatch_async(dispatch_get_main_queue(),^{
            HueviaCorePlugin *owner=weakHost;if(!owner)return;
            @synchronized(owner){
              if(owner.maintenanceDetached)return;
              BOOL active=[owner.camera maintenanceActive];
              if(owner.maintenanceObserved==active)return;
              owner.maintenanceObserved=active;
              if(active||[owner.camera maintenanceConnection])return;
              if(owner.events)owner.events(@{@"kind":@"cameraConnectionChanged"});
            }
          });};
          @synchronized(self){
            if(!self.maintenanceDetached){
              self.cameraMaintenanceObserver=observer;
              [camera setMaintenanceObserverWithJavaLangRunnable:observer];
            }
          }
          self.originalFiles=[[HueviaOriginalFiles alloc] initWithRoot:self.root runtime:runtime];
          self.albumOperations=[[HueviaAlbumOperations alloc] initWithRoot:self.root runtime:runtime];
        }
        stage=@"bridge schema";
        NSData *schema=[[CcHueviaSharedCoreEngine schema] dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *data=@{@"root":self.root,@"schema":[NSJSONSerialization JSONObjectWithData:schema options:0 error:nil],@"platform":@"ios"};
        value=[[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:data options:0 error:nil] encoding:NSUTF8StringEncoding];
      }else{
        if(!self.runtime)@throw [[JavaIoIOException alloc] initWithNSString:@"应用尚未初始化。"];
        NSString *operation=args[@"operation"],*payload=args[@"payload"];
        if(![operation isKindOfClass:NSString.class]||![payload isKindOfClass:NSString.class]||payload.length>4*1024*1024)@throw [[JavaIoIOException alloc] initWithNSString:@"操作数据无效。"];
        stage=operation;
        if([operation hasPrefix:@"media."]){NSDictionary *data=[self.media request:operation payload:payload task:task];value=[[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:data options:0 error:nil] encoding:NSUTF8StringEncoding];}
        else if([operation isEqualToString:@"files.publishOriginal"]){NSDictionary *p=[NSJSONSerialization JSONObjectWithData:[payload dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];NSDictionary *data=[self.originalFiles publish:p task:task];value=[[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:data options:0 error:nil] encoding:NSUTF8StringEncoding];}
        else if([operation isEqualToString:@"gallery.delete"]||[operation isEqualToString:@"gallery.publishedCopies"]){NSDictionary *p=[NSJSONSerialization JSONObjectWithData:[payload dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];NSDictionary *data=[self.albumOperations request:operation payload:p task:task];value=[[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:data options:0 error:nil] encoding:NSUTF8StringEncoding];}
        else if([operation hasPrefix:@"gallery."]){NSDictionary *data=[self.gallery request:operation payload:payload task:task];value=[[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:data options:0 error:nil] encoding:NSUTF8StringEncoding];}
        else if([operation hasPrefix:@"camera."]){NSDictionary *p=[NSJSONSerialization JSONObjectWithData:[payload dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];if(p[@"queueId"])[self.runtime guardOwnerWithNSString:p[@"owner"]];self.sockets.cancellation=task;self.sockets.progress=task;[self.wired prepareRequestWithCancellation:task];value=[self.camera requestWithNSString:operation withNSString:payload withNSString:job withJavaUtilFunctionBooleanSupplier:task withJavaUtilFunctionDoubleConsumer:task];}
        else value=[self.runtime requestWithNSString:operation withNSString:payload withJavaUtilFunctionBooleanSupplier:task withJavaUtilFunctionDoubleConsumer:task];
      }
      if(cameraPresentation){
        id decoded=[NSJSONSerialization JSONObjectWithData:[value dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        if([decoded isKindOfClass:NSDictionary.class]){
          NSMutableDictionary *data=[decoded mutableCopy];data[@"presentation"]=cameraPresentation;
          value=[[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:data options:0 error:nil] encoding:NSUTF8StringEncoding];
        }
      }
      [task finish];
      dispatch_async(dispatch_get_main_queue(),^{if(self.tasks[job]==task)[self.tasks removeObjectForKey:job];reply(value);});
    }@catch(id failure){
      NSString *message=[failure respondsToSelector:@selector(getMessage)]?[failure getMessage]:@"操作未完成，请重试。";
      NSMutableDictionary *details=[@{@"stage":stage,@"nativeType":NSStringFromClass([failure class])} mutableCopy];
      if([failure isKindOfClass:CcHueviaAccountAccountException.class]){details[@"accountCode"]=((CcHueviaAccountAccountException *)failure)->code_;details[@"status"]=@(((CcHueviaAccountAccountException *)failure)->status_);}
      if([call.method isEqualToString:@"initialize"])details[@"reason"]=[failure description]?:@"unknown";
#if DEBUG
      // Native debug integration failures must retain their actual exception,
      // while release requests keep the friendly message and omit operation data.
      NSString *reason=[failure description]?:@"unknown";
      details[@"reason"]=[reason substringToIndex:MIN(reason.length,2048)];
      if([failure isKindOfClass:NSException.class])details[@"nativeStack"]=[[(NSException *)failure callStackSymbols] subarrayWithRange:NSMakeRange(0,MIN(10,[(NSException *)failure callStackSymbols].count))];
#endif
      [task finish];
      dispatch_async(dispatch_get_main_queue(),^{if(self.tasks[job]==task)[self.tasks removeObjectForKey:job];reply([FlutterError errorWithCode:task.cancelled?@"CANCELLED":@"OPERATION_FAILED" message:message details:details]);});
    }
  }});
}
- (void)detachFromEngineForRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
  self.protection.maintenanceChanged=nil;
  self.events=nil;
  CcHueviaSharedSharedCamera *camera;
  @synchronized(self){
    self.maintenanceDetached=YES;self.maintenanceAllowed=NO;
    camera=self.camera;[camera setMaintenanceAllowedWithBoolean:NO];
    [camera setMaintenanceObserverWithJavaLangRunnable:nil];
    self.cameraMaintenanceObserver=nil;
    for(NSString *job in self.tasks.allKeys){
      if([self.tasks[job] cancelIfActive])[camera cancelWithNSString:job];
    }
  }
  [self finishNetworkIntroduction:[FlutterError errorWithCode:@"CANCELLED" message:@"应用连接已关闭。" details:nil] resume:NO];
  dispatch_async(self.queue,^{[camera closeTransport];});
}
@end
