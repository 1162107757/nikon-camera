#import "HueviaStability.h"
#import <Foundation/Foundation.h>
#import <MetricKit/MetricKit.h>

static const NSUInteger HueviaStabilityLimit=32768;
static NSUncaughtExceptionHandler *previousExceptionHandler;

@interface HueviaStability () <MXMetricManagerSubscriber>
@property(nonatomic) BOOL exceptionHandlerInstalled;
@property(nonatomic) BOOL metricKitRegistered;
+ (instancetype)shared;
- (void)recordException:(NSException *)exception;
@end

static void hueviaUncaughtException(NSException *exception){
  @try{[[HueviaStability shared] recordException:exception];}
  @catch(id unavailable){/* Preserve the original exception. */}
  @finally{if(previousExceptionHandler)previousExceptionHandler(exception);}
}

@implementation HueviaStability
+ (instancetype)shared {
  static HueviaStability *instance;static dispatch_once_t once;
  dispatch_once(&once,^{instance=[HueviaStability new];});return instance;
}
+ (void)install {
  HueviaStability *host=[self shared];
  @synchronized(host){
    if(!host.exceptionHandlerInstalled){
      previousExceptionHandler=NSGetUncaughtExceptionHandler();
      NSSetUncaughtExceptionHandler(hueviaUncaughtException);
      host.exceptionHandlerInstalled=YES;
    }
    if(!host.metricKitRegistered){
      @try{[[MXMetricManager sharedManager] addSubscriber:host];host.metricKitRegistered=YES;}
      @catch(id unavailable){/* Diagnostics delivery remains optional. */}
    }
  }
}
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
  [self install];
  FlutterMethodChannel *channel=[FlutterMethodChannel methodChannelWithName:@"cc.huevia/stability" binaryMessenger:registrar.messenger];
  [registrar addMethodCallDelegate:[self shared] channel:channel];
}
- (NSURL *)directory {
  NSFileManager *files=NSFileManager.defaultManager;
  NSURL *support=[files URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
  NSURL *root=[support URLByAppendingPathComponent:@"Huevia" isDirectory:YES];
  NSDictionary *rootAttributes=[files attributesOfItemAtPath:root.path error:nil];
  if(rootAttributes&&![rootAttributes[NSFileType] isEqual:NSFileTypeDirectory])return nil;
  NSURL *directory=[root URLByAppendingPathComponent:@"app-stability" isDirectory:YES];
  NSDictionary *attributes=[files attributesOfItemAtPath:directory.path error:nil];
  if(attributes&&![attributes[NSFileType] isEqual:NSFileTypeDirectory])return nil;
  if(![files createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:@{NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} error:nil])return nil;
  [directory setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];return directory;
}
- (BOOL)write:(NSDictionary *)record name:(NSString *)name {
  @synchronized(self){
    NSURL *directory=[self directory];if(!directory)return NO;
    NSURL *target=[directory URLByAppendingPathComponent:name];
    NSDictionary *attributes=[NSFileManager.defaultManager attributesOfItemAtPath:target.path error:nil];
    if(attributes&&![attributes[NSFileType] isEqual:NSFileTypeRegular])return NO;
    NSData *data=[NSJSONSerialization dataWithJSONObject:record options:0 error:nil];
    return data&&data.length<=HueviaStabilityLimit&&[data writeToURL:target options:NSDataWritingAtomic error:nil];
  }
}
- (NSDictionary *)read:(NSString *)name {
  @synchronized(self){
    NSURL *directory=[self directory];if(!directory)return nil;
    NSURL *file=[directory URLByAppendingPathComponent:name];
    NSDictionary *attributes=[NSFileManager.defaultManager attributesOfItemAtPath:file.path error:nil];
    if(![attributes[NSFileType] isEqual:NSFileTypeRegular]||[attributes fileSize]>HueviaStabilityLimit)return nil;
    NSData *bytes=[NSData dataWithContentsOfURL:file options:0 error:nil];
    id value=bytes?[NSJSONSerialization JSONObjectWithData:bytes options:0 error:nil]:nil;
    return [value isKindOfClass:NSDictionary.class]?value:nil;
  }
}
- (void)recordException:(NSException *)exception {
  // Reasons and full callStackSymbols can contain private paths or values.
  // Retain only Objective-C method identities from the original stack.
  NSRegularExpression *method=[NSRegularExpression regularExpressionWithPattern:@"[+-]\\[[A-Za-z_][A-Za-z0-9_$.]* [A-Za-z0-9_$:]+\\]" options:0 error:nil];
  NSMutableArray *frames=[NSMutableArray array];
  for(NSString *symbol in exception.callStackSymbols){
    if(![symbol isKindOfClass:NSString.class]||symbol.length>2048)continue;
    NSTextCheckingResult *match=[method firstMatchInString:symbol options:0 range:NSMakeRange(0,symbol.length)];
    if(match&&match.range.length<=200)[frames addObject:[symbol substringWithRange:match.range]];
    if(frames.count>=48)break;
  }
  NSRegularExpression *type=[NSRegularExpression regularExpressionWithPattern:@"^[A-Za-z_$][A-Za-z0-9_$.<>]{0,95}$" options:0 error:nil];
  NSString *name=exception.name?:@"NSException";
  if(![type firstMatchInString:name options:0 range:NSMakeRange(0,name.length)])name=@"NSException";
  [self write:@{@"recordedAtEpochMillis":@((long long)(NSDate.date.timeIntervalSince1970*1000)),@"type":name,@"frames":frames} name:@"last-native-exception.json"];
}
- (void)didReceiveDiagnosticPayloads:(NSArray<MXDiagnosticPayload *> *)payloads {
  @try{
    NSMutableArray *crashes=[NSMutableArray array];
    for(MXDiagnosticPayload *payload in payloads.reverseObjectEnumerator){
      for(MXCrashDiagnostic *crash in payload.crashDiagnostics.reverseObjectEnumerator){
        NSMutableDictionary *row=[@{@"recordedAtEpochMillis":@((long long)(NSDate.date.timeIntervalSince1970*1000)),@"windowStartedAt":@((long long)(payload.timeStampBegin.timeIntervalSince1970*1000)),@"windowEndedAt":@((long long)(payload.timeStampEnd.timeIntervalSince1970*1000))} mutableCopy];
        if(crash.signal)row[@"signal"]=crash.signal;
        if(crash.exceptionType)row[@"exceptionType"]=crash.exceptionType;
        [crashes addObject:row];if(crashes.count>=4)break;
      }
      if(crashes.count>=4)break;
    }
    if(crashes.count)[self write:@{@"crashes":crashes} name:@"metric-kit-crashes.json"];
  }@catch(id unavailable){/* System delivery must not affect application work. */}
}
- (void)didReceiveMetricPayloads:(NSArray<MXMetricPayload *> *)payloads {
  @try{
    MXMetricPayload *latest=nil;
    for(MXMetricPayload *payload in payloads)if(payload.applicationExitMetrics&&(!latest||[payload.timeStampEnd compare:latest.timeStampEnd]==NSOrderedDescending))latest=payload;
    if(!latest)return;
    MXAppExitMetric *exits=latest.applicationExitMetrics;
    NSDictionary *summary=@{@"recordedAtEpochMillis":@((long long)(NSDate.date.timeIntervalSince1970*1000)),@"windowStartedAt":@((long long)(latest.timeStampBegin.timeIntervalSince1970*1000)),@"windowEndedAt":@((long long)(latest.timeStampEnd.timeIntervalSince1970*1000)),
      @"foregroundMemoryLimit":@(exits.foregroundExitData.cumulativeMemoryResourceLimitExitCount),@"backgroundMemoryLimit":@(exits.backgroundExitData.cumulativeMemoryResourceLimitExitCount),@"backgroundMemoryPressure":@(exits.backgroundExitData.cumulativeMemoryPressureExitCount),
      @"foregroundWatchdog":@(exits.foregroundExitData.cumulativeAppWatchdogExitCount),@"backgroundWatchdog":@(exits.backgroundExitData.cumulativeAppWatchdogExitCount),@"backgroundCPUResourceLimit":@(exits.backgroundExitData.cumulativeCPUResourceLimitExitCount),
      @"includesMultipleAppVersions":@(latest.includesMultipleApplicationVersions),@"latestAppVersion":latest.latestApplicationVersion?:@""};
    [self write:summary name:@"metric-kit-exits.json"];
  }@catch(id unavailable){/* Daily, system-managed summaries may be absent. */}
}
- (NSString *)snapshot {
  NSMutableDictionary *record=[@{@"platform":@"ios",@"uncaughtExceptionHandlerInstalled":@(self.exceptionHandlerInstalled),@"metricKitRegistered":@(self.metricKitRegistered)} mutableCopy];
  NSDictionary *exception=[self read:@"last-native-exception.json"],*flutter=[self read:@"last-flutter-error.json"],*metric=[self read:@"metric-kit-crashes.json"],*exits=[self read:@"metric-kit-exits.json"];
  if(exception)record[@"lastNativeException"]=exception;
  if(flutter)record[@"lastFlutterError"]=flutter;
  if([metric[@"crashes"] isKindOfClass:NSArray.class])record[@"metricKitCrashes"]=metric[@"crashes"];
  if(exits)record[@"metricKitExits"]=exits;
  NSData *data=[NSJSONSerialization dataWithJSONObject:record options:0 error:nil];return data?[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]:@"{}";
}
- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)reply {
  if([call.method isEqualToString:@"recordFlutter"]){
    @try{BOOL written=[call.arguments isKindOfClass:NSDictionary.class]&&[self write:call.arguments name:@"last-flutter-error.json"];reply(written?nil:[FlutterError errorWithCode:@"STABILITY_UNAVAILABLE" message:@"异常记录暂不可用。" details:nil]);}
    @catch(id unavailable){reply([FlutterError errorWithCode:@"STABILITY_UNAVAILABLE" message:@"异常记录暂不可用。" details:nil]);}return;
  }
  if(![call.method isEqualToString:@"snapshot"]){reply(FlutterMethodNotImplemented);return;}
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{@autoreleasepool{
    @try{NSString *value=[self snapshot];dispatch_async(dispatch_get_main_queue(),^{reply(value);});}
    @catch(id unavailable){dispatch_async(dispatch_get_main_queue(),^{reply([FlutterError errorWithCode:@"STABILITY_UNAVAILABLE" message:@"异常记录暂不可用。" details:nil]);});}
  }});
}
@end
