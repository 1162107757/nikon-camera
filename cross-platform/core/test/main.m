#import <Foundation/Foundation.h>
#import "cc/huevia/shared/CoreParity.h"
#import "HueviaCoreBootstrap.h"

int main(int argc, const char *argv[]) {
    // Match the app's separate worker tasks: initialization must survive a
    // drained pool before any later filesystem/render operation starts.
    @autoreleasepool {
        @try {HueviaLinkCoreModules();}
        @catch(id error){fprintf(stderr,"Shared bootstrap failed: %s\n",[[error description] UTF8String]);return 1;}
    }
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
