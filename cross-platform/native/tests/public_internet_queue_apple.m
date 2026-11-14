#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#include <stdio.h>
#import "HueviaPublicInternetQueues.h"

static void require(BOOL value,NSString *message){if(!value)@throw [NSException exceptionWithName:@"PublicInternetQueueFailure" reason:message userInfo:nil];}
int main(void){@autoreleasepool{
  HueviaPublicInternetQueues *queues=[[HueviaPublicInternetQueues alloc] init];
  dispatch_queue_t camera=dispatch_queue_create("fixture.camera.original-serial",DISPATCH_QUEUE_SERIAL);
  dispatch_semaphore_t accountEntered=dispatch_semaphore_create(0),publicEntered=dispatch_semaphore_create(0);
  dispatch_semaphore_t accountRelease=dispatch_semaphore_create(0),publicRelease=dispatch_semaphore_create(0);
  dispatch_group_t completed=dispatch_group_create();
  NSObject *counts=[[NSObject alloc] init];
  __block NSInteger activeAccount=0,activePublic=0,peakAccount=0,peakPublic=0;
  for(NSInteger index=0;index<10;index++){
    require([queues hasCapacityForAccount:YES],@"Account capacity rejected a bounded job");
    dispatch_group_enter(completed);
    [queues enqueueAccount:YES block:^{@autoreleasepool{
      @synchronized(counts){activeAccount++;peakAccount=MAX(peakAccount,activeAccount);}
      dispatch_semaphore_signal(accountEntered);
      dispatch_semaphore_wait(accountRelease,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC));
      @synchronized(counts){activeAccount--;}
      dispatch_group_leave(completed);
    }}];
  }
  require(![queues hasCapacityForAccount:YES],@"Blocked account work must respect its own bound");
  for(NSInteger index=0;index<3;index++){
    dispatch_group_enter(completed);
    [queues enqueueAccount:NO block:^{@autoreleasepool{
      @synchronized(counts){activePublic++;peakPublic=MAX(peakPublic,activePublic);}
      dispatch_semaphore_signal(publicEntered);
      dispatch_semaphore_wait(publicRelease,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC));
      @synchronized(counts){activePublic--;}
      dispatch_group_leave(completed);
    }}];
  }
  for(NSInteger index=0;index<2;index++)require(dispatch_semaphore_wait(accountEntered,dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC))==0,@"Account workers did not start");
  for(NSInteger index=0;index<3;index++)require(dispatch_semaphore_wait(publicEntered,dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC))==0,@"Public reads were blocked by account I/O");
  __block NSInteger beats=0;
  dispatch_semaphore_t heartbeat=dispatch_semaphore_create(0);
  for(NSInteger index=0;index<16;index++)dispatch_async(camera,^{beats++;dispatch_semaphore_signal(heartbeat);});
  for(NSInteger index=0;index<16;index++)require(dispatch_semaphore_wait(heartbeat,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC))==0,@"Serial camera commands stalled behind public I/O");
  @synchronized(counts){require(activeAccount==2&&activePublic==3,@"Camera heartbeat must run while both public queues remain blocked");}
  for(NSInteger index=0;index<10;index++)dispatch_semaphore_signal(accountRelease);
  for(NSInteger index=0;index<3;index++)dispatch_semaphore_signal(publicRelease);
  require(dispatch_group_wait(completed,dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC))==0,@"Public work did not complete independently");
  require(beats==16&&peakAccount==2&&peakPublic==3,@"The camera serial queue or public concurrency bound changed");
  puts("PASS Apple public I/O queue isolation: account/public waits preserve serial camera heartbeat; no physical camera exercised");
  return 0;
}}
