#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <Flutter/Flutter.h>
#import "HueviaTask.h"

@interface HueviaGallery : NSObject
@property(atomic,copy) void (^changed)(void);
- (instancetype)initWithRoot:(NSString *)root;
- (NSDictionary *)access;
- (void)requestPermissionFrom:(UIViewController *)presenter reply:(FlutterResult)reply;
- (NSDictionary *)request:(NSString *)operation payload:(NSString *)payload task:(HueviaTask *)task;
@end
