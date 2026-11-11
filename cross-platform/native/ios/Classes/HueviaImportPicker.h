#import <Flutter/Flutter.h>
#import <UIKit/UIKit.h>
#import <Photos/Photos.h>
#import <PhotosUI/PhotosUI.h>
@class CcHueviaSharedSharedRuntime;

@interface HueviaImportPicker : NSObject <UIDocumentPickerDelegate, PHPickerViewControllerDelegate>
- (instancetype)initWithQueue:(dispatch_queue_t)queue;
- (void)pickPreset:(BOOL)preset root:(NSString *)root presenter:(UIViewController *)presenter reply:(FlutterResult)reply;
- (void)pickSubmission:(NSString *)kind owner:(NSString *)owner root:(NSString *)root presenter:(UIViewController *)presenter reply:(FlutterResult)reply;
- (void)pickAvatarForOwner:(NSString *)owner updatedAt:(NSString *)updatedAt runtime:(CcHueviaSharedSharedRuntime *)runtime root:(NSString *)root presenter:(UIViewController *)presenter reply:(FlutterResult)reply;
@end
