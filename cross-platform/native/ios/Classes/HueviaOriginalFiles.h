#import <Flutter/Flutter.h>
#import <UIKit/UIKit.h>
#import "cc/huevia/shared/SharedRuntime.h"
#import "HueviaTask.h"

/** File-provider folders are private bookmark IDs, never caller supplied filesystem paths. */
@interface HueviaOriginalFiles : NSObject <UIDocumentPickerDelegate>
- (instancetype)initWithRoot:(NSString *)root runtime:(CcHueviaSharedSharedRuntime *)runtime;
- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result;
- (NSDictionary *)publish:(NSDictionary *)payload task:(HueviaTask *)task;
@end
