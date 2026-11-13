#import "HueviaCameraWait.h"
#import "java/io/IOException.h"

BOOL HueviaAwaitCameraResponse(dispatch_semaphore_t semaphore,double seconds,
                              id<JavaUtilFunctionBooleanSupplier> cancel) {
  double deadline=NSProcessInfo.processInfo.systemUptime+seconds;
  while(YES){
    if(cancel&&[cancel getAsBoolean])@throw [[JavaIoIOException alloc] initWithNSString:@"USB 相机操作已取消。"];
    double remaining=deadline-NSProcessInfo.processInfo.systemUptime;
    if(remaining<=0)return NO;
    if(dispatch_semaphore_wait(semaphore,dispatch_time(DISPATCH_TIME_NOW,(int64_t)(MIN(remaining,.1)*NSEC_PER_SEC)))==0){
      if(cancel&&[cancel getAsBoolean])@throw [[JavaIoIOException alloc] initWithNSString:@"USB 相机操作已取消。"];
      return YES;
    }
  }
}
