#import "HueviaOriginalFiles.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <CommonCrypto/CommonDigest.h>
#import "java/io/IOException.h"
#import "java/lang/Throwable.h"
#include <fcntl.h>
#include <unistd.h>

namespace {
void filesFail(NSString *message){@throw [[JavaIoIOException alloc] initWithNSString:message];}
void filesCheck(HueviaTask *task){if(task.cancelled)filesFail(@"原文件保存已停止；未完成文件保留以供核对。");}
NSString *filesJson(NSDictionary *p){return [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:p options:0 error:nil] encoding:NSUTF8StringEncoding];}
BOOL filesHex(NSString *s,NSUInteger count){return [s isKindOfClass:NSString.class]&&s.length==count&&[s rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"].invertedSet].location==NSNotFound;}
NSString *filesHash(NSData *data){uint8_t sum[CC_SHA256_DIGEST_LENGTH];CC_SHA256(data.bytes,(CC_LONG)data.length,sum);NSMutableString *out=[NSMutableString string];for(uint8_t value:sum)[out appendFormat:@"%02x",value];return out;}
NSString *filesDirectory(NSString *parent,NSString *name){NSString *path=[parent stringByAppendingPathComponent:name];NSDictionary *a=[NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];if(a&&![a[NSFileType] isEqual:NSFileTypeDirectory])filesFail(@"文件保存记录目录无效。");if(![path.stringByResolvingSymlinksInPath isEqual:path])filesFail(@"文件保存记录不能是链接。");if(!a&&![NSFileManager.defaultManager createDirectoryAtPath:path withIntermediateDirectories:NO attributes:nil error:nil])filesFail(@"无法保存文件发布记录。");return path;}
NSDictionary *filesRead(NSString *path){NSDictionary *a=[NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];if(!a)return nil;if(![a[NSFileType] isEqual:NSFileTypeRegular]||[a[NSFileSize] unsignedLongLongValue]>16384)filesFail(@"文件保存记录无效。");NSData *data=[NSData dataWithContentsOfFile:path];if(!data)filesFail(@"文件保存记录暂不可读。");NSDictionary *p=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];if(![p isKindOfClass:NSDictionary.class]||![p[@"schema"] isEqual:@1])filesFail(@"文件保存记录不可读取。");return p;}
void filesWrite(NSString *path,NSDictionary *p){NSData *data=[NSJSONSerialization dataWithJSONObject:p options:0 error:nil];if(!data||![data writeToFile:path options:NSDataWritingAtomic error:nil])filesFail(@"无法写入文件保存记录。");}
NSString *filesName(NSString *input,NSString *operation,BOOL raw){if(![input isKindOfClass:NSString.class])input=@"original";NSMutableCharacterSet *bad=[NSCharacterSet.controlCharacterSet mutableCopy];[bad addCharactersInString:@"/\\"];NSString *name=[[[input componentsSeparatedByCharactersInSet:bad] componentsJoinedByString:@"_"] stringByDeletingPathExtension];while(name.length>90)name=[name substringToIndex:[name rangeOfComposedCharacterSequenceAtIndex:name.length-1].location];if(!name.length)name=@"original";return [NSString stringWithFormat:@"%@__Huevia_%@.%@",name,operation,raw?@"NEF":@"jpg"];}
BOOL filesPrefix(NSURL *destination,NSString *source,unsigned long long expected,HueviaTask *task){NSInputStream *a=[NSInputStream inputStreamWithURL:destination],*b=[NSInputStream inputStreamWithFileAtPath:source];[a open];[b open];BOOL equal=YES;unsigned long long total=0;uint8_t left[65536],right[65536];@try{NSInteger count;while((count=[a read:left maxLength:sizeof(left)])>0){filesCheck(task);total+=count;if(total>expected){equal=NO;break;}NSInteger offset=0;while(offset<count){NSInteger n=[b read:right+offset maxLength:count-offset];if(n<=0){equal=NO;break;}offset+=n;}if(!equal||memcmp(left,right,count)){equal=NO;break;}}if(count<0)filesFail(@"未完成文件暂不可读，请检查 Files 访问权限。");}@finally{[a close];[b close];}return equal;}
void filesVerify(NSURL *url,NSString *sha,unsigned long long expected,HueviaTask *task){NSInputStream *input=[NSInputStream inputStreamWithURL:url];[input open];CC_SHA256_CTX context;CC_SHA256_Init(&context);unsigned long long total=0;uint8_t buffer[65536];@try{NSInteger count;while((count=[input read:buffer maxLength:sizeof(buffer)])>0){filesCheck(task);total+=count;if(total>expected)filesFail(@"目标文件已变化，未覆盖或重复保存。");CC_SHA256_Update(&context,buffer,(CC_LONG)count);}if(count<0)filesFail(@"保存后的文件暂不可读，请稍后核对。");}@finally{[input close];}uint8_t sum[CC_SHA256_DIGEST_LENGTH];CC_SHA256_Final(sum,&context);NSMutableString *actual=[NSMutableString string];for(uint8_t v:sum)[actual appendFormat:@"%02x",v];if(total!=expected||![actual isEqual:sha])filesFail(@"文件长度或 SHA-256 未通过读回核对；未重复保存。");}
}

