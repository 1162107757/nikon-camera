#import "HueviaWiredCameras.h"
#import "HueviaCameraWait.h"
#import "cc/huevia/album/PhotoCameraClient.h"
#import "cc/huevia/ptp/PtpResponseException.h"
#import "cc/huevia/ptp/PtpContainer.h"
#import "cc/huevia/shared/SharedSlotTransportGuard.h"
#import "java/io/IOException.h"
#import "java/io/OutputStream.h"
#import "java/lang/Runnable.h"
#import "java/util/Map.h"
#import "java/util/function/LongConsumer.h"
#import "IOSPrimitiveArray.h"

static void wiredFailure(NSString *message){@throw [[JavaIoIOException alloc] initWithNSString:message];}
static void mainSync(dispatch_block_t action){if(NSThread.isMainThread)action();else dispatch_sync(dispatch_get_main_queue(),action);}
static IOSByteArray *javaBytes(NSData *data){return [IOSByteArray arrayWithBytes:data.bytes count:(jint)data.length];}
static uint32_t little32(const uint8_t *p){return (uint32_t)p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24;}
static void append32(NSMutableData *data,uint32_t value){uint8_t bytes[4]={value,value>>8,value>>16,value>>24};[data appendBytes:bytes length:4];}
static NSString *deviceID(ICDevice *device){return [NSString stringWithFormat:@"usb-%u-%@",(unsigned)device.usbLocationID,device.UUIDString?:@""];}
static BOOL supported(ICDevice *device){return [device isKindOfClass:ICCameraDevice.class]&&device.usbVendorID==0x04b0&&[device.transportType isEqualToString:ICTransportTypeUSB];}

@interface HueviaWiredClient : NSObject <CcHueviaAlbumPhotoCameraClient,ICCameraDeviceDelegate>
@property(nonatomic,strong) ICCameraDevice *device;
@property(atomic) BOOL open;
@property(atomic,strong) id<JavaLangRunnable> closed;
@property(nonatomic,strong) dispatch_semaphore_t ready;
@property(atomic,strong) dispatch_semaphore_t closing;
@property(atomic,strong) NSError *sessionError;
@property(atomic,strong) NSError *closeError;
@property(nonatomic) uint32_t transaction;
@property(atomic,strong) id<JavaUtilFunctionBooleanSupplier> cancellation;
- (void)waitForClose;
- (void)openSession;
@end
@interface HueviaWiredSlots : NSObject <CcHueviaSharedSharedSlots_Transport>
@property(nonatomic,strong) HueviaWiredClient *client;
@property(nonatomic,strong) CcHueviaSharedSharedSlotTransportGuard *guard;
@end
@interface HueviaWiredCameras ()
@property(nonatomic,strong) ICDeviceBrowser *browser;
@property(atomic,strong) HueviaWiredClient *active;
@property(atomic,strong) HueviaWiredSlots *slots;
@property(nonatomic,strong) dispatch_semaphore_t discovery;
@property(atomic,strong) id<JavaUtilFunctionBooleanSupplier> cancellation;
@end

