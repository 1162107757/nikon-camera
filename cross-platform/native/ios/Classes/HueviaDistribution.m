#import "HueviaDistribution.h"
#import <zlib.h>
#import <mach-o/loader.h>
#import <mach-o/fat.h>
#import <mach/machine.h>

static uint16_t HRead16(const uint8_t *p){uint16_t n;memcpy(&n,p,2);return CFSwapInt16LittleToHost(n);}
static uint32_t HRead32(const uint8_t *p){uint32_t n;memcpy(&n,p,4);return CFSwapInt32LittleToHost(n);}
static uint32_t HReadBig32(const uint8_t *p){uint32_t n;memcpy(&n,p,4);return CFSwapInt32BigToHost(n);}

// Read selected bounded entries only. No IPA path is extracted into the filesystem.
static NSDictionary<NSString *,NSDictionary *> *HZipIndex(NSData *archive){
  const uint8_t *bytes=archive.bytes;NSUInteger size=archive.length;if(size<22)return nil;
  NSUInteger minimum=size>65557?size-65557:0,end=NSNotFound;
  for(NSUInteger i=size-22;;i--){if(HRead32(bytes+i)==0x06054b50&&i+22+HRead16(bytes+i+20)==size){end=i;break;}if(i==minimum)break;}
  if(end==NSNotFound||HRead16(bytes+end+4)||HRead16(bytes+end+6)||HRead16(bytes+end+8)!=HRead16(bytes+end+10))return nil;
  NSUInteger count=HRead16(bytes+end+10),length=HRead32(bytes+end+12),start=HRead32(bytes+end+16);
  if(start>end||length>end-start)return nil;
  NSMutableDictionary *index=[NSMutableDictionary dictionary];NSUInteger at=start;
  for(NSUInteger i=0;i<count;i++){
    if(at+46>end||HRead32(bytes+at)!=0x02014b50)return nil;
    NSUInteger nameLength=HRead16(bytes+at+28),extra=HRead16(bytes+at+30),comment=HRead16(bytes+at+32);
    if(at+46+nameLength+extra+comment>start+length)return nil;
    NSString *name=[[NSString alloc] initWithBytes:bytes+at+46 length:nameLength encoding:NSUTF8StringEncoding];
    if(!name||index[name])return nil;
    index[name]=@{@"offset":@(HRead32(bytes+at+42)),@"compressed":@(HRead32(bytes+at+20)),
      @"size":@(HRead32(bytes+at+24)),@"crc":@(HRead32(bytes+at+16)),
      @"method":@(HRead16(bytes+at+10)),@"flags":@(HRead16(bytes+at+8))};
    at+=46+nameLength+extra+comment;
  }
  return at==start+length?index:nil;
}
static NSData *HZipRead(NSData *archive,NSDictionary *entry,NSUInteger limit){
  if(!entry)return nil;NSUInteger at=[entry[@"offset"] unsignedIntegerValue],compressed=[entry[@"compressed"] unsignedIntegerValue],size=[entry[@"size"] unsignedIntegerValue];
  const uint8_t *bytes=archive.bytes;if(size>limit||compressed>limit||at+30>archive.length||HRead32(bytes+at)!=0x04034b50||([entry[@"flags"] unsignedIntValue]&1))return nil;
  NSUInteger start=at+30+HRead16(bytes+at+26)+HRead16(bytes+at+28);
  if(start>archive.length||compressed>archive.length-start)return nil;
  NSMutableData *result=[NSMutableData dataWithLength:size];int method=[entry[@"method"] intValue];
  if(method==0){if(compressed!=size)return nil;memcpy(result.mutableBytes,bytes+start,size);}
  else if(method==8){
    z_stream stream={0};stream.next_in=(Bytef *)(bytes+start);stream.avail_in=(uInt)compressed;
    stream.next_out=result.mutableBytes;stream.avail_out=(uInt)size;
    if(inflateInit2(&stream,-MAX_WBITS)!=Z_OK)return nil;
    int status=inflate(&stream,Z_FINISH);BOOL valid=status==Z_STREAM_END&&stream.total_out==size&&stream.total_in==compressed;inflateEnd(&stream);if(!valid)return nil;
  }else return nil;
  if(crc32(0,result.bytes,(uInt)size)!=[entry[@"crc"] unsignedLongValue])return nil;
  return result;
}
static BOOL HDeviceExecutable(NSData *data){
  const uint8_t *bytes=data.bytes;NSUInteger size=data.length,offset=0;
  if(size<32)return NO;
  if(HReadBig32(bytes)==FAT_MAGIC){
    NSUInteger count=HReadBig32(bytes+4);if(count>32||8+count*20>size)return NO;
    BOOL found=NO;
    for(NSUInteger i=0;i<count;i++){const uint8_t *arch=bytes+8+i*20;if(HReadBig32(arch)==CPU_TYPE_ARM64){offset=HReadBig32(arch+8);NSUInteger length=HReadBig32(arch+12);if(offset>size||length>size-offset)return NO;size=offset+length;found=YES;break;}}
    if(!found)return NO;
  }
  if(offset+32>size||HRead32(bytes+offset)!=MH_MAGIC_64||HRead32(bytes+offset+4)!=CPU_TYPE_ARM64)return NO;
  NSUInteger count=HRead32(bytes+offset+16),commands=HRead32(bytes+offset+20),at=offset+32;
  if(commands>size-at||count>4096)return NO;
  for(NSUInteger i=0;i<count;i++){
    if(at+8>size)return NO;uint32_t command=HRead32(bytes+at),length=HRead32(bytes+at+4);if(length<8||length>size-at)return NO;
    if(command==LC_BUILD_VERSION){NSOperatingSystemVersion version=NSProcessInfo.processInfo.operatingSystemVersion;uint32_t current=(uint32_t)(version.majorVersion<<16|version.minorVersion<<8|version.patchVersion);return length>=24&&HRead32(bytes+at+8)==PLATFORM_IOS&&HRead32(bytes+at+12)<=current;}
    at+=length;
  }
  return NO;
}

