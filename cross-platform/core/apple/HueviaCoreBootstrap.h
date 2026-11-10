#import "java/nio/file/FileSystems.h"
#import "java/time/Instant.h"
#import "java/net/Socket.h"
#import "java/net/URL.h"
#import "javax/net/ssl/HttpsURLConnection.h"

/** Retain JRE modules reached through reflection by filesystem/network factories. */
static inline void HueviaLinkCoreModules(void) {
    JavaNioFileFileSystems_class_();
    JavaTimeInstant_class_();
    JavaNetSocket_class_();
    JavaNetURL_class_();
    JavaxNetSslHttpsURLConnection_class_();
}
