#import "HueviaPublicInternetQueues.h"

@implementation HueviaPublicInternetQueues {
  NSOperationQueue *_account;
  NSOperationQueue *_publicInternet;
}
- (instancetype)init {
  self=[super init];
  if(self){
    _account=[[NSOperationQueue alloc] init];
    _account.name=@"cc.huevia.account.io";
    _account.maxConcurrentOperationCount=2;
    _account.qualityOfService=NSQualityOfServiceUtility;
    _publicInternet=[[NSOperationQueue alloc] init];
    _publicInternet.name=@"cc.huevia.public-internet.io";
    _publicInternet.maxConcurrentOperationCount=3;
    _publicInternet.qualityOfService=NSQualityOfServiceUtility;
  }
  return self;
}
- (BOOL)hasCapacityForAccount:(BOOL)account {
  return (account?_account:_publicInternet).operationCount<(account?10:51);
}
- (void)enqueueAccount:(BOOL)account block:(void (^)(void))block {
  [(account?_account:_publicInternet) addOperationWithBlock:block];
}
@end
