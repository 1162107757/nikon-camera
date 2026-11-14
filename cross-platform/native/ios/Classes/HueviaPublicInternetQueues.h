#import <Foundation/Foundation.h>

/** Owns only public-service I/O. Camera actors and their cancellation are not retained here. */
@interface HueviaPublicInternetQueues : NSObject
- (BOOL)hasCapacityForAccount:(BOOL)account;
- (void)enqueueAccount:(BOOL)account block:(void (^)(void))block;
@end
