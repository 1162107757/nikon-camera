#import "HueviaGalleryPreview.h"
#import <AVKit/AVKit.h>
#import <PhotosUI/PhotosUI.h>
#import "java/io/IOException.h"
#import "java/io/InterruptedIOException.h"

@interface HueviaGalleryVideoController : AVPlayerViewController
@end
@implementation HueviaGalleryVideoController
- (void)viewDidDisappear:(BOOL)animated {[super viewDidDisappear:animated];[self.player pause];}
@end

@interface HueviaGalleryLiveController : UIViewController
@property(nonatomic,strong) PHLivePhoto *photo;
@end
@implementation HueviaGalleryLiveController
- (void)viewDidLoad {
  [super viewDidLoad];self.view.backgroundColor=UIColor.blackColor;
  self.title=@"实况照片";
  PHLivePhotoView *live=[[PHLivePhotoView alloc] initWithFrame:CGRectZero];
  live.translatesAutoresizingMaskIntoConstraints=NO;live.contentMode=UIViewContentModeScaleAspectFit;live.livePhoto=self.photo;
  [self.view addSubview:live];
  [NSLayoutConstraint activateConstraints:@[[live.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor],[live.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor],[live.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],[live.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor]]];
  self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(close)];
  [live startPlaybackWithStyle:PHLivePhotoViewPlaybackStyleHint];
}
- (void)close {[self.navigationController dismissViewControllerAnimated:YES completion:nil];}
@end

namespace {
void failPreview(NSString *message){@throw [[JavaIoIOException alloc] initWithNSString:message];}
BOOL readable(PHAsset *asset){PHAuthorizationStatus s=[PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelReadWrite];return (s==PHAuthorizationStatusAuthorized||s==PHAuthorizationStatusLimited)&&[PHAsset fetchAssetsWithLocalIdentifiers:@[asset.localIdentifier] options:nil].count>0;}
BOOL waitPreview(dispatch_semaphore_t done,HueviaTask *task){
  NSTimeInterval limit=NSProcessInfo.processInfo.systemUptime+45;
  while(dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC))!=0){if(task.cancelled||NSProcessInfo.processInfo.systemUptime>=limit)return NO;}
  return !task.cancelled;
}
UIViewController *presenter(){
  for(UIScene *scene in UIApplication.sharedApplication.connectedScenes){
    if(![scene isKindOfClass:UIWindowScene.class]||scene.activationState!=UISceneActivationStateForegroundActive)continue;
    for(UIWindow *window in ((UIWindowScene *)scene).windows)if(window.isKeyWindow){UIViewController *top=window.rootViewController;while(top.presentedViewController)top=top.presentedViewController;return top;}
  }
  return nil;
}
}

NSDictionary *HueviaPreviewGalleryAsset(PHAsset *asset,HueviaTask *task){
  BOOL video=asset.mediaType==PHAssetMediaTypeVideo,live=(asset.mediaSubtypes&PHAssetMediaSubtypePhotoLive)!=0;
  if(!video&&!live)failPreview(@"请选择实况照片或视频。");
  dispatch_semaphore_t done=dispatch_semaphore_create(0);NSLock *lock=[NSLock new];
  __block id media=nil;__block BOOL accepting=YES;
  PHImageRequestID request;
  if(video){
    PHVideoRequestOptions *options=[PHVideoRequestOptions new];options.networkAccessAllowed=YES;
    request=[PHImageManager.defaultManager requestPlayerItemForVideo:asset options:options resultHandler:^(AVPlayerItem *item,NSDictionary *info){[lock lock];if(accepting)media=item;[lock unlock];dispatch_semaphore_signal(done);}];
  }else{
    PHLivePhotoRequestOptions *options=[PHLivePhotoRequestOptions new];options.networkAccessAllowed=YES;options.deliveryMode=PHImageRequestOptionsDeliveryModeHighQualityFormat;
    request=[PHImageManager.defaultManager requestLivePhotoForAsset:asset targetSize:CGSizeMake(1600,1600) contentMode:PHImageContentModeAspectFit options:options resultHandler:^(PHLivePhoto *photo,NSDictionary *info){if([info[PHImageResultIsDegradedKey] boolValue])return;[lock lock];if(accepting)media=photo;[lock unlock];dispatch_semaphore_signal(done);}];
  }
  BOOL finished=waitPreview(done,task);[lock lock];accepting=NO;id received=media;[lock unlock];
  if(!finished){[PHImageManager.defaultManager cancelImageRequest:request];if(task.cancelled)@throw [[JavaIoInterruptedIOException alloc] initWithNSString:@"预览已取消。"];failPreview(@"预览加载超时，请检查网络后重试。");}
  if(!received||!readable(asset))failPreview(@"此项目暂不可预览，请检查相册权限或网络后重试。");
  __block BOOL opened=NO;
  dispatch_sync(dispatch_get_main_queue(),^{
    UIViewController *host=presenter();if(!host||host.isBeingDismissed||task.cancelled)return;
    if(video){HueviaGalleryVideoController *controller=[HueviaGalleryVideoController new];controller.player=[AVPlayer playerWithPlayerItem:received];[host presentViewController:controller animated:YES completion:^{[controller.player play];}];}
    else{HueviaGalleryLiveController *controller=[HueviaGalleryLiveController new];controller.photo=received;[host presentViewController:[[UINavigationController alloc] initWithRootViewController:controller] animated:YES completion:nil];}
    opened=YES;
  });
  if(!opened)failPreview(@"请返回相册后重新打开预览。");
  return @{@"opened":@YES};
}
