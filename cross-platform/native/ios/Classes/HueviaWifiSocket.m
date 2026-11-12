#import "HueviaWifiSocket.h"
#import <Network/Network.h>
#import "java/io/InputStream.h"
#import "java/io/OutputStream.h"
#import "java/io/IOException.h"
#import "java/net/ConnectException.h"
#import "java/net/NoRouteToHostException.h"
#import "java/net/SocketTimeoutException.h"
#import "IOSPrimitiveArray.h"
#include <errno.h>
#include <string.h>

static void socketFailure(nw_error_t error) {
  int code=error?nw_error_get_error_code(error):0;
  if(error&&nw_error_get_error_domain(error)==nw_error_domain_posix){
    if(code==ECONNREFUSED)@throw [[JavaNetConnectException alloc] initWithNSString:@"Connection refused：请核对相机 IP、端口，并断开其他手机或 SnapBridge 后重试。"];
    if(code==EACCES||code==EPERM)@throw [[JavaIoIOException alloc] initWithNSString:@"请在 iPhone 设置中允许本应用访问本地网络，再重新连接相机 Wi-Fi。"];
    if(code==ENETDOWN||code==ENETUNREACH||code==EHOSTUNREACH)@throw [[JavaNetNoRouteToHostException alloc] initWithNSString:@"相机 Wi-Fi 通道不可用，请连接相机 Wi-Fi 并检查本地网络权限。"];
  }
  @throw [[JavaIoIOException alloc] initWithNSString:@"相机 Wi-Fi 通道已中断，请重新连接。"];
}

@interface HueviaWifiSocket ()
@property(nonatomic,strong) nw_connection_t connection;
@property(nonatomic,strong) dispatch_queue_t networkQueue;
@property(nonatomic) int32_t receiveTimeout;
@property(atomic) BOOL channelClosed;
- (int32_t)receive:(IOSByteArray *)bytes offset:(int32_t)offset length:(int32_t)length;
- (void)send:(IOSByteArray *)bytes offset:(int32_t)offset length:(int32_t)length;
@end
@interface HueviaSocketInput : JavaIoInputStream
@property(nonatomic,weak) HueviaWifiSocket *socket;
@end
@interface HueviaSocketOutput : JavaIoOutputStream
@property(nonatomic,weak) HueviaWifiSocket *socket;
@end

@implementation HueviaSockets
- (id<CcHueviaAlbumPtpIpClient_SocketConnector>)createWithNSString:(NSString *)host withInt:(int32_t)port withBoolean:(bool)fuji { return self; }
- (JavaNetSocket *)connectWithNSString:(NSString *)host withInt:(int32_t)port withInt:(int32_t)timeout {
  return [[HueviaWifiSocket alloc] initWithHost:host port:port timeout:timeout wifiOnly:YES];
}
@end

