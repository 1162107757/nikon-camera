#import <Flutter/Flutter.h>

@interface HueviaCameraLocation : NSObject
- (instancetype)initWithMessenger:(NSObject<FlutterBinaryMessenger> *)messenger;
- (void)detach;
@end
