#import <Flutter/Flutter.h>
#import <UIKit/UIKit.h>

/** A finite UIKit finishing lease. It never claims unrestricted background USB/Wi-Fi. */
@interface HueviaConnectionProtection : NSObject <FlutterStreamHandler>
- (instancetype)initWithMessenger:(NSObject<FlutterBinaryMessenger> *)messenger cancel:(dispatch_block_t)cancel;
@end