@implementation HueviaWiredCameras
- (void)prepareRequestWithCancellation:(id<JavaUtilFunctionBooleanSupplier>)cancel {self.cancellation=cancel;self.active.cancellation=cancel;}
- (NSString *)devices {
  id<JavaUtilFunctionBooleanSupplier> cancel=self.cancellation;
  __block ICAuthorizationStatus authorization=ICAuthorizationStatusNotDetermined;
  dispatch_semaphore_t permission=dispatch_semaphore_create(0);
  mainSync(^{
    if(cancel&&[cancel getAsBoolean]){dispatch_semaphore_signal(permission);return;}
    if(!self.browser){self.browser=[[ICDeviceBrowser alloc] init];self.browser.delegate=self;self.browser.browsedDeviceTypeMask=ICDeviceTypeMaskCamera|ICDeviceLocationTypeMaskLocal;}
    [self.browser requestContentsAuthorizationWithCompletion:^(ICAuthorizationStatus status){authorization=status;dispatch_semaphore_signal(permission);}];
  });
  if(!HueviaAwaitCameraResponse(permission,45,cancel))wiredFailure(@"等待外接相机授权超时。请查看系统授权弹窗，或在 iPhone 设置中允许访问相机后重试。");
  if(![authorization isEqualToString:ICAuthorizationStatusAuthorized])wiredFailure(@"请在 iPhone 设置中允许 Huevia 访问外接相机，然后重试。");
  __block BOOL starting=NO;mainSync(^{if(!self.browser.browsing){starting=YES;self.discovery=dispatch_semaphore_create(0);[self.browser start];}});
  if(starting)HueviaAwaitCameraResponse(self.discovery,2,cancel);
  // Discovery is asynchronous; a subsequent refresh can add a newly attached camera.
  NSMutableArray *rows=[NSMutableArray array];mainSync(^{for(ICDevice *device in self.browser.devices)if(supported(device))[rows addObject:@{@"id":deviceID(device),@"name":device.name?:@"Nikon USB 相机",@"permission":@YES}];});
  return [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:@{@"items":rows,@"transport":@"usb"} options:0 error:nil] encoding:NSUTF8StringEncoding];
}
- (id<CcHueviaAlbumPhotoCameraClient>)createWithNSString:(NSString *)identity {
  id<JavaUtilFunctionBooleanSupplier> cancel=self.cancellation;
  // ICDevice's delegate is unretained. Retire the old session before a new
  // client replaces its delegate, including reconnects to the same device.
  [self.slots close];self.slots=nil;
  HueviaWiredClient *previous=self.active;[previous close];[previous waitForClose];
  if(cancel&&[cancel getAsBoolean])wiredFailure(@"USB 相机连接已取消。");
  if(!self.browser)wiredFailure(@"请先检测 USB 相机，再选择设备连接。");
  dispatch_semaphore_t permission=dispatch_semaphore_create(0);__block ICAuthorizationStatus authorization=nil;
  mainSync(^{if(cancel&&[cancel getAsBoolean]){dispatch_semaphore_signal(permission);return;}[self.browser requestControlAuthorizationWithCompletion:^(ICAuthorizationStatus status){authorization=status;dispatch_semaphore_signal(permission);}];});
  if(!HueviaAwaitCameraResponse(permission,45,cancel))wiredFailure(@"等待外接相机会话授权超时，请允许系统授权后重试。");
  if(![authorization isEqualToString:ICAuthorizationStatusAuthorized])wiredFailure(@"外接相机会话访问未获允许。请在 iPhone 设置中允许相机访问后重试。");
  __block ICCameraDevice *selected=nil;mainSync(^{for(ICDevice *device in self.browser.devices)if(supported(device)&&[deviceID(device) isEqualToString:identity]){selected=(ICCameraDevice *)device;break;}});
  if(!selected)wiredFailure(@"未找到该 USB 相机，请检查相机开机、数据线和转接器后重新检测。");
  if(![selected.capabilities containsObject:ICCameraDeviceCanAcceptPTPCommands])wiredFailure(@"该相机未提供系统 PTP 读取通道，无法建立有线照片会话。请检查相机 USB 模式，或改用相机 Wi-Fi。");
  HueviaWiredClient *client=[[HueviaWiredClient alloc] init];client.device=selected;client.cancellation=cancel;self.active=client;return client;
}
- (id<CcHueviaSharedSharedSlots_Transport>)openSlotsWithNSString:(NSString *)identity {
  HueviaWiredClient *client=(HueviaWiredClient *)[self createWithNSString:identity];
  if(![client.device.capabilities containsObject:ICCameraDeviceCanAcceptPTPCommands])wiredFailure(@"此相机未提供系统 PTP 命令通道，未打开优化校准会话。");
  HueviaWiredSlots *slots=[[HueviaWiredSlots alloc] init];slots.client=client;slots.guard=[[CcHueviaSharedSharedSlotTransportGuard alloc] init];self.slots=slots;return slots;
}
- (void)deviceBrowser:(ICDeviceBrowser *)browser didAddDevice:(ICDevice *)device moreComing:(BOOL)moreComing {if(self.discovery&&supported(device))dispatch_semaphore_signal(self.discovery);}
- (void)deviceBrowser:(ICDeviceBrowser *)browser didRemoveDevice:(ICDevice *)device moreGoing:(BOOL)moreGoing {if(self.active.device==device)[self.active close];}
- (void)dealloc {
  [_slots close];[_active close];ICDeviceBrowser *browser=_browser;
  mainSync(^{browser.delegate=nil;[browser stop];});
}
@end

