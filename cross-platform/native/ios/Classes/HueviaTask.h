#import <Foundation/Foundation.h>
#import "java/util/function/BooleanSupplier.h"
#import "java/util/function/DoubleConsumer.h"

@interface HueviaTask : NSObject <JavaUtilFunctionBooleanSupplier,JavaUtilFunctionDoubleConsumer>
@property(nonatomic,readonly) BOOL cancelled;
@property(nonatomic,copy) void (^progress)(double);
- (BOOL)cancelIfActive;
- (void)finish;
@end
