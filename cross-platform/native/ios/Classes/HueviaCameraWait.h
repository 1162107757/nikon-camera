#import <Foundation/Foundation.h>
#import "java/util/function/BooleanSupplier.h"

/** Worker-only wait. Cancellation is independent of a delayed OS callback. */
FOUNDATION_EXPORT BOOL HueviaAwaitCameraResponse(dispatch_semaphore_t semaphore,
  double seconds,id<JavaUtilFunctionBooleanSupplier> cancel);