@implementation HueviaWiredClient
- (void)wait:(dispatch_semaphore_t)semaphore {
  for(int i=0;i<120;i++){
    if(self.cancellation&&[self.cancellation getAsBoolean]){[self close];wiredFailure(@"USB 相机操作已取消。");}
    if(dispatch_semaphore_wait(semaphore,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC/4))==0)return;
    if(!self.open)wiredFailure(@"USB 相机已断开，请重新连接。");
  }
  [self close];wiredFailure(@"USB 相机读取超时，请重新连接。");
}
- (IOSByteArray *)connectWithNSString:(NSString *)host withInt:(jint)port withByteArray:(IOSByteArray *)guid withNSString:(NSString *)name {
  [self openSession];return [self readAlbumDeviceInfo];
}
- (void)openSession {
  if(self.cancellation&&[self.cancellation getAsBoolean])wiredFailure(@"USB 相机连接已取消。");
  self.open=YES;self.ready=dispatch_semaphore_create(0);self.sessionError=nil;
  mainSync(^{if(!self.open||(self.cancellation&&[self.cancellation getAsBoolean])){dispatch_semaphore_signal(self.ready);return;}self.device.delegate=self;[self.device requestOpenSessionWithOptions:nil completion:^(NSError *error){if(error){self.sessionError=error;dispatch_semaphore_signal(self.ready);}}];});
  [self wait:self.ready];if(self.sessionError){[self close];wiredFailure(@"USB 相机会话无法打开，请关闭其他相机应用后重连。");}
}
- (bool)isOpen {return self.open;}
- (bool)isProtocolUnconfirmed {return false;}
- (NSString *)closeReason {return self.open?@"":@"USB 相机已断开";}
- (NSString *)connectedHost {return [@"usb:" stringByAppendingString:deviceID(self.device)];}
- (jint)connectedPort {return 0;}
- (NSString *)cameraIdentity {return @"";}
- (void)setOnClosedWithJavaLangRunnable:(id<JavaLangRunnable>)listener {self.closed=listener;}
- (void)setOnObjectAddedWithJavaUtilFunctionLongConsumer:(id<JavaUtilFunctionLongConsumer>)listener {}
- (void)setConnectionStageListenerWithJavaUtilFunctionConsumer:(id)listener {}
- (void)beginPhotoPage {}
- (void)endPhotoPage {}
- (IOSByteArray *)readAlbumDeviceInfo {return [self getDataWithInt:0x1001 withInt:65536 withLongArray:[IOSLongArray arrayWithLength:0]];}
- (IOSByteArray *)getDataWithInt:(jint)operation withInt:(jint)limit withLongArray:(IOSLongArray *)parameters {
  if(!self.open)wiredFailure(@"USB 相机已断开。");
  if(!(operation==0x1001||operation==0x1004||operation==0x1007||operation==0x1008||operation==0x100a)||parameters->size_>3||limit<1||limit>8*1024*1024)wiredFailure(@"USB 照片连接只允许读取目录、信息和缩略图。");
  uint32_t transaction=++self.transaction;NSMutableData *command=[NSMutableData data];append32(command,12+4*(uint32_t)parameters->size_);
  uint8_t header[4]={1,0,operation,operation>>8};[command appendBytes:header length:4];append32(command,transaction);
  for(jint i=0;i<parameters->size_;i++)append32(command,(uint32_t)IOSLongArray_Get(parameters,i));
  dispatch_semaphore_t done=dispatch_semaphore_create(0);__block NSData *bytes=nil,*response=nil;__block NSError *failure=nil;
  mainSync(^{if(!self.open||(self.cancellation&&[self.cancellation getAsBoolean])){dispatch_semaphore_signal(done);return;}[self.device requestSendPTPCommand:command outData:nil completion:^(NSData *reply,NSData *data,NSError *error){response=reply;bytes=data;failure=error;dispatch_semaphore_signal(done);}];});
  [self wait:done];if(failure)wiredFailure(@"USB 相机读取失败，请检查数据线后重连。");
  if(response.length<12)wiredFailure(@"USB 相机返回的响应不完整。");const uint8_t *r=response.bytes;int code=r[6]|(int)r[7]<<8;
  if(code!=0x2001)@throw [[CcHueviaPtpPtpResponseException alloc] initWithInt:code withLong:transaction];
  if(bytes.length>(NSUInteger)limit)wiredFailure(@"USB 相机返回的数据超出范围。");return javaBytes(bytes?:[NSData data]);
}
- (IOSByteArray *)getLargeThumbnailWithLong:(jlong)handle {@throw [[CcHueviaPtpPtpResponseException alloc] initWithInt:0x2005 withLong:0];}
- (jlong)readToWithInt:(jint)operation withJavaIoOutputStream:(JavaIoOutputStream *)destination withLong:(jlong)maximum withLong:(jlong)expected withCcHueviaAlbumPhotoCameraClient_Progress:(id<CcHueviaAlbumPhotoCameraClient_Progress>)progress withLongArray:(IOSLongArray *)parameters {
  if(operation!=0x1009||parameters->size_!=1||expected<4||expected>maximum||expected>512LL*1024*1024)wiredFailure(@"USB 原文件请求无效。");
  jlong handle=IOSLongArray_Get(parameters,0);__block ICCameraFile *file=nil;
  mainSync(^{for(ICCameraFile *candidate in self.device.mediaFiles)if(candidate.ptpObjectHandle==(uint32_t)handle){file=candidate;break;}});
  if(!file)wiredFailure(@"USB 照片不在当前相机目录中，请重新读取。");
  jlong received=0;while(received<expected){@autoreleasepool{
    if(!self.open)wiredFailure(@"USB 相机已断开，原文件未保存。");
    jlong count=MIN(256*1024,expected-received);dispatch_semaphore_t done=dispatch_semaphore_create(0);__block NSData *data=nil;__block NSError *failure=nil;
    mainSync(^{if(!self.open||(self.cancellation&&[self.cancellation getAsBoolean])){dispatch_semaphore_signal(done);return;}[file requestReadDataAtOffset:received length:count completion:^(NSData *bytes,NSError *error){data=bytes;failure=error;dispatch_semaphore_signal(done);}];});
    [self wait:done];if(failure||data.length<1||data.length>(NSUInteger)count)wiredFailure(@"USB 原文件接收中断，未保存不完整照片。");
    IOSByteArray *part=javaBytes(data);[destination writeWithByteArray:part withInt:0 withInt:(jint)data.length];received+=data.length;[progress onProgressWithLong:received withLong:expected];
  }}return received;
}
- (void)abortProtocolWithJavaIoIOException:(JavaIoIOException *)failure {[self close];}
- (void)waitForClose {
  dispatch_semaphore_t done=self.closing;if(!done)return;
  if(!HueviaAwaitCameraResponse(done,15,self.cancellation))wiredFailure(@"上一次 USB 会话尚未关闭，请检查数据线后重试。");
  if(self.closing==done)self.closing=nil;
}
- (void)close {
  ICCameraDevice *device;dispatch_semaphore_t done;
  @synchronized(self){
    if(!self.open)return;self.open=NO;device=self.device;
    done=dispatch_semaphore_create(0);self.closing=done;self.closeError=nil;
  }
  // Reads use ICCameraFile's data API, not the macOS-only download API.
  // Keep this client alive until its unretained delegate is cleared on main.
  // The worker observes open=NO; a reconnect waits for OS close completion.
  dispatch_async(dispatch_get_main_queue(),^{
    if(device.delegate==self)device.delegate=nil;
    [device requestCloseSessionWithOptions:nil completion:^(NSError *error){self.closeError=error;dispatch_semaphore_signal(done);}];
  });
  id<JavaLangRunnable> listener=self.closed;self.closed=nil;if(listener)[listener run];
}
- (void)deviceDidBecomeReadyWithCompleteContentCatalog:(ICCameraDevice *)device {dispatch_semaphore_signal(self.ready);}
- (void)device:(ICDevice *)device didOpenSessionWithError:(NSError *)error {if(error){self.sessionError=error;dispatch_semaphore_signal(self.ready);}}
- (void)device:(ICDevice *)device didCloseSessionWithError:(NSError *)error {[self close];}
- (void)didRemoveDevice:(ICDevice *)device {[self close];}
- (void)deviceDidBecomeReady:(ICDevice *)device {if(self.ready)dispatch_semaphore_signal(self.ready);}
- (void)device:(ICDevice *)device didReceiveStatusInformation:(NSDictionary *)status {}
- (void)device:(ICDevice *)device didEjectWithError:(NSError *)error {if(error)[self close];}
- (void)device:(ICDevice *)device didEncounterError:(NSError *)error {[self close];}
- (void)cameraDevice:(ICCameraDevice *)camera didAddItems:(NSArray<ICCameraItem *> *)items {}
- (void)cameraDevice:(ICCameraDevice *)camera didRemoveItems:(NSArray<ICCameraItem *> *)items {}
- (void)cameraDevice:(ICCameraDevice *)camera didRenameItems:(NSArray<ICCameraItem *> *)items {}
- (void)cameraDevice:(ICCameraDevice *)camera didReceiveThumbnail:(CGImageRef)image forItem:(ICCameraItem *)item error:(NSError *)error {}
- (void)cameraDevice:(ICCameraDevice *)camera didReceiveMetadata:(NSDictionary *)metadata forItem:(ICCameraItem *)item error:(NSError *)error {}
- (void)cameraDeviceDidChangeCapability:(ICCameraDevice *)camera {}
- (void)cameraDeviceDidEnableAccessRestriction:(ICDevice *)camera {[self close];}
- (void)cameraDeviceDidRemoveAccessRestriction:(ICDevice *)camera {}
- (void)cameraDevice:(ICCameraDevice *)camera didReceivePTPEvent:(NSData *)event {}
@end

