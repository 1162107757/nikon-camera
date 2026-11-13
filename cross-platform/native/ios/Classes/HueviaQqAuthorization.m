#import "HueviaQqAuthorization.h"
#import <TencentOpenAPI/TencentOAuth.h>
#import <TencentOpenAPI/QQApiInterface.h>

@interface HueviaQqAuthorization () <TencentSessionDelegate,FlutterSceneLifeCycleDelegate>
@property(nonatomic,strong) TencentOAuth *oauth;
@property(nonatomic,copy) FlutterResult pending;
@property(nonatomic,assign) BOOL draining;
@property(nonatomic,assign) NSUInteger generation;
@end

@implementation HueviaQqAuthorization
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
  HueviaQqAuthorization *host=[[self alloc] init];
  FlutterMethodChannel *channel=[FlutterMethodChannel methodChannelWithName:@"cc.huevia/qq" binaryMessenger:registrar.messenger];
  [registrar addMethodCallDelegate:host channel:channel];
  [registrar addApplicationDelegate:host];
  [registrar addSceneDelegate:host];
}
- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)reply {
  if([call.method isEqualToString:@"cancel"]){
    self.generation++;
    [self finish:@{@"cancelled":@YES}];
    // The singleton SDK must drain this provider callback before another attempt.
    if(self.draining)[self.oauth cancel:nil];
    reply(nil);return;
  }
  if(![call.method isEqualToString:@"authorize"]){reply(FlutterMethodNotImplemented);return;}
  if(![call.arguments isKindOfClass:NSDictionary.class]||![call.arguments[@"consent"] isEqual:@YES]){
    reply([FlutterError errorWithCode:@"QQ_CONSENT_REQUIRED" message:@"请先阅读并同意 QQ 登录说明。" details:nil]);return;
  }
  if(self.pending||self.draining){reply([FlutterError errorWithCode:@"QQ_BUSY" message:@"请先关闭上次 QQ 授权页，再重试；如仍无法继续，请重新打开应用。" details:nil]);return;}
  NSString *link=[NSBundle.mainBundle objectForInfoDictionaryKey:@"HueviaQqUniversalLink"];
  NSURLComponents *url=[link isKindOfClass:NSString.class]?[NSURLComponents componentsWithString:link]:nil;
  if(![url.scheme isEqualToString:@"https"]||!url.host.length||url.user||url.password||url.query||url.fragment){
    reply([FlutterError errorWithCode:@"QQ_CONFIGURATION_REQUIRED" message:@"此安装包尚未配置 QQ 互联的 iOS 通用链接，请使用账号密码登录。" details:nil]);return;
  }
  [QQApiInterface stopLog];[QQApiInterface setSwitchPrintLogToFile:NO];
  [TencentOAuth setIsUserAgreedAuthorization:YES];
  if(![QQApiInterface isQQInstalled]){reply([FlutterError errorWithCode:@"QQ_NOT_INSTALLED" message:@"请先安装 QQ，再重试登录。" details:nil]);return;}
  self.oauth=[TencentOAuth sharedInstance];
  [self clearProvider];
  [self.oauth setupAppId:@"1105984855" enableUniveralLink:YES universalLink:link delegate:self];
  self.pending=reply;self.draining=YES;
  NSUInteger attempt=++self.generation;
  // Do not fall back to embedded browser OAuth when the native client cannot launch.
  if(![self.oauth authorize:@[@"get_simple_userinfo"]]){
    self.draining=NO;[self clearProvider];
    [self finish:[FlutterError errorWithCode:@"QQ_LAUNCH_FAILED" message:@"无法打开 QQ 授权，请更新 QQ 后重试。" details:nil]];return;
  }
  __weak HueviaQqAuthorization *weakSelf=self;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,300*NSEC_PER_SEC),dispatch_get_main_queue(),^{
    HueviaQqAuthorization *host=weakSelf;
    if(host.generation==attempt&&host.pending){
      [host finish:[FlutterError errorWithCode:@"QQ_TIMEOUT" message:@"QQ 授权已超时，请重新登录。" details:nil]];
      [host.oauth cancel:nil];
    }
  });
}
- (void)finish:(id)value {FlutterResult reply=self.pending;self.pending=nil;if(reply)reply(value);}
- (void)clearProvider {
  [self.oauth deleteCachedToken];[self.oauth deleteOpenId];
  self.oauth.accessToken=nil;self.oauth.openId=nil;self.oauth.expirationDate=nil;
}
- (void)tencentDidLogin {
  NSString *token=[self.oauth.accessToken copy];
  BOOL valid=[token isKindOfClass:NSString.class]&&token.length>=16&&token.length<=2048;
  if(valid){NSCharacterSet *invalid=[[NSCharacterSet characterSetWithRange:NSMakeRange(0x21, 0x7e - 0x21 + 1)] invertedSet];valid=[token rangeOfCharacterFromSet:invalid].location==NSNotFound;}
  [self clearProvider];self.draining=NO;
  if(valid)[self finish:@{@"accessToken":token}];
  else [self finish:[FlutterError errorWithCode:@"QQ_RESULT_INVALID" message:@"QQ 授权结果无效，请重新登录。" details:nil]];
}
- (void)tencentDidNotLogin:(BOOL)cancelled {
  [self clearProvider];self.draining=NO;
  [self finish:cancelled?@{@"cancelled":@YES}:[FlutterError errorWithCode:@"QQ_AUTH_FAILED" message:@"QQ 授权未完成，请重试或使用账号密码登录。" details:nil]];
}
- (void)tencentDidNotNetWork {
  [self clearProvider];self.draining=NO;
  [self finish:[FlutterError errorWithCode:@"QQ_NETWORK_FAILED" message:@"QQ 授权暂时无法连接网络，请稍后重试。" details:nil]];
}
- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenURLOptionsKey,id> *)options {
  if(![url.scheme isEqualToString:@"tencent1105984855"])return NO;
  return [TencentOAuth HandleOpenURL:url];
}
- (BOOL)application:(UIApplication *)application continueUserActivity:(NSUserActivity *)activity restorationHandler:(void (^)(NSArray<id<UIUserActivityRestoring>> *))handler {
  if(![activity.activityType isEqualToString:NSUserActivityTypeBrowsingWeb]||![TencentOAuth CanHandleUniversalLink:activity.webpageURL])return NO;
  return [TencentOAuth HandleUniversalLink:activity.webpageURL];
}
- (BOOL)scene:(UIScene *)scene openURLContexts:(NSSet<UIOpenURLContext *> *)contexts {
  for(UIOpenURLContext *context in contexts)if([context.URL.scheme isEqualToString:@"tencent1105984855"]&&[TencentOAuth HandleOpenURL:context.URL])return YES;
  return NO;
}
- (BOOL)scene:(UIScene *)scene continueUserActivity:(NSUserActivity *)activity {
  if(![activity.activityType isEqualToString:NSUserActivityTypeBrowsingWeb]||![TencentOAuth CanHandleUniversalLink:activity.webpageURL])return NO;
  return [TencentOAuth HandleUniversalLink:activity.webpageURL];
}
- (BOOL)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
  if([self scene:scene openURLContexts:options.URLContexts])return YES;
  for(NSUserActivity *activity in options.userActivities)if([self scene:scene continueUserActivity:activity])return YES;
  return NO;
}
@end
