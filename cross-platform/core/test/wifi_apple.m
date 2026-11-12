#import <Foundation/Foundation.h>
#import "HueviaWifiSocket.h"
#import "java/io/InputStream.h"
#import "java/io/OutputStream.h"
#import "java/net/SocketTimeoutException.h"
#import "java/net/ConnectException.h"
#import "IOSPrimitiveArray.h"
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>

static int checks;
static void yes(BOOL value){checks++;if(!value)@throw [NSException exceptionWithName:@"WifiBoundary" reason:[NSString stringWithFormat:@"check %d",checks] userInfo:nil];}
static int listener(uint16_t *port){int fd=socket(AF_INET,SOCK_STREAM,0);struct sockaddr_in address={0};address.sin_len=sizeof(address);address.sin_family=AF_INET;address.sin_addr.s_addr=htonl(INADDR_LOOPBACK);yes(bind(fd,(struct sockaddr *)&address,sizeof(address))==0);socklen_t size=sizeof(address);yes(getsockname(fd,(struct sockaddr *)&address,&size)==0);*port=ntohs(address.sin_port);yes(listen(fd,4)==0);return fd;}
int main(void){@autoreleasepool{@try{
  uint16_t port;int server=listener(&port);dispatch_semaphore_t finished=dispatch_semaphore_create(0);
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
    int peer=accept(server,NULL,NULL);char bytes[6]={0};size_t offset=0;
    while(offset<6){ssize_t n=read(peer,bytes+offset,6-offset);if(n<=0)break;offset+=n;}
    if(offset==6){write(peer,bytes,2);usleep(30000);write(peer,bytes+2,4);}
    char probe;while(read(peer,&probe,1)>0){}close(peer);dispatch_semaphore_signal(finished);
  });
  // A local fixture bypasses the Wi-Fi requirement; the production connector
  // always passes YES and has no cellular/ethernet fallback.
  HueviaWifiSocket *socket=[[HueviaWifiSocket alloc] initWithHost:@"127.0.0.1" port:port timeout:3000 wifiOnly:NO];
  [socket setSoTimeoutWithInt:2000];JavaIoInputStream *input=[socket getInputStream];JavaIoOutputStream *output=[socket getOutputStream];
  IOSByteArray *bytes=[IOSByteArray arrayWithLength:10];for(int i=0;i<6;i++)bytes->buffer_[i+2]=i+1;
  [output writeWithByteArray:bytes withInt:2 withInt:6];IOSByteArray *readback=[IOSByteArray arrayWithLength:10];int32_t received=0;
  while(received<6){int32_t n=[input readWithByteArray:readback withInt:received+1 withInt:6-received];yes(n>0);received+=n;}
  for(int i=0;i<6;i++)yes(readback->buffer_[i+1]==i+1);yes(readback->buffer_[0]==0);yes([input readWithByteArray:readback withInt:0 withInt:0]==0);
  [socket setSoTimeoutWithInt:80];BOOL timedOut=NO;@try{[input read];}@catch(JavaNetSocketTimeoutException *expected){timedOut=YES;}yes(timedOut);yes([socket isClosed]);
  yes(dispatch_semaphore_wait(finished,dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC))==0);close(server);
  BOOL refused=NO;@try{(void)[[HueviaWifiSocket alloc] initWithHost:@"127.0.0.1" port:port timeout:2000 wifiOnly:NO];}@catch(JavaNetConnectException *expected){refused=YES;}yes(refused);
  // A concurrent close interrupts a read with an infinite event-channel timeout.
  server=listener(&port);int heldServer=server;dispatch_semaphore_t accepted=dispatch_semaphore_create(0);
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{int peer=accept(heldServer,NULL,NULL);dispatch_semaphore_signal(accepted);char b;while(read(peer,&b,1)>0){}close(peer);});
  socket=[[HueviaWifiSocket alloc] initWithHost:@"127.0.0.1" port:port timeout:2000 wifiOnly:NO];input=[socket getInputStream];
  yes(dispatch_semaphore_wait(accepted,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC))==0);HueviaWifiSocket *closing=socket;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,80000000),dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{[closing close];});
  BOOL interrupted=NO;@try{[input read];}@catch(id expected){interrupted=YES;}yes(interrupted);yes([socket isClosed]);close(server);
  printf("PASS %d Apple Wi-Fi stream checks; exact bytes, offsets, segmented reads, timeout, refusal and concurrent close\n",checks);return 0;
}@catch(id error){fprintf(stderr,"Apple Wi-Fi checks failed: %s\n",[[error description] UTF8String]);return 1;}}}
