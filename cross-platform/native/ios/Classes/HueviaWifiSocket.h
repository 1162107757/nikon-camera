#import <Foundation/Foundation.h>
#import "java/net/Socket.h"
#import "cc/huevia/album/PtpIpClient.h"
#import "cc/huevia/shared/SharedCamera.h"

/** Both PTP/IP channels use the camera Wi-Fi, matching the original iOS app. */
@interface HueviaSockets : NSObject <CcHueviaSharedSharedCamera_Connectors,CcHueviaAlbumPtpIpClient_SocketConnector>
@end

@interface HueviaWifiSocket : JavaNetSocket
- (instancetype)initWithHost:(NSString *)host port:(int32_t)port timeout:(int32_t)timeout wifiOnly:(BOOL)wifiOnly;
@end
