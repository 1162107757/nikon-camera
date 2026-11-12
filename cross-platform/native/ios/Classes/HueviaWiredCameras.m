#import "HueviaWiredCameras.h"
#import "cc/huevia/album/PhotoCameraClient.h"
#import "cc/huevia/ptp/PtpResponseException.h"
#import "java/io/IOException.h"
#import "java/io/OutputStream.h"
#import "java/lang/Runnable.h"
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
@property(nonatomic,strong) id<JavaLangRunnable> closed;
@property(nonatomic,strong) dispatch_semaphore_t ready;
@property(atomic,strong) NSError *sessionError;
@property(nonatomic) uint32_t transaction;
@end
@interface HueviaWiredCameras ()
@property(nonatomic,strong) ICDeviceBrowser *browser;
@property(nonatomic,strong) HueviaWiredClient *active;
@property(nonatomic,strong) dispatch_semaphore_t discovery;
@end

@implementation HueviaWiredCameras
- (NSString *)devices {
  __block ICAuthorizationStatus authorization=ICAuthorizationStatusNotDetermined;
  dispatch_semaphore_t permission=dispatch_semaphore_create(0);
  mainSync(^{
    if(!self.browser){self.browser=[[ICDeviceBrowser alloc] init];self.browser.delegate=self;self.browser.browsedDeviceTypeMask=ICDeviceTypeMaskCamera|ICDeviceLocationTypeMaskLocal;}
    [self.browser requestContentsAuthorizationWithCompletion:^(ICAuthorizationStatus status){authorization=status;dispatch_semaphore_signal(permission);}];
  });
  if(dispatch_semaphore_wait(permission,dispatch_time(DISPATCH_TIME_NOW,45*NSEC_PER_SEC)))wiredFailure(@"USB 相机授权超时，请重试。");
  if(![authorization isEqualToString:ICAuthorizationStatusAuthorized])wiredFailure(@"请在 iPhone 设置中允许 Huevia 访问外接相机，然后重试。");
  __block BOOL starting=NO;mainSync(^{if(!self.browser.browsing){starting=YES;self.discovery=dispatch_semaphore_create(0);[self.browser start];}});
  if(starting)dispatch_semaphore_wait(self.discovery,dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC));
  // Discovery is asynchronous; a subsequent refresh can add a newly attached camera.
  NSMutableArray *rows=[NSMutableArray array];mainSync(^{for(ICDevice *device in self.browser.devices)if(supported(device))[rows addObject:@{@"id":deviceID(device),@"name":device.name?:@"Nikon USB 相机",@"permission":@YES}];});
  return [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:@{@"items":rows,@"transport":@"usb"} options:0 error:nil] encoding:NSUTF8StringEncoding];
}
- (id<CcHueviaAlbumPhotoCameraClient>)createWithNSString:(NSString *)identity {
  dispatch_semaphore_t permission=dispatch_semaphore_create(0);__block ICAuthorizationStatus authorization=nil;
  mainSync(^{[self.browser requestControlAuthorizationWithCompletion:^(ICAuthorizationStatus status){authorization=status;dispatch_semaphore_signal(permission);}];});
  if(dispatch_semaphore_wait(permission,dispatch_time(DISPATCH_TIME_NOW,45*NSEC_PER_SEC))||![authorization isEqualToString:ICAuthorizationStatusAuthorized])wiredFailure(@"请允许访问外接相机会话后重试有线连接。");
  __block ICCameraDevice *selected=nil;mainSync(^{for(ICDevice *device in self.browser.devices)if(supported(device)&&[deviceID(device) isEqualToString:identity]){selected=(ICCameraDevice *)device;break;}});
  if(!selected)wiredFailure(@"未找到该 USB 相机，请检查相机开机、数据线和转接器后重新检测。");
  HueviaWiredClient *client=[[HueviaWiredClient alloc] init];client.device=selected;self.active=client;return client;
}
- (void)deviceBrowser:(ICDeviceBrowser *)browser didAddDevice:(ICDevice *)device moreComing:(BOOL)moreComing {if(self.discovery&&supported(device))dispatch_semaphore_signal(self.discovery);}
- (void)deviceBrowser:(ICDeviceBrowser *)browser didRemoveDevice:(ICDevice *)device moreGoing:(BOOL)moreGoing {if(self.active.device==device)[self.active close];}
- (void)dealloc {[_active close];[_browser stop];}
@end

@implementation HueviaWiredClient
- (void)wait:(dispatch_semaphore_t)semaphore {
  for(int i=0;i<120;i++){
    if(dispatch_semaphore_wait(semaphore,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC/4))==0)return;
    if(!self.open)wiredFailure(@"USB 相机已断开，请重新连接。");
  }
  [self close];wiredFailure(@"USB 相机读取超时，请重新连接。");
}
- (IOSByteArray *)connectWithNSString:(NSString *)host withInt:(jint)port withByteArray:(IOSByteArray *)guid withNSString:(NSString *)name {
  self.open=YES;self.ready=dispatch_semaphore_create(0);self.sessionError=nil;
  mainSync(^{self.device.delegate=self;[self.device requestOpenSessionWithOptions:nil completion:^(NSError *error){if(error){self.sessionError=error;dispatch_semaphore_signal(self.ready);}}];});
  [self wait:self.ready];if(self.sessionError){[self close];wiredFailure(@"USB 相机会话无法打开，请关闭其他相机应用后重连。");}
  return [self readAlbumDeviceInfo];
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
  mainSync(^{[self.device requestSendPTPCommand:command outData:nil completion:^(NSData *reply,NSData *data,NSError *error){response=reply;bytes=data;failure=error;dispatch_semaphore_signal(done);}];});
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
    mainSync(^{[file requestReadDataAtOffset:received length:count completion:^(NSData *bytes,NSError *error){data=bytes;failure=error;dispatch_semaphore_signal(done);}];});
    [self wait:done];if(failure||data.length<1||data.length>(NSUInteger)count)wiredFailure(@"USB 原文件接收中断，未保存不完整照片。");
    IOSByteArray *part=javaBytes(data);[destination writeWithByteArray:part withInt:0 withInt:(jint)data.length];received+=data.length;[progress onProgressWithLong:received withLong:expected];
  }}return received;
}
- (void)abortProtocolWithJavaIoIOException:(JavaIoIOException *)failure {[self close];}
- (void)close {
  BOOL wasOpen=self.open;self.open=NO;if(!wasOpen)return;ICCameraDevice *device=self.device;
  // Reads use ICCameraFile's data API, not the macOS-only download API.
  // Closing the iOS session retires pending reads; wait: observes open=NO.
  dispatch_async(dispatch_get_main_queue(),^{[device requestCloseSession];});
  id<JavaLangRunnable> listener=self.closed;self.closed=nil;if(listener)[listener run];
}
- (void)deviceDidBecomeReadyWithCompleteContentCatalog:(ICCameraDevice *)device {dispatch_semaphore_signal(self.ready);}
- (void)device:(ICDevice *)device didOpenSessionWithError:(NSError *)error {if(error){self.sessionError=error;dispatch_semaphore_signal(self.ready);}}
- (void)device:(ICDevice *)device didCloseSessionWithError:(NSError *)error {self.open=NO;}
- (void)didRemoveDevice:(ICDevice *)device {[self close];}
- (void)deviceDidBecomeReady:(ICDevice *)device {}
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
