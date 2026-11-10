#import "HueviaKeychain.h"
#import <Security/Security.h>
#import "IOSPrimitiveArray.h"
#import "java/io/IOException.h"

@implementation HueviaKeychain
- (NSMutableDictionary *)query {
  return [@{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
            (__bridge id)kSecAttrService:@"cc.huevia.shared.session.v1",
            (__bridge id)kSecAttrAccount:@"current",
            (__bridge id)kSecAttrSynchronizable:@NO} mutableCopy];
}
- (IOSByteArray *)read {
  NSMutableDictionary *query=[self query];
  query[(__bridge id)kSecReturnData]=@YES;
  query[(__bridge id)kSecMatchLimit]=(__bridge id)kSecMatchLimitOne;
  CFTypeRef value=NULL;
  OSStatus status=SecItemCopyMatching((__bridge CFDictionaryRef)query,&value);
  if(status==errSecItemNotFound)return nil;
  if(status!=errSecSuccess)@throw [[JavaIoIOException alloc] initWithNSString:@"无法读取本机登录资料，请解锁设备后重试。"];
  NSData *data=CFBridgingRelease(value);
  if(data.length>65536)@throw [[JavaIoIOException alloc] initWithNSString:@"本机登录资料超出范围。"];
  return [IOSByteArray arrayWithBytes:data.bytes count:(jint)data.length];
}
- (void)writeWithByteArray:(IOSByteArray *)value {
  if(!value||value->size_>65536)@throw [[JavaIoIOException alloc] initWithNSString:@"登录资料大小无效。"];
  NSData *data=[NSData dataWithBytes:value->buffer_ length:value->size_];
  NSDictionary *attributes=@{(__bridge id)kSecValueData:data,
    (__bridge id)kSecAttrAccessible:(__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly};
  NSMutableDictionary *query=[self query];
  OSStatus status=SecItemUpdate((__bridge CFDictionaryRef)query,(__bridge CFDictionaryRef)attributes);
  if(status==errSecItemNotFound){[query addEntriesFromDictionary:attributes];status=SecItemAdd((__bridge CFDictionaryRef)query,NULL);}
  if(status!=errSecSuccess)@throw [[JavaIoIOException alloc] initWithNSString:@"无法安全保存登录资料，请解锁设备后重试。"];
}
- (void)clear {
  OSStatus status=SecItemDelete((__bridge CFDictionaryRef)[self query]);
  if(status!=errSecSuccess&&status!=errSecItemNotFound)@throw [[JavaIoIOException alloc] initWithNSString:@"本机登录资料尚未清除，请重试退出登录。"];
}
@end
