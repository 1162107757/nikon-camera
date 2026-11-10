#import "java/nio/file/FileSystems.h"
#import "java/nio/file/FileSystem.h"
#import "java/io/IOException.h"
#import "java/nio/file/attribute/BasicFileAttributes.h"
#import "java/nio/file/attribute/BasicFileAttributeView.h"
#import "java/nio/file/LinkOption.h"
#import "java/time/Instant.h"
#import "java/net/Socket.h"
#import "java/net/URL.h"
#import "javax/net/ssl/HttpsURLConnection.h"

/** Retain JRE modules reached through reflection by filesystem/network factories. */
static inline void HueviaLinkCoreModules(void) {
    // J2ObjC 3.1 UnixFileSystem.provider is @Weak. FileSystems only keeps
    // the filesystem, so the provider otherwise dies when a worker's first
    // autorelease pool drains. Every subsequent NIO request then sees nil.
    static id retainedFileSystemProvider;
    static dispatch_once_t fileSystemOnce;
    dispatch_once(&fileSystemOnce,^{retainedFileSystemProvider=[[JavaNioFileFileSystems getDefault] provider];});
    if(!retainedFileSystemProvider)@throw [[JavaIoIOException alloc] initWithNSString:@"文件系统提供器不可用。"];
    // NIO attribute interfaces are otherwise reached only from the static JRE.
    JavaNioFileAttributeBasicFileAttributes_class_();
    JavaNioFileAttributeBasicFileAttributeView_class_();
    JavaNioFileLinkOption_class_();
    JavaTimeInstant_class_();
    JavaNetSocket_class_();
    JavaNetURL_class_();
    JavaxNetSslHttpsURLConnection_class_();
}
