#import "HueviaCorePlugin.h"
#import "HueviaKeychain.h"
#import "HueviaMedia.h"
#import "cc/huevia/account/AccountHttpTransport.h"
#import "cc/huevia/shared/CoreEngine.h"
#import "cc/huevia/shared/SharedCamera.h"
#import "cc/huevia/album/PtpIpClient.h"
#import "java/net/Socket.h"
#import "java/net/InetSocketAddress.h"
#import "java/io/IOException.h"
#import "java/lang/Throwable.h"
#import "IOSPrimitiveArray.h"
#import "HueviaCoreBootstrap.h"

@interface HueviaSockets : NSObject <CcHueviaSharedSharedCamera_Connectors,CcHueviaAlbumPtpIpClient_SocketConnector>
@end
@implementation HueviaSockets
- (id<CcHueviaAlbumPtpIpClient_SocketConnector>)createWithNSString:(NSString *)host withInt:(int32_t)port withBoolean:(bool)fuji {return self;}
- (JavaNetSocket *)connectWithNSString:(NSString *)host withInt:(int32_t)port withInt:(int32_t)timeout {
  JavaNetSocket *socket=[[JavaNetSocket alloc] init];
  @try {[socket connectWithJavaNetSocketAddress:[[JavaNetInetSocketAddress alloc] initWithNSString:host withInt:port] withInt:timeout];return socket;}
  @catch(id failure){[socket close];@throw failure;}
}
@end

@interface HueviaCorePlugin ()
@property(nonatomic) dispatch_queue_t queue;
@property(nonatomic) NSMutableDictionary<NSString *,HueviaTask *> *tasks;
@property(nonatomic,copy) FlutterEventSink events;
@property(nonatomic) CcHueviaSharedSharedRuntime *runtime;
@property(nonatomic) CcHueviaSharedSharedCamera *camera;
@property(nonatomic) HueviaMedia *media;
@property(nonatomic) NSString *root;
@end

@implementation HueviaCorePlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
  HueviaLinkCoreModules();
  HueviaCorePlugin *host=[[self alloc] init];
  host.queue=dispatch_queue_create("cc.huevia.shared.worker",DISPATCH_QUEUE_SERIAL);
  host.tasks=[NSMutableDictionary dictionary];
  FlutterMethodChannel *channel=[FlutterMethodChannel methodChannelWithName:@"cc.huevia/core" binaryMessenger:registrar.messenger];
  [registrar addMethodCallDelegate:host channel:channel];
  FlutterEventChannel *events=[FlutterEventChannel eventChannelWithName:@"cc.huevia/events" binaryMessenger:registrar.messenger];
  [events setStreamHandler:host];
}
- (FlutterError *)onListenWithArguments:(id)arguments eventSink:(FlutterEventSink)events {self.events=events;return nil;}
- (FlutterError *)onCancelWithArguments:(id)arguments {self.events=nil;return nil;}
- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)reply {
  NSDictionary *args=[call.arguments isKindOfClass:NSDictionary.class]?call.arguments:@{};
  if([call.method isEqualToString:@"cancel"]){NSString *job=args[@"jobId"];if([job isKindOfClass:NSString.class]){self.tasks[job].cancelled=YES;[self.camera cancelWithNSString:job];}reply(nil);return;}
  if(![call.method isEqualToString:@"initialize"]&&![call.method isEqualToString:@"request"]){reply(FlutterMethodNotImplemented);return;}
  NSString *job=[args[@"jobId"] isKindOfClass:NSString.class]?args[@"jobId"]:NSUUID.UUID.UUIDString;
  if(self.tasks.count>=9||self.tasks[job]){reply([FlutterError errorWithCode:@"BUSY" message:@"任务较多，请等待当前操作完成。" details:nil]);return;}
  HueviaTask *task=[[HueviaTask alloc] init];self.tasks[job]=task;
  __weak HueviaCorePlugin *weakSelf=self;
  task.progress=^(double value){dispatch_async(dispatch_get_main_queue(),^{HueviaCorePlugin *host=weakSelf;if(host.events)host.events(@{@"jobId":job,@"progress":@(value)});});};
  dispatch_async(self.queue,^{@autoreleasepool{
    @try {
      if(task.cancelled)@throw [[JavaIoIOException alloc] initWithNSString:@"操作已取消。"];
      NSString *value;
      if([call.method isEqualToString:@"initialize"]){
        if(!self.runtime){
          NSURL *directory=[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
          directory=[directory URLByAppendingPathComponent:@"Huevia" isDirectory:YES];
          NSError *error=nil;
          if(![NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:@{NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} error:&error])@throw [[JavaIoIOException alloc] initWithNSString:@"无法打开应用资料目录。"];
          [directory setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];self.root=directory.path;
          [CcHueviaSharedMediaValidation installWithCcHueviaSharedMediaValidation_Decoder:[[HueviaImageValidator alloc] init]];
          self.runtime=[[CcHueviaSharedSharedRuntime alloc] initWithNSString:self.root withCcHueviaAccountAccountRepository_Store:[[HueviaKeychain alloc] init] withCcHueviaAccountAccountRepository_Transport:[[CcHueviaAccountAccountHttpTransport alloc] init]];
          self.camera=[[CcHueviaSharedSharedCamera alloc] initWithNSString:self.root withCcHueviaSharedSharedCamera_Connectors:[[HueviaSockets alloc] init]];
          self.media=[[HueviaMedia alloc] initWithRuntime:self.runtime root:self.root];
        }
        NSData *schema=[[CcHueviaSharedCoreEngine schema] dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *data=@{@"root":self.root,@"schema":[NSJSONSerialization JSONObjectWithData:schema options:0 error:nil],@"platform":@"ios"};
        value=[[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:data options:0 error:nil] encoding:NSUTF8StringEncoding];
      }else{
        if(!self.runtime)@throw [[JavaIoIOException alloc] initWithNSString:@"应用尚未初始化。"];
        NSString *operation=args[@"operation"],*payload=args[@"payload"];
        if(![operation isKindOfClass:NSString.class]||![payload isKindOfClass:NSString.class]||payload.length>4*1024*1024)@throw [[JavaIoIOException alloc] initWithNSString:@"操作数据无效。"];
        if([operation hasPrefix:@"media."]){NSDictionary *data=[self.media request:operation payload:payload task:task];value=[[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:data options:0 error:nil] encoding:NSUTF8StringEncoding];}
        else if([operation hasPrefix:@"camera."])value=[self.camera requestWithNSString:operation withNSString:payload withNSString:job withJavaUtilFunctionBooleanSupplier:task withJavaUtilFunctionDoubleConsumer:task];
        else value=[self.runtime requestWithNSString:operation withNSString:payload];
      }
      dispatch_async(dispatch_get_main_queue(),^{[self.tasks removeObjectForKey:job];reply(value);});
    }@catch(id failure){
      NSString *message=[failure respondsToSelector:@selector(getMessage)]?[failure getMessage]:@"操作未完成，请重试。";
      dispatch_async(dispatch_get_main_queue(),^{[self.tasks removeObjectForKey:job];reply([FlutterError errorWithCode:task.cancelled?@"CANCELLED":@"OPERATION_FAILED" message:message details:nil]);});
    }
  }});
}
@end
