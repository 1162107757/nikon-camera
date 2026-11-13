#import "HueviaLegacyFiles.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface HueviaLegacyFiles () <UIDocumentPickerDelegate>
@property(nonatomic,weak) UIViewController *presenter;
@property(nonatomic,copy) FlutterResult pending;
@property(nonatomic,assign) BOOL directory;
@property(nonatomic,strong) dispatch_queue_t queue;
@end

@implementation HueviaLegacyFiles
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
  HueviaLegacyFiles *host=[[self alloc] init];host.presenter=registrar.viewController;
  host.queue=dispatch_queue_create("cc.huevia.legacy-files",DISPATCH_QUEUE_SERIAL);
  FlutterMethodChannel *channel=[FlutterMethodChannel methodChannelWithName:@"cc.huevia/legacy-files" binaryMessenger:registrar.messenger];
  [registrar addMethodCallDelegate:host channel:channel];
}
- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)reply {
  if(![call.method isEqualToString:@"pick"]){reply(FlutterMethodNotImplemented);return;}
  if(self.pending){reply([FlutterError errorWithCode:@"BUSY" message:@"请先完成当前文件选择。" details:nil]);return;}
  NSDictionary *args=[call.arguments isKindOfClass:NSDictionary.class]?call.arguments:@{};
  self.directory=[args[@"iosPresets"] isEqual:@YES];self.pending=reply;
  UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[self.directory?UTTypeFolder:UTTypeZIP] asCopy:NO];
  picker.delegate=self;picker.allowsMultipleSelection=NO;
  [self.presenter presentViewController:picker animated:YES completion:nil];
}
- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {FlutterResult reply=self.pending;self.pending=nil;if(reply)reply(@{@"cancelled":@YES});}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
  NSURL *selected=urls.firstObject;BOOL directory=self.directory;FlutterResult reply=self.pending;if(!selected||!reply)return;
  dispatch_async(self.queue,^{@autoreleasepool{
    BOOL access=[selected startAccessingSecurityScopedResource];__block NSError *failure=nil;
    NSURL *base=[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL *incoming=[base URLByAppendingPathComponent:@"Huevia/legacy-incoming" isDirectory:YES];
    NSURL *target=[incoming URLByAppendingPathComponent:[NSUUID.UUID.UUIDString.lowercaseString stringByAppendingString:directory?@"":@".zip"] isDirectory:directory];
    [NSFileManager.defaultManager createDirectoryAtURL:incoming withIntermediateDirectories:YES attributes:@{NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} error:&failure];
    if(!failure){
      NSFileCoordinator *coordinator=[[NSFileCoordinator alloc] initWithFilePresenter:nil];
      [coordinator coordinateReadingItemAtURL:selected options:NSFileCoordinatorReadingWithoutChanges error:&failure byAccessor:^(NSURL *url){
        NSNumber *link=nil;[url getResourceValue:&link forKey:NSURLIsSymbolicLinkKey error:&failure];if(link.boolValue||failure){failure=[NSError errorWithDomain:@"HueviaLegacy" code:1 userInfo:nil];return;}
        if(directory){
          [NSFileManager.defaultManager createDirectoryAtURL:target withIntermediateDirectories:YES attributes:nil error:&failure];
          NSArray<NSURL *> *files=[NSFileManager.defaultManager contentsOfDirectoryAtURL:url includingPropertiesForKeys:@[NSURLFileSizeKey,NSURLIsSymbolicLinkKey] options:NSDirectoryEnumerationSkipsHiddenFiles error:&failure];
          if(files.count>20000){failure=[NSError errorWithDomain:@"HueviaLegacy" code:2 userInfo:nil];return;}
          for(NSURL *file in files){
            if(![@[@"ncp",@"np3"] containsObject:file.pathExtension.lowercaseString])continue;
            NSNumber *size=nil,*symbolic=nil;[file getResourceValue:&size forKey:NSURLFileSizeKey error:&failure];[file getResourceValue:&symbolic forKey:NSURLIsSymbolicLinkKey error:&failure];
            if(failure||symbolic.boolValue||size.unsignedLongLongValue<1||size.unsignedLongLongValue>1024*1024){failure=[NSError errorWithDomain:@"HueviaLegacy" code:3 userInfo:nil];break;}
            if(![NSFileManager.defaultManager copyItemAtURL:file toURL:[target URLByAppendingPathComponent:file.lastPathComponent] error:&failure])break;
          }
        }else{
          NSNumber *size=nil;[url getResourceValue:&size forKey:NSURLFileSizeKey error:&failure];
          if(failure||size.unsignedLongLongValue<1||size.unsignedLongLongValue>16ULL*1024*1024*1024){failure=[NSError errorWithDomain:@"HueviaLegacy" code:4 userInfo:nil];return;}
          [NSFileManager.defaultManager copyItemAtURL:url toURL:target error:&failure];
        }
      }];
    }
    if(access)[selected stopAccessingSecurityScopedResource];
    if(failure)[NSFileManager.defaultManager removeItemAtURL:target error:nil];
    dispatch_async(dispatch_get_main_queue(),^{self.pending=nil;reply(failure?[FlutterError errorWithCode:@"LEGACY_IMPORT_FAILED" message:@"无法读取旧版资料，请核对文件和可用空间后重试。" details:nil]:@{@"path":target.path,@"iosPresets":@(directory)});});
  }});
}
@end
