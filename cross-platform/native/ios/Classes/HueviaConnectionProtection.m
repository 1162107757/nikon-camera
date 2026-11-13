#import "HueviaConnectionProtection.h"
#import "HueviaTaskCancellation.h"

@interface HueviaConnectionProtection ()
@property(nonatomic) BOOL active;
@property(nonatomic) BOOL foreground;
@property(nonatomic) BOOL expired;
@property(nonatomic) UIBackgroundTaskIdentifier lease;
@property(nonatomic,strong) HueviaTaskCancellation *leaseCancellation;
@property(nonatomic,copy) FlutterEventSink events;
@property(nonatomic,copy) dispatch_block_t cancel;
@end

@implementation HueviaConnectionProtection
- (instancetype)initWithMessenger:(NSObject<FlutterBinaryMessenger> *)messenger cancel:(dispatch_block_t)cancel {
  if((self=[super init])){
    _lease=UIBackgroundTaskInvalid;_foreground=UIApplication.sharedApplication.applicationState!=UIApplicationStateBackground;_cancel=[cancel copy];
    __weak typeof(self) weakSelf=self;
    FlutterMethodChannel *channel=[FlutterMethodChannel methodChannelWithName:@"cc.huevia/connection-protection" binaryMessenger:messenger];
    [channel setMethodCallHandler:^(FlutterMethodCall *call,FlutterResult result){[weakSelf handle:call result:result];}];
    FlutterEventChannel *events=[FlutterEventChannel eventChannelWithName:@"cc.huevia/connection-protection-events" binaryMessenger:messenger];[events setStreamHandler:self];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(background:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(foreground:) name:UIApplicationWillEnterForegroundNotification object:nil];
  }return self;
}
- (BOOL)enabled {return [NSUserDefaults.standardUserDefaults boolForKey:@"HueviaCameraConnectionProtection"];}
- (NSString *)status {
  NSDictionary *value=@{@"available":@YES,@"enabled":@(self.enabled),@"running":@(self.lease!=UIBackgroundTaskInvalid),@"backgroundAllowed":@(self.enabled&&self.active&&self.lease!=UIBackgroundTaskInvalid&&!self.expired),@"limited":@YES,@"warning":self.expired?@"iOS 后台时间已到，接收已暂停；返回前台后可继续未完成队列。":@"iOS 只提供有限的后台收尾时间；持续接收请保持应用前台。"};
  return [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:value options:0 error:nil] encoding:NSUTF8StringEncoding];
}
- (void)emit {if(self.events)self.events([self status]);}
- (void)endLease {UIBackgroundTaskIdentifier lease=self.lease;self.lease=UIBackgroundTaskInvalid;[self.leaseCancellation finish];self.leaseCancellation=nil;if(lease!=UIBackgroundTaskInvalid)[UIApplication.sharedApplication endBackgroundTask:lease];}
- (void)update {
  if(!self.enabled||!self.active){[self endLease];[self emit];return;}
  if(self.lease==UIBackgroundTaskInvalid&&!self.expired&&self.foreground){
    __weak typeof(self) weakSelf=self;
    HueviaTaskCancellation *cancellation=[HueviaTaskCancellation new];self.leaseCancellation=cancellation;
    self.lease=[UIApplication.sharedApplication beginBackgroundTaskWithName:@"Huevia camera transfer" expirationHandler:^{
      HueviaConnectionProtection *host=weakSelf;if(!host)return;
      if(host.leaseCancellation!=cancellation||![cancellation cancelIfActive])return;
      host.expired=YES;if(host.cancel)host.cancel();[host endLease];[host emit];
    }];
    if(self.lease==UIBackgroundTaskInvalid)self.expired=YES;
  }[self emit];
}
- (void)background:(NSNotification *)note {self.foreground=NO;[self emit];}
- (void)foreground:(NSNotification *)note {self.foreground=YES;self.expired=NO;[self update];}
- (void)handle:(FlutterMethodCall *)call result:(FlutterResult)reply {
  NSDictionary *args=[call.arguments isKindOfClass:NSDictionary.class]?call.arguments:@{};
  if([call.method isEqualToString:@"set"]){
    if((args[@"enabled"]&&![args[@"enabled"] isKindOfClass:NSNumber.class])||(args[@"active"]&&![args[@"active"] isKindOfClass:NSNumber.class])){reply([FlutterError errorWithCode:@"INVALID_ARGUMENT" message:@"连接保护设置无效。" details:nil]);return;}
    if(args[@"enabled"])[NSUserDefaults.standardUserDefaults setBool:[args[@"enabled"] boolValue] forKey:@"HueviaCameraConnectionProtection"];
    if(args[@"active"]){BOOL active=[args[@"active"] boolValue];if(active&&!self.active&&self.foreground)self.expired=NO;self.active=active;}[self update];
  }else if([call.method isEqualToString:@"foreground"]){
    self.foreground=[args[@"foreground"] boolValue];if(self.foreground){self.expired=NO;[self update];}
  }else if(![call.method isEqualToString:@"status"]&&! [call.method isEqualToString:@"batterySettings"]){reply(FlutterMethodNotImplemented);return;}
  reply([self status]);
}
- (FlutterError *)onListenWithArguments:(id)arguments eventSink:(FlutterEventSink)events {self.events=events;[self emit];return nil;}
- (FlutterError *)onCancelWithArguments:(id)arguments {self.events=nil;return nil;}
- (void)dealloc {[NSNotificationCenter.defaultCenter removeObserver:self];[self endLease];}
@end
