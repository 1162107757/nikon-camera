#import <Flutter/Flutter.h>
#import <UIKit/UIKit.h>

@interface HueviaImportPicker : NSObject <UIDocumentPickerDelegate>
- (instancetype)initWithQueue:(dispatch_queue_t)queue;
- (void)pickPreset:(BOOL)preset root:(NSString *)root presenter:(UIViewController *)presenter reply:(FlutterResult)reply;
@end