@interface HueviaOriginalFiles ()
@property(nonatomic,copy) NSString *root;
@property(nonatomic,strong) CcHueviaSharedSharedRuntime *runtime;
@property(nonatomic,copy) FlutterResult pickerReply;
@property(nonatomic,copy) NSString *pickerOwner;
@property(nonatomic,strong) NSMutableDictionary<NSString *,HueviaTask *> *tasks;
@property(nonatomic,strong) dispatch_queue_t worker;
- (void)presentFolderPicker;
- (void)failPicker:(NSString *)message;
@end

@implementation HueviaOriginalFiles
- (instancetype)initWithRoot:(NSString *)root runtime:(CcHueviaSharedSharedRuntime *)runtime {self=[super init];if(self){_root=root.stringByResolvingSymlinksInPath;_runtime=runtime;_tasks=[NSMutableDictionary dictionary];_worker=dispatch_queue_create("cc.huevia.original-files",DISPATCH_QUEUE_SERIAL);}return self;}
- (NSString *)record:(NSString *)kind owner:(NSString *)owner identifier:(NSString *)identifier {if(!filesHex(identifier,32))filesFail(@"文件保存标识无效。");NSString *base=filesDirectory(self.root,kind),*folder=filesDirectory(base,filesHash([owner dataUsingEncoding:NSUTF8StringEncoding]));return [folder stringByAppendingPathComponent:[identifier stringByAppendingString:@".json"]];}
- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
  @try{
    NSDictionary *p=[call.arguments isKindOfClass:NSDictionary.class]?call.arguments:@{};
    if([call.method isEqual:@"chooseTarget"]){
      if(self.pickerReply)filesFail(@"请先完成当前文件夹选择。");NSString *owner=p[@"owner"]?:@"";if(![owner isKindOfClass:NSString.class]||owner.length>64)filesFail(@"文件夹授权账号无效。");
      self.pickerReply=result;self.pickerOwner=owner;
      dispatch_async(self.worker,^{@try{[self.runtime guardOwnerWithNSString:owner];dispatch_async(dispatch_get_main_queue(),^{@try{[self presentFolderPicker];}@catch(JavaLangThrowable *failure){[self failPicker:[failure getMessage]];}@catch(NSException *failure){[self failPicker:@"当前无法打开文件夹选择器。"];}});}@catch(JavaLangThrowable *failure){dispatch_async(dispatch_get_main_queue(),^{[self failPicker:[failure getMessage]];});}});return;
    }
    if([call.method isEqual:@"cancel"]){if(filesHex(p[@"operationId"],32)){@synchronized(self.tasks){[self.tasks[p[@"operationId"]] cancelIfActive];}}result(nil);return;}
    if(![call.method isEqual:@"publishOriginal"]){result(FlutterMethodNotImplemented);return;}
    NSString *operation=p[@"operationId"];if(!filesHex(operation,32))filesFail(@"文件保存任务标识无效。");HueviaTask *task=[[HueviaTask alloc] init];
    @synchronized(self.tasks){if(self.tasks[operation])filesFail(@"此原文件保存任务正在进行。");self.tasks[operation]=task;}
    dispatch_async(self.worker,^{@try{NSDictionary *value=[self publish:p task:task];[task finish];dispatch_async(dispatch_get_main_queue(),^{result(filesJson(value));});}@catch(JavaLangThrowable *failure){NSString *message=[failure getMessage]?:@"文件保存未完成。";[task finish];dispatch_async(dispatch_get_main_queue(),^{result([FlutterError errorWithCode:@"FILES_PUBLICATION" message:message details:nil]);});}@catch(NSException *failure){[task finish];dispatch_async(dispatch_get_main_queue(),^{result([FlutterError errorWithCode:@"FILES_PUBLICATION" message:@"文件保存未完成，请先核对 Files。" details:nil]);});}@finally{[task finish];@synchronized(self.tasks){if(self.tasks[operation]==task)[self.tasks removeObjectForKey:operation];}}});
  }@catch(JavaLangThrowable *failure){result([FlutterError errorWithCode:@"FILES_PUBLICATION" message:[failure getMessage] details:nil]);}@catch(NSException *failure){result([FlutterError errorWithCode:@"FILES_PUBLICATION" message:@"无法处理文件保存请求。" details:nil]);}
}
- (void)presentFolderPicker {
  if(!self.pickerReply)return;UIViewController *presenter=nil;for(UIScene *scene in UIApplication.sharedApplication.connectedScenes)if([scene isKindOfClass:UIWindowScene.class]&&scene.activationState==UISceneActivationStateForegroundActive){for(UIWindow *window in ((UIWindowScene *)scene).windows)if(window.isKeyWindow){presenter=window.rootViewController;break;}if(presenter)break;}
  while(presenter.presentedViewController)presenter=presenter.presentedViewController;if(!presenter)filesFail(@"当前无法打开文件夹选择器。");
  UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeFolder] asCopy:NO];picker.allowsMultipleSelection=NO;picker.delegate=self;[presenter presentViewController:picker animated:YES completion:nil];
}
- (void)failPicker:(NSString *)message {FlutterResult reply=self.pickerReply;self.pickerReply=nil;self.pickerOwner=nil;if(reply)reply([FlutterError errorWithCode:@"FILES_TARGET" message:message?:@"文件夹授权未完成。" details:nil]);}
- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {FlutterResult reply=self.pickerReply;self.pickerReply=nil;self.pickerOwner=nil;if(reply)reply(nil);}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
  FlutterResult reply=self.pickerReply;NSString *owner=self.pickerOwner;self.pickerReply=nil;self.pickerOwner=nil;if(!reply)return;
  NSURL *folder=urls.firstObject;dispatch_async(self.worker,^{BOOL scoped=[folder startAccessingSecurityScopedResource];@try{
    [self.runtime guardOwnerWithNSString:owner];NSNumber *directory=nil;if(!folder||![folder getResourceValue:&directory forKey:NSURLIsDirectoryKey error:nil]||!directory.boolValue)filesFail(@"请选择 Files 中的文件夹。");
    NSData *bookmark=[folder bookmarkDataWithOptions:NSURLBookmarkCreationMinimalBookmark includingResourceValuesForKeys:nil relativeToURL:nil error:nil];if(!bookmark.length)filesFail(@"此文件夹不支持持久授权，请重新选择。");
    NSString *identifier=[NSUUID.UUID.UUIDString.lowercaseString stringByReplacingOccurrencesOfString:@"-" withString:@""],*name=folder.lastPathComponent?:@"Files 文件夹";
    filesWrite([self record:@"file-targets" owner:owner identifier:identifier],@{@"schema":@1,@"owner":owner,@"id":identifier,@"name":name,@"bookmark":[bookmark base64EncodedStringWithOptions:0]});NSString *json=filesJson(@{@"id":identifier,@"name":name});dispatch_async(dispatch_get_main_queue(),^{reply(json);});
  }@catch(JavaLangThrowable *failure){dispatch_async(dispatch_get_main_queue(),^{reply([FlutterError errorWithCode:@"FILES_TARGET" message:[failure getMessage] details:nil]);});}@catch(NSException *failure){dispatch_async(dispatch_get_main_queue(),^{reply([FlutterError errorWithCode:@"FILES_TARGET" message:@"文件夹授权未完成，请重新选择。" details:nil]);});}@finally{if(scoped)[folder stopAccessingSecurityScopedResource];}});
}
- (NSDictionary *)publish:(NSDictionary *)p task:(HueviaTask *)task {
  @synchronized(self){
    NSString *owner=p[@"owner"],*operation=p[@"operationId"],*target=p[@"targetId"];if(![owner isKindOfClass:NSString.class]||owner.length>64||!filesHex(operation,32)||!filesHex(target,32))filesFail(@"文件发布身份或目标无效。");[self.runtime guardOwnerWithNSString:owner];filesCheck(task);
    NSDictionary *chosen=filesRead([self record:@"file-targets" owner:owner identifier:target]);if(![chosen[@"owner"] isEqual:owner]||![chosen[@"id"] isEqual:target])filesFail(@"文件夹授权记录不可用，请重新选择目标。");
    NSData *bookmark=[[NSData alloc] initWithBase64EncodedString:chosen[@"bookmark"] options:0];BOOL stale=NO;NSURL *folder=[NSURL URLByResolvingBookmarkData:bookmark options:NSURLBookmarkResolutionWithoutUI relativeToURL:nil bookmarkDataIsStale:&stale error:nil];
    if(!folder||stale)filesFail(@"文件夹授权已失效，请重新选择；未重复保存。");BOOL scoped=[folder startAccessingSecurityScopedResource];
    if(!scoped&&![folder.path hasPrefix:[NSHomeDirectory() stringByAppendingString:@"/"]])filesFail(@"Files 文件夹不可访问，请重新授权。");
    @try{
      NSString *prepared=[self.runtime prepareOriginalPublicationWithNSString:filesJson(p) withJavaUtilFunctionBooleanSupplier:task];NSDictionary *source=[NSJSONSerialization JSONObjectWithData:[prepared dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
      NSString *path=source[@"path"],*sha=source[@"sha256"],*name=filesName(p[@"filename"],operation,[source[@"format"] isEqual:@"NEF"]);unsigned long long bytes=[source[@"bytes"] unsignedLongLongValue];
      if(!filesHex(sha,64)||bytes<4||bytes>512ULL*1024*1024)filesFail(@"原文件快照无效。");
      NSString *journal=[self record:@"file-publications" owner:owner identifier:operation];NSMutableDictionary *record=[filesRead(journal) mutableCopy];BOOL existing=record!=nil;
      if(!record){record=[@{@"schema":@1,@"owner":owner,@"targetId":target,@"operationId":operation,@"sha256":sha,@"bytes":@(bytes),@"name":name,@"state":@"preparing",@"ownsFile":@NO} mutableCopy];filesWrite(journal,record);}
      if(![record[@"owner"] isEqual:owner]||![record[@"targetId"] isEqual:target]||![record[@"sha256"] isEqual:sha]||[record[@"bytes"] unsignedLongLongValue]!=bytes||![record[@"name"] isEqual:name])filesFail(@"此文件保存任务已绑定其他内容或目标，未覆盖。");
      NSURL *destination=[folder URLByAppendingPathComponent:name isDirectory:NO];
      if(![destination.URLByResolvingSymlinksInPath.URLByDeletingLastPathComponent.path isEqual:folder.URLByResolvingSymlinksInPath.path])filesFail(@"目标文件路径越过授权文件夹，已停止。");
      NSFileCoordinator *coordinator=[[NSFileCoordinator alloc] initWithFilePresenter:nil];__block NSError *coordination=nil;__block id pendingFailure=nil;
      [coordinator coordinateWritingItemAtURL:destination options:0 error:&coordination byAccessor:^(NSURL *writing){@try{
        NSDictionary *attributes=[NSFileManager.defaultManager attributesOfItemAtPath:writing.path error:nil];
        if(attributes&&![attributes[NSFileType] isEqual:NSFileTypeRegular])filesFail(@"目标文件不是普通文件，未覆盖。");
        if([record[@"state"] isEqual:@"complete"]){if(!attributes)filesFail(@"此前保存的文件已不可访问，请重新发起保存。");filesVerify(writing,sha,bytes,task);return;}
        if(attributes&&![record[@"ownsFile"] boolValue]){filesVerify(writing,sha,bytes,task);record[@"state"]=@"complete";filesWrite(journal,record);return;}
        if(attributes&&!filesPrefix(writing,path,bytes,task))filesFail(@"未完成文件已被修改，未覆盖；请先在 Files 核对。");
        filesCheck(task);int fd=open(writing.fileSystemRepresentation,O_WRONLY|O_NOFOLLOW|(attributes?O_TRUNC:(O_CREAT|O_EXCL)),0600);if(fd<0)filesFail(@"Files 无法创建或打开原文件，未覆盖其他文件。");
        NSInputStream *input=[NSInputStream inputStreamWithFileAtPath:path];[input open];
        @try{record[@"ownsFile"]=@YES;record[@"state"]=@"pending";filesWrite(journal,record);uint8_t buffer[65536];unsigned long long total=0;NSInteger count;
          while((count=[input read:buffer maxLength:sizeof(buffer)])>0){filesCheck(task);total+=count;if(total>bytes)filesFail(@"原文件快照已变化。");NSInteger at=0;while(at<count){ssize_t written=write(fd,buffer+at,count-at);if(written<1)filesFail(@"Files 原文件写入中断，未确认完成。");at+=written;}}
          if(count<0||total!=bytes||fsync(fd)!=0)filesFail(@"原文件尚未完整保存，请核对目标文件夹。");
        }@finally{[input close];close(fd);}
        filesVerify(writing,sha,bytes,task);[self.runtime guardOwnerWithNSString:owner];record[@"state"]=@"complete";filesWrite(journal,record);
      }@catch(id failure){pendingFailure=failure;}}];
      if(pendingFailure)@throw pendingFailure;if(coordination)filesFail(@"Files 文件提供者未确认写入，请稍后核对目标文件夹。");
      [self.runtime releaseOriginalPublicationWithNSString:filesJson(@{@"owner":owner,@"operationId":operation,@"sha256":sha,@"bytes":@(bytes)})];
      return @{@"published":@YES,@"owner":owner,@"operationId":operation,@"targetKind":@"folder",@"uri":destination.absoluteString,@"targetId":target,@"sha256":sha,@"bytes":@(bytes),@"verified":@YES,@"existing":@(existing)};
    }@finally{if(scoped)[folder stopAccessingSecurityScopedResource];}
  }
}
@end
