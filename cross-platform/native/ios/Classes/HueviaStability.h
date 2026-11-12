#import <Flutter/Flutter.h>

/** Bounded, local evidence. Never replaces the system's crash handling. */
@interface HueviaStability : NSObject <FlutterPlugin>
+ (void)install;
@end
