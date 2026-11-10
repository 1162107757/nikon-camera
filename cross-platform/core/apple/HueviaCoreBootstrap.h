#import "java/nio/file/FileSystems.h"
#import "java/nio/file/attribute/BasicFileAttributes.h"
#import "java/nio/file/attribute/BasicFileAttributeView.h"
#import "java/nio/file/LinkOption.h"
#import "java/time/Instant.h"
#import "java/net/Socket.h"
#import "java/net/URL.h"
#import "javax/net/ssl/HttpsURLConnection.h"

/** Retain JRE modules reached through reflection by filesystem/network factories. */
static inline void HueviaLinkCoreModules(void) {
    [JavaNioFileFileSystems getDefault];
    // NIO attribute interfaces are otherwise reached only from the static JRE.
    JavaNioFileAttributeBasicFileAttributes_class_();
    JavaNioFileAttributeBasicFileAttributeView_class_();
    JavaNioFileLinkOption_class_();
    JavaTimeInstant_class_();
    JavaNetSocket_class_();
    JavaNetURL_class_();
    JavaxNetSslHttpsURLConnection_class_();
}
