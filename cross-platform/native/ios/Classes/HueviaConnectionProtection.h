#import <Flutter/Flutter.h>
#import <UIKit/UIKit.h>

/** A finite UIKit finishing lease. It never claims unrestricted background USB/Wi-Fi. */
@interface HueviaConnectionProtection : NSObject <FlutterStreamHandler>
@property(nonatomic,readonly) BOOL maintenanceAllowed;
@property(nonatomic,copy) void (^maintenanceChanged)(BOOL allowed);
- (instancetype)initWithMessenger:(NSObject<FlutterBinaryMessenger> *)messenger cancel:(dispatch_block_t)cancel;
@end