@implementation HueviaWifiSocket
- (instancetype)initWithHost:(NSString *)host port:(int32_t)port timeout:(int32_t)timeout wifiOnly:(BOOL)wifiOnly {
  if(!(self=[super init]))return nil;
  _networkQueue=dispatch_queue_create("cc.huevia.camera.socket",DISPATCH_QUEUE_SERIAL);
  nw_parameters_t parameters=nw_parameters_create_secure_tcp(NW_PARAMETERS_DISABLE_PROTOCOL,NW_PARAMETERS_DEFAULT_CONFIGURATION);
  if(wifiOnly){nw_parameters_set_required_interface_type(parameters,nw_interface_type_wifi);nw_parameters_set_prohibit_expensive(parameters,true);}
  nw_protocol_stack_t stack=nw_parameters_copy_default_protocol_stack(parameters);
  nw_protocol_options_t tcp=nw_protocol_stack_copy_transport_protocol(stack);
  nw_tcp_options_set_no_delay(tcp,true);
  nw_endpoint_t endpoint=nw_endpoint_create_host(host.UTF8String,[[NSString stringWithFormat:@"%d",port] UTF8String]);
  _connection=nw_connection_create(endpoint,parameters);
  dispatch_semaphore_t ready=dispatch_semaphore_create(0);
  __block nw_error_t failure=nil;
  __block BOOL connected=NO,finished=NO;
  nw_connection_set_state_changed_handler(_connection,^(nw_connection_state_t state,nw_error_t error){
    if(finished)return;
    if(state==nw_connection_state_ready){connected=YES;finished=YES;dispatch_semaphore_signal(ready);}
    else if(state==nw_connection_state_failed||state==nw_connection_state_cancelled){failure=error;finished=YES;dispatch_semaphore_signal(ready);}
    else if(state==nw_connection_state_waiting&&error&&nw_error_get_error_domain(error)==nw_error_domain_posix){
      int code=nw_error_get_error_code(error);
      if(code==ECONNREFUSED||code==EACCES||code==EPERM){failure=error;finished=YES;dispatch_semaphore_signal(ready);}
    }
    // A waiting path can become usable after the local-network permission prompt.
  });
  nw_connection_set_queue(_connection,_networkQueue);nw_connection_start(_connection);
  long waited=dispatch_semaphore_wait(ready,dispatch_time(DISPATCH_TIME_NOW,(int64_t)MAX(timeout,1)*NSEC_PER_MSEC));
  if(waited||!connected){[self close];if(waited)@throw [[JavaNetSocketTimeoutException alloc] initWithNSString:@"相机 Wi-Fi 连接超时，请检查相机 IP、端口和本地网络权限后重试。"] ;socketFailure(failure);}
  nw_connection_set_state_changed_handler(_connection,nil);
  return self;
}
- (void)setSoTimeoutWithInt:(int32_t)timeout { _receiveTimeout=MAX(0,timeout); }
- (void)setTcpNoDelayWithBoolean:(bool)enabled { /* Network.framework TCP handles packet delivery. */ }
- (JavaIoInputStream *)getInputStream { HueviaSocketInput *input=[HueviaSocketInput new];input.socket=self;return input; }
- (JavaIoOutputStream *)getOutputStream { HueviaSocketOutput *output=[HueviaSocketOutput new];output.socket=self;return output; }
- (bool)isClosed { return self.channelClosed; }
- (void)close { @synchronized(self){if(_channelClosed)return;_channelClosed=YES;if(_connection)nw_connection_cancel(_connection);} }
- (void)dealloc { if(_connection)nw_connection_cancel(_connection); }
- (int32_t)receive:(IOSByteArray *)bytes offset:(int32_t)offset length:(int32_t)length {
  if(!bytes||offset<0||length<0||offset>bytes->size_-length)@throw [[JavaIoIOException alloc] initWithNSString:@"相机接收缓冲区无效。"];
  if(length==0)return 0;
  if(self.channelClosed)socketFailure(nil);
  dispatch_semaphore_t received=dispatch_semaphore_create(0);
  __block NSData *data=nil;__block nw_error_t failure=nil;__block BOOL complete=NO;
  nw_connection_receive(_connection,1,(uint32_t)length,^(dispatch_data_t content,nw_content_context_t context,bool done,nw_error_t error){
    if(content){NSMutableData *copy=[NSMutableData dataWithCapacity:dispatch_data_get_size(content)];dispatch_data_apply(content,^bool(dispatch_data_t region,size_t offset,const void *buffer,size_t size){[copy appendBytes:buffer length:size];return true;});data=copy;}
    failure=error;complete=done;dispatch_semaphore_signal(received);
  });
  dispatch_time_t deadline=_receiveTimeout?dispatch_time(DISPATCH_TIME_NOW,(int64_t)_receiveTimeout*NSEC_PER_MSEC):DISPATCH_TIME_FOREVER;
  if(dispatch_semaphore_wait(received,deadline)){[self close];@throw [[JavaNetSocketTimeoutException alloc] initWithNSString:@"相机数据接收超时。"] ;}
  if(data.length){memcpy(bytes->buffer_+offset,data.bytes,data.length);return (int32_t)data.length;}
  if(failure)socketFailure(failure);
  if(complete)return -1;
  socketFailure(nil);return -1;
}
- (void)send:(IOSByteArray *)bytes offset:(int32_t)offset length:(int32_t)length {
  if(!bytes||offset<0||length<0||offset>bytes->size_-length)@throw [[JavaIoIOException alloc] initWithNSString:@"相机发送缓冲区无效。"];
  if(length==0)return;
  if(self.channelClosed)socketFailure(nil);
  // dispatch_data owns a copy, including when cancellation wins the deadline.
  NSData *copy=[NSData dataWithBytes:bytes->buffer_+offset length:length];
  dispatch_data_t data=dispatch_data_create(copy.bytes,copy.length,_networkQueue,^{(void)copy;});
  dispatch_semaphore_t sent=dispatch_semaphore_create(0);__block nw_error_t failure=nil;
  nw_connection_send(_connection,data,NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT,true,^(nw_error_t error){failure=error;dispatch_semaphore_signal(sent);});
  if(dispatch_semaphore_wait(sent,dispatch_time(DISPATCH_TIME_NOW,15*NSEC_PER_SEC))){[self close];@throw [[JavaNetSocketTimeoutException alloc] initWithNSString:@"相机数据发送超时。"] ;}
  if(failure)socketFailure(failure);
}
@end

@implementation HueviaSocketInput
- (int32_t)read { IOSByteArray *byte=[IOSByteArray arrayWithLength:1];int32_t count=[self readWithByteArray:byte withInt:0 withInt:1];return count<0?-1:((uint8_t)byte->buffer_[0]); }
- (int32_t)readWithByteArray:(IOSByteArray *)bytes withInt:(int32_t)offset withInt:(int32_t)length { HueviaWifiSocket *socket=self.socket;if(!socket)socketFailure(nil);return [socket receive:bytes offset:offset length:length]; }
- (void)close { [self.socket close]; }
@end
@implementation HueviaSocketOutput
- (void)writeWithInt:(int32_t)value { IOSByteArray *byte=[IOSByteArray arrayWithLength:1];byte->buffer_[0]=(int8_t)value;[self writeWithByteArray:byte withInt:0 withInt:1]; }
- (void)writeWithByteArray:(IOSByteArray *)bytes withInt:(int32_t)offset withInt:(int32_t)length { HueviaWifiSocket *socket=self.socket;if(!socket)socketFailure(nil);[socket send:bytes offset:offset length:length]; }
- (void)close { [self.socket close]; }
@end