/** ICC owns the PTP session. Logical session operations map to actual, awaited OS operations. */
@implementation HueviaWiredSlots
- (bool)isSessionManaged {return true;}
- (bool)isOpen {return self.client!=nil&&self.client.open;}
- (void)authorizeDeletionWithInt:(jint)target {[self.guard authorizeDeletionWithInt:target];}
- (void)authorizeParametersWithJavaUtilMap:(id<JavaUtilMap>)values {[self.guard authorizeParametersWithJavaUtilMap:values];}
- (IOSByteArray *)exchange:(jint)operation transaction:(jlong)transaction parameters:(IOSLongArray *)parameters outgoing:(IOSByteArray *)outgoing {
  HueviaWiredClient *client=self.client;if(!client||!client.open)wiredFailure(@"USB 槽位会话已断开。");
  IOSByteArray *encoded=[[CcHueviaPtpPtpContainer commandWithInt:operation withLong:transaction withLongArray:parameters] toBytes];
  NSData *command=[NSData dataWithBytes:encoded->buffer_ length:encoded->size_];
  NSData *outData=outgoing?[NSData dataWithBytes:outgoing->buffer_ length:outgoing->size_]:nil;
  dispatch_semaphore_t done=dispatch_semaphore_create(0);__block NSData *bytes=nil,*response=nil;__block NSError *failure=nil;
  mainSync(^{if(!client.open||(client.cancellation&&[client.cancellation getAsBoolean])){dispatch_semaphore_signal(done);return;}[client.device requestSendPTPCommand:command outData:outData completion:^(NSData *reply,NSData *data,NSError *error){response=reply;bytes=data;failure=error;dispatch_semaphore_signal(done);}];});
  [client wait:done];
  if(failure){[self close];wiredFailure(@"USB 槽位操作响应未确认，连接已关闭；请只读核对，勿重复执行。");}
  if(response.length<12||response.length>32){[self close];wiredFailure(@"USB 槽位响应长度无效。");}
  const uint8_t *r=response.bytes;
  if(little32(r)!=response.length||r[4]!=3||r[5]!=0||little32(r+8)!=(uint32_t)transaction||(response.length-12)%4){[self close];wiredFailure(@"USB 槽位响应事务或容器无效，已停止。");}
  int code=r[6]|(int)r[7]<<8;if(code!=0x2001)@throw [[CcHueviaPtpPtpResponseException alloc] initWithInt:code withLong:transaction];
  if(bytes.length>1024*1024){[self close];wiredFailure(@"USB 槽位数据超出范围。");}
  return javaBytes(bytes?:[NSData data]);
}
- (IOSByteArray *)readWithInt:(jint)operation withLong:(jlong)transaction withLongArray:(IOSLongArray *)parameters {
  [self.guard readWithInt:operation withLong:transaction withLongArray:parameters];
  IOSByteArray *bytes=[self exchange:operation transaction:transaction parameters:parameters outgoing:nil];
  [self.guard observeReadbackWithInt:operation withByteArray:bytes withLongArray:parameters];return bytes;
}
- (CcHueviaPtpPtpContainer *)commandWithInt:(jint)operation withLong:(jlong)transaction withLongArray:(IOSLongArray *)parameters {
  [self.guard commandWithInt:operation withLong:transaction withLongArray:parameters];
  if(!self.client)wiredFailure(@"USB 槽位会话已取消。");
  if(operation==0x1002){[self.client openSession];}
  else if(operation==0x1003){HueviaWiredClient *client=self.client;[client close];[client waitForClose];if(client.closeError)wiredFailure(@"USB 槽位系统会话关闭未确认。");}
  else [self exchange:operation transaction:transaction parameters:parameters outgoing:nil];
  return [CcHueviaPtpPtpContainer responseWithInt:0x2001 withLong:transaction withLongArray:[IOSLongArray arrayWithLength:0]];
}
- (CcHueviaPtpPtpContainer *)sendWithInt:(jint)operation withLong:(jlong)transaction withByteArray:(IOSByteArray *)bytes withLongArray:(IOSLongArray *)parameters {
  [self.guard sendWithInt:operation withLong:transaction withByteArray:bytes withLongArray:parameters];
  [self exchange:operation transaction:transaction parameters:parameters outgoing:bytes];
  CcHueviaPtpPtpContainer *response=[CcHueviaPtpPtpContainer responseWithInt:0x2001 withLong:transaction withLongArray:[IOSLongArray arrayWithLength:0]];
  [self.guard observeWriteResponseWithInt:operation withLong:transaction withCcHueviaPtpPtpContainer:response];return response;
}
- (void)close {HueviaWiredClient *client=self.client;self.client=nil;[client close];}
@end
