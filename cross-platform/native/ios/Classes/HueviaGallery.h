#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <Flutter/Flutter.h>
#import "HueviaTask.h"
@class CcHueviaSharedSharedRuntime;

@interface HueviaGallery : NSObject
@property(atomic,copy) void (^changed)(void);
- (instancetype)initWithRoot:(NSString *)root;
- (NSDictionary *)access;
- (void)requestPermissionFrom:(UIViewController *)presenter reply:(FlutterResult)reply;
- (void)configurePublicationWithRuntime:(CcHueviaSharedSharedRuntime *)runtime;
- (void)requestSavePermission:(FlutterResult)reply;
- (NSDictionary *)request:(NSString *)operation payload:(NSString *)payload task:(HueviaTask *)task;
@end
