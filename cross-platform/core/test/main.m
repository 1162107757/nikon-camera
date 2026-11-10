#import <Foundation/Foundation.h>
#import "cc/huevia/shared/CoreParity.h"

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        @try {
            NSString *result = [CcHueviaSharedCoreParity run];
            printf("HUEVIA_CORE_GOLDEN=%s\n", result.UTF8String);
            return 0;
        } @catch (id error) {
            fprintf(stderr, "Shared Objective-C core failed: %s\n", [[error description] UTF8String]);
            return 1;
        }
    }
}