@implementation HueviaDistribution
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
  HueviaDistribution *host=[[self alloc] init];
  FlutterMethodChannel *channel=[FlutterMethodChannel methodChannelWithName:@"cc.huevia/distribution" binaryMessenger:registrar.messenger];
  [registrar addMethodCallDelegate:host channel:channel];
}
- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)reply {
  if([call.method isEqualToString:@"information"]){
    NSBundle *bundle=NSBundle.mainBundle;
    reply(@{@"bundleId":bundle.bundleIdentifier?:@"",@"osVersion":UIDevice.currentDevice.systemVersion,@"versionName":[bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"]?:@"",
      @"versionCode":[bundle objectForInfoDictionaryKey:@"CFBundleVersion"]?:@"",@"manifestUrl":[bundle objectForInfoDictionaryKey:@"HueviaIosReleaseManifest"]?:@""});return;
  }
  if(![call.method isEqualToString:@"verifyIpa"]){reply(FlutterMethodNotImplemented);return;}
  NSDictionary *args=[call.arguments isKindOfClass:NSDictionary.class]?call.arguments:@{};
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{@autoreleasepool{
    BOOL valid=NO;
    @try{
      NSString *path=args[@"path"];
      NSURL *base=[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
      NSString *root=[[[base URLByAppendingPathComponent:@"Huevia/app-updates-ios" isDirectory:YES] path] stringByResolvingSymlinksInPath];
      NSString *resolved=[path isKindOfClass:NSString.class]?[path stringByResolvingSymlinksInPath]:nil;
      if(resolved&&[resolved.stringByDeletingLastPathComponent isEqualToString:root]&&[resolved.pathExtension isEqualToString:@"part"]){
        NSDictionary *attributes=[NSFileManager.defaultManager attributesOfItemAtPath:resolved error:nil];
        unsigned long long length=[attributes fileSize];
        if(length>=1024&&length<=128ULL*1024*1024){
          NSData *archive=[NSData dataWithContentsOfFile:resolved options:NSDataReadingMappedIfSafe error:nil];
          NSDictionary *index=HZipIndex(archive);NSMutableArray *plists=[NSMutableArray array];
          for(NSString *name in index){NSArray *parts=[name componentsSeparatedByString:@"/"];if(parts.count==3&&[parts[0] isEqualToString:@"Payload"]&&[parts[1] hasSuffix:@".app"]&&[parts[2] isEqualToString:@"Info.plist"])[plists addObject:name];}
          if(plists.count==1){
            NSString *plistPath=plists.firstObject;NSData *encoded=HZipRead(archive,index[plistPath],1024*1024);
            NSDictionary *plist=encoded?[NSPropertyListSerialization propertyListWithData:encoded options:NSPropertyListImmutable format:nil error:nil]:nil;
            NSString *executable=plist[@"CFBundleExecutable"];
            if([plist isKindOfClass:NSDictionary.class]&&[plist[@"CFBundleIdentifier"] isEqual:args[@"bundleId"]]&&
              [plist[@"CFBundleIdentifier"] isEqual:NSBundle.mainBundle.bundleIdentifier]&&[plist[@"CFBundleShortVersionString"] isEqual:args[@"versionName"]]&&
              [plist[@"CFBundleVersion"] isEqual:args[@"versionCode"]]&&[plist[@"MinimumOSVersion"] isKindOfClass:NSString.class]&&
              [plist[@"MinimumOSVersion"] compare:UIDevice.currentDevice.systemVersion options:NSNumericSearch]!=NSOrderedDescending&&
              [executable isKindOfClass:NSString.class]&&[executable.lastPathComponent isEqual:executable]){
              NSString *binary=[plistPath.stringByDeletingLastPathComponent stringByAppendingPathComponent:executable];
              valid=HDeviceExecutable(HZipRead(archive,index[binary],256*1024*1024));
            }
          }
        }
      }
    }@catch(NSException *exception){valid=NO;}
    dispatch_async(dispatch_get_main_queue(),^{reply(valid?nil:[FlutterError errorWithCode:@"IPA_INVALID" message:@"IPA 应用身份、版本或 ARM64 真机平台校验失败。" details:nil]);});
  }});
}
@end
