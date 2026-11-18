#import "HueviaCameraLocation.h"

#import <CommonCrypto/CommonCryptor.h>
#import <CoreBluetooth/CoreBluetooth.h>
#import <CoreLocation/CoreLocation.h>
#import <ExternalAccessory/ExternalAccessory.h>
#import <TargetConditionals.h>
#import <math.h>

typedef NS_ENUM(NSUInteger, HueviaBluetoothOperation) {
  HueviaBluetoothIdle,
  HueviaBluetoothScan,
  HueviaBluetoothConnect,
  HueviaBluetoothWrite,
  HueviaBluetoothPairClassic,
};

static CBUUID *NikonUuid(NSString *shortId) {
  return [CBUUID UUIDWithString:[shortId stringByAppendingString:@"-3dd4-4255-8d62-6dc7b9bd5561"]];
}

static FlutterError *LocationError(NSString *code, NSString *message) {
  return [FlutterError errorWithCode:code message:message details:nil];
}

@interface HueviaCameraLocation () <FlutterStreamHandler, CBCentralManagerDelegate, CBPeripheralDelegate, CLLocationManagerDelegate>
@property(nonatomic, strong) FlutterMethodChannel *commands;
@property(nonatomic, strong) FlutterEventChannel *events;
@property(nonatomic, copy) FlutterEventSink sink;
@property(nonatomic, strong) CBCentralManager *central;
@property(nonatomic, strong) NSMutableDictionary<NSString *, CBPeripheral *> *discovered;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *names;
@property(nonatomic, strong) CBPeripheral *camera;
@property(nonatomic, strong) CBCharacteristic *pairing;
@property(nonatomic, strong) CBCharacteristic *success;
@property(nonatomic, strong) CBCharacteristic *controllerName;
@property(nonatomic, strong) CBCharacteristic *geo;
@property(nonatomic, strong) CBCharacteristic *pendingWrite;
@property(nonatomic, strong) CLLocationManager *location;
@property(nonatomic, copy) FlutterResult locateReply;
@property(nonatomic, copy) FlutterResult bluetoothReply;
@property(nonatomic) HueviaBluetoothOperation bluetoothOperation;
@property(nonatomic) NSUInteger bluetoothToken;
@property(nonatomic) NSUInteger locationToken;
@property(nonatomic) BOOL requestLocationStarted;
@property(nonatomic) BOOL scanning;
@property(nonatomic) BOOL ready;
@property(nonatomic) BOOL pickerVisible;
@property(nonatomic) BOOL detached;
@end

@implementation HueviaCameraLocation

- (instancetype)initWithMessenger:(NSObject<FlutterBinaryMessenger> *)messenger {
  self = [super init];
  if (!self) return nil;
  _discovered = [NSMutableDictionary dictionary];
  _names = [NSMutableDictionary dictionary];
  _commands = [FlutterMethodChannel methodChannelWithName:@"cc.huevia/camera-location" binaryMessenger:messenger];
  _events = [FlutterEventChannel eventChannelWithName:@"cc.huevia/camera-location/events" binaryMessenger:messenger];
  __weak HueviaCameraLocation *weakSelf = self;
  [_commands setMethodCallHandler:^(FlutterMethodCall *call, FlutterResult reply) {
    HueviaCameraLocation *owner = weakSelf;
    if (owner) {
      [owner handleMethodCall:call result:reply];
    } else {
      reply(LocationError(@"CANCELLED", @"蓝牙定位已关闭。"));
    }
  }];
  [_events setStreamHandler:self];
  return self;
}

- (FlutterError *)onListenWithArguments:(id)arguments eventSink:(FlutterEventSink)sink {
  self.sink = sink;
  return nil;
}

- (FlutterError *)onCancelWithArguments:(id)arguments {
  self.sink = nil;
  [self stop];
  return nil;
}

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)reply {
  if (self.detached) {
    reply(LocationError(@"CANCELLED", @"蓝牙定位已关闭。"));
    return;
  }
  NSDictionary *args = [call.arguments isKindOfClass:NSDictionary.class] ? call.arguments : @{};
  if ([call.method isEqualToString:@"stop"]) {
    [self stop];
    reply(nil);
  } else if ([call.method isEqualToString:@"locate"]) {
    [self locate:reply];
  } else if ([call.method isEqualToString:@"encrypt"]) {
    [self encrypt:args[@"bytes"] reply:reply];
  } else if ([call.method isEqualToString:@"scan"]) {
    [self scan:reply];
  } else if ([call.method isEqualToString:@"connect"]) {
    [self connect:args[@"id"] reply:reply];
  } else if ([call.method isEqualToString:@"write"]) {
    [self write:args reply:reply];
  } else if ([call.method isEqualToString:@"pairClassic"]) {
    [self pairClassic:reply];
  } else {
    reply(FlutterMethodNotImplemented);
  }
}

- (void)encrypt:(id)value reply:(FlutterResult)reply {
  NSData *input = [value isKindOfClass:FlutterStandardTypedData.class] ? [value data] : nil;
  if (input.length != 8) {
    reply(LocationError(@"INVALID_ARGUMENT", @"相机配对数据格式不正确。"));
    return;
  }
  // Fixed key of the Nikon smart-device protocol; it is not a pairing record.
  const uint8_t key[] = {0xff, 0xff, 0xaa, 0x55, 0x11, 0x22, 0x33, 0x00};
  uint8_t output[8];
  size_t count = 0;
  CCCryptorStatus status = CCCrypt(kCCEncrypt, kCCAlgorithmBlowfish, kCCOptionECBMode,
                                  key, sizeof(key), NULL, input.bytes, input.length,
                                  output, sizeof(output), &count);
  if (status != kCCSuccess || count != sizeof(output)) {
    reply(LocationError(@"PAIRING_FAILED", @"无法处理相机配对数据。"));
    return;
  }
  reply([FlutterStandardTypedData typedDataWithBytes:[NSData dataWithBytes:output length:count]]);
}

- (BOOL)beginBluetooth:(HueviaBluetoothOperation)operation reply:(FlutterResult)reply {
  if (self.bluetoothReply || self.pickerVisible) {
    reply(LocationError(@"BUSY", @"请先完成当前蓝牙操作。"));
    return NO;
  }
  self.bluetoothToken++;
  self.bluetoothOperation = operation;
  self.bluetoothReply = reply;
  return YES;
}

- (void)finishBluetooth:(id)value {
  FlutterResult reply = self.bluetoothReply;
  self.bluetoothReply = nil;
  self.bluetoothOperation = HueviaBluetoothIdle;
  self.pendingWrite = nil;
  self.bluetoothToken++;
  if (reply) reply(value);
}

- (void)closeLink {
  CBPeripheral *camera = self.camera;
  camera.delegate = nil;
  self.camera = nil;
  self.ready = NO;
  self.pairing = nil;
  self.success = nil;
  self.controllerName = nil;
  self.geo = nil;
  if (camera && camera.state != CBPeripheralStateDisconnected) {
    [self.central cancelPeripheralConnection:camera];
  }
}

- (void)stopScan {
  if (self.scanning) [self.central stopScan];
  self.scanning = NO;
}

- (void)stop {
  [self stopScan];
  [self closeLink];
  [self.discovered removeAllObjects];
  [self.names removeAllObjects];
  FlutterError *cancelled = LocationError(@"CANCELLED", @"已停止相机蓝牙定位。");
  [self finishBluetooth:cancelled];
  [self finishLocation:cancelled];
}

- (void)detach {
  if (self.detached) return;
  self.detached = YES;
  self.sink = nil;
  [self stop];
  self.central.delegate = nil;
  self.central = nil;
  [self.commands setMethodCallHandler:nil];
  [self.events setStreamHandler:nil];
}

- (void)bluetoothTimeoutAfter:(NSUInteger)seconds message:(NSString *)message {
  NSUInteger token = self.bluetoothToken;
  __weak HueviaCameraLocation *weakSelf = self;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)seconds * NSEC_PER_SEC),
                 dispatch_get_main_queue(), ^{
    HueviaCameraLocation *owner = weakSelf;
    if (!owner.bluetoothReply || token != owner.bluetoothToken) return;
    [owner stopScan];
    [owner closeLink];
    [owner finishBluetooth:LocationError(@"TIMEOUT", message)];
  });
}

- (void)scan:(FlutterResult)reply {
  if (self.camera) {
    reply(LocationError(@"BUSY", @"请先断开当前蓝牙相机再搜索。"));
    return;
  }
  if (![self beginBluetooth:HueviaBluetoothScan reply:reply]) return;
  [self.discovered removeAllObjects];
  [self.names removeAllObjects];
  if (!self.central) {
    self.central = [[CBCentralManager alloc] initWithDelegate:self queue:dispatch_get_main_queue()
                                                     options:@{CBCentralManagerOptionShowPowerAlertKey: @NO}];
  }
  if (self.central.state == CBManagerStateUnknown || self.central.state == CBManagerStateResetting) {
    [self bluetoothTimeoutAfter:30 message:@"等待蓝牙权限超时，请检查系统蓝牙设置。"];
    return;
  }
  [self centralManagerDidUpdateState:self.central];
}

- (void)beginScan {
  if (self.scanning) return;
  self.scanning = YES;
  // Saved Nikon cameras may omit the service UUID while advertising reconnects.
  [self.central scanForPeripheralsWithServices:nil options:nil];
  NSUInteger token = ++self.bluetoothToken;
  __weak HueviaCameraLocation *weakSelf = self;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 8 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
    HueviaCameraLocation *owner = weakSelf;
    if (token != owner.bluetoothToken || owner.bluetoothOperation != HueviaBluetoothScan) return;
    [owner stopScan];
    NSMutableArray *devices = [NSMutableArray array];
    for (NSString *identifier in [owner.names.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
      [devices addObject:@{@"id": identifier, @"name": owner.names[identifier]}];
    }
    [owner finishBluetooth:devices];
  });
}

- (void)centralManagerDidUpdateState:(CBCentralManager *)central {
  if (central != self.central || self.detached) return;
  if (central.state == CBManagerStatePoweredOn) {
    if (self.bluetoothOperation == HueviaBluetoothScan) [self beginScan];
    return;
  }
  if (central.state == CBManagerStateUnknown ||
      (central.state == CBManagerStateResetting && !self.camera && !self.scanning)) return;
  BOOL notify = self.ready && self.bluetoothOperation != HueviaBluetoothPairClassic;
  [self stopScan];
  [self closeLink];
  NSString *message = @"蓝牙不可用，请在 iPhone 设置中开启蓝牙后重试。";
  if (central.state == CBManagerStateUnauthorized) message = @"请在 iPhone 设置中允许 Huevia 使用蓝牙。";
  if (central.state == CBManagerStateUnsupported) message = @"此设备不支持相机蓝牙定位。";
  [self finishBluetooth:LocationError(@"BLUETOOTH_UNAVAILABLE", message)];
  if (notify && self.sink) self.sink(@{@"type": @"disconnected"});
}

- (void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)peripheral
     advertisementData:(NSDictionary<NSString *, id> *)advertisementData RSSI:(NSNumber *)rssi {
  if (central != self.central || !self.scanning) return;
  NSArray *services = advertisementData[CBAdvertisementDataServiceUUIDsKey];
  NSData *manufacturer = advertisementData[CBAdvertisementDataManufacturerDataKey];
  const uint8_t *bytes = manufacturer.bytes;
  BOOL nikonManufacturer = manufacturer.length >= 2 && bytes[0] == 0x99 && bytes[1] == 0x03;
  if (![services containsObject:NikonUuid(@"0000de00")] && !nikonManufacturer) return;
  NSString *name = advertisementData[CBAdvertisementDataLocalNameKey] ?: peripheral.name;
  if (!name.length) return;
  NSString *identifier = peripheral.identifier.UUIDString;
  self.names[identifier] = name;
  self.discovered[identifier] = peripheral;
}

- (void)connect:(id)identifier reply:(FlutterResult)reply {
  if (self.camera) {
    reply(LocationError(@"BUSY", @"请先断开当前蓝牙相机。"));
    return;
  }
  CBPeripheral *camera = [identifier isKindOfClass:NSString.class] ? self.discovered[identifier] : nil;
  if (!camera || self.central.state != CBManagerStatePoweredOn) {
    reply(LocationError(@"CAMERA_UNAVAILABLE", @"请重新搜索并选择蓝牙相机。"));
    return;
  }
  if (![self beginBluetooth:HueviaBluetoothConnect reply:reply]) return;
  [self.discovered removeAllObjects];
  [self.names removeAllObjects];
  self.camera = camera;
  camera.delegate = self;
  [self.central connectPeripheral:camera options:nil];
  [self bluetoothTimeoutAfter:18 message:@"连接蓝牙相机超时，请唤醒相机后重试。"];
}

- (void)failConnect:(NSString *)message {
  [self closeLink];
  [self finishBluetooth:LocationError(@"CONNECT_FAILED", message)];
}

- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral {
  if (central != self.central || peripheral != self.camera || self.bluetoothOperation != HueviaBluetoothConnect) return;
  [peripheral discoverServices:@[NikonUuid(@"0000de00")]];
}

- (void)centralManager:(CBCentralManager *)central didFailToConnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error {
  if (central != self.central || peripheral != self.camera || self.bluetoothOperation != HueviaBluetoothConnect) return;
  [self failConnect:@"无法连接蓝牙相机，请检查相机配对状态。"];
}

- (void)centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error {
  if (central != self.central || peripheral != self.camera) return;
  BOOL completingPair = self.bluetoothOperation == HueviaBluetoothPairClassic;
  BOOL notify = self.ready && !completingPair;
  [self closeLink];
  if (completingPair) {
    [self showClassicPicker];
    return;
  }
  [self finishBluetooth:LocationError(@"DISCONNECTED", @"相机蓝牙连接已断开。")];
  if (notify && self.sink) self.sink(@{@"type": @"disconnected"});
}

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(NSError *)error {
  if (peripheral != self.camera || self.bluetoothOperation != HueviaBluetoothConnect) return;
  if (!error) {
    for (CBService *service in peripheral.services) {
      if (![service.UUID isEqual:NikonUuid(@"0000de00")]) continue;
      [peripheral discoverCharacteristics:@[NikonUuid(@"00002000"), NikonUuid(@"00002008"),
                                             NikonUuid(@"00002002"), NikonUuid(@"00002007")]
                                 forService:service];
      return;
    }
  }
  [self failConnect:@"相机未提供尼康智能设备蓝牙服务。"];
}

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverCharacteristicsForService:(CBService *)service error:(NSError *)error {
  if (peripheral != self.camera || self.bluetoothOperation != HueviaBluetoothConnect) return;
  if (!error) {
    for (CBCharacteristic *characteristic in service.characteristics) {
      if ([characteristic.UUID isEqual:NikonUuid(@"00002000")]) self.pairing = characteristic;
      if ([characteristic.UUID isEqual:NikonUuid(@"00002008")]) self.success = characteristic;
      if ([characteristic.UUID isEqual:NikonUuid(@"00002002")]) self.controllerName = characteristic;
      if ([characteristic.UUID isEqual:NikonUuid(@"00002007")]) self.geo = characteristic;
    }
  }
  if (!(self.pairing.properties & CBCharacteristicPropertyIndicate) ||
      !(self.pairing.properties & CBCharacteristicPropertyWrite) ||
      !(self.success.properties & (CBCharacteristicPropertyNotify | CBCharacteristicPropertyIndicate)) ||
      !(self.controllerName.properties & CBCharacteristicPropertyWrite) ||
      !(self.geo.properties & CBCharacteristicPropertyWrite) ||
      [peripheral maximumWriteValueLengthForType:CBCharacteristicWriteWithResponse] < 41) {
    [self failConnect:@"相机蓝牙服务缺少配对或位置数据通道。请在相机上选择连接至智能设备。"];
    return;
  }
  [peripheral setNotifyValue:YES forCharacteristic:self.pairing];
}

- (void)peripheral:(CBPeripheral *)peripheral didUpdateNotificationStateForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
  if (peripheral != self.camera || self.bluetoothOperation != HueviaBluetoothConnect) return;
  if (error || !characteristic.isNotifying) {
    [self failConnect:@"无法订阅相机配对消息。请重新打开机身配对页面。"];
  } else if (characteristic == self.pairing) {
    [peripheral setNotifyValue:YES forCharacteristic:self.success];
  } else if (characteristic == self.success) {
    self.ready = YES;
    [self finishBluetooth:nil];
  }
}

- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
  if (peripheral != self.camera || !self.ready || error || !self.sink) return;
  NSData *value = characteristic.value;
  NSString *type = nil;
  if (characteristic == self.pairing && value.length == 17) type = @"pair";
  if (characteristic == self.success && value.length == 2) type = @"ready";
  if (type) self.sink(@{@"type": type, @"bytes": [FlutterStandardTypedData typedDataWithBytes:value]});
}

- (void)write:(NSDictionary *)args reply:(FlutterResult)reply {
  if (!self.ready || !self.camera) {
    reply(LocationError(@"DISCONNECTED", @"相机蓝牙连接已断开。"));
    return;
  }
  CBCharacteristic *target;
  NSUInteger length;
  if ([args[@"type"] isEqual:@"pair"]) {
    target = self.pairing;
    length = 17;
  } else if ([args[@"type"] isEqual:@"name"]) {
    target = self.controllerName;
    length = 32;
  } else if ([args[@"type"] isEqual:@"location"]) {
    target = self.geo;
    length = 41;
  } else {
    reply(LocationError(@"INVALID_ARGUMENT", @"未知的相机蓝牙数据类型。"));
    return;
  }
  id bytes = args[@"bytes"];
  NSData *data = [bytes isKindOfClass:FlutterStandardTypedData.class] ? [bytes data] : nil;
  if (data.length != length) {
    reply(LocationError(@"INVALID_ARGUMENT", @"相机蓝牙数据长度不正确。"));
    return;
  }
  if (![self beginBluetooth:HueviaBluetoothWrite reply:reply]) return;
  self.pendingWrite = target;
  [self.camera writeValue:data forCharacteristic:target type:CBCharacteristicWriteWithResponse];
  [self bluetoothTimeoutAfter:10 message:@"相机没有确认收到蓝牙数据，请重新连接。"];
}

- (void)peripheral:(CBPeripheral *)peripheral didWriteValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
  if (peripheral != self.camera || self.bluetoothOperation != HueviaBluetoothWrite || characteristic != self.pendingWrite) return;
  if (error) {
    [self closeLink];
    [self finishBluetooth:LocationError(@"WRITE_REJECTED", @"相机未接收蓝牙数据，请核对机身选择的配对设备。")];
  } else {
    [self finishBluetooth:nil];
  }
}

- (void)pairClassic:(FlutterResult)reply {
  if (![self beginBluetooth:HueviaBluetoothPairClassic reply:reply]) return;
  [self bluetoothTimeoutAfter:65 message:@"等待系统蓝牙配对超时，请在相机和手机上确认配对码后重试。"];
  if (self.camera && self.camera.state != CBPeripheralStateDisconnected) {
    // The camera changes from BLE to Classic discovery after GATT closes.
    [self.central cancelPeripheralConnection:self.camera];
  } else {
    [self closeLink];
    [self showClassicPicker];
  }
}

- (void)showClassicPicker {
  if (self.bluetoothOperation != HueviaBluetoothPairClassic || self.pickerVisible) return;
#if TARGET_OS_SIMULATOR
  [self finishBluetooth:LocationError(@"UNSUPPORTED", @"请使用实体 iPhone 与相机配对。")];
#else
  self.pickerVisible = YES;
  NSUInteger token = self.bluetoothToken;
  __weak HueviaCameraLocation *weakSelf = self;
  // The Classic Bluetooth name can differ from the BLE name. The system
  // requires the user to select the camera and confirm the pairing code.
  [[EAAccessoryManager sharedAccessoryManager] showBluetoothAccessoryPickerWithNameFilter:nil completion:^(NSError *error) {
    dispatch_async(dispatch_get_main_queue(), ^{
      HueviaCameraLocation *owner = weakSelf;
      owner.pickerVisible = NO;
      if (token != owner.bluetoothToken || owner.bluetoothOperation != HueviaBluetoothPairClassic) return;
      BOOL alreadyPaired = [error.domain isEqualToString:EABluetoothAccessoryPickerErrorDomain] &&
                           error.code == EABluetoothAccessoryPickerAlreadyConnected;
      if (!error || alreadyPaired) {
        [owner finishBluetooth:nil];
      } else {
        BOOL cancelled = [error.domain isEqualToString:EABluetoothAccessoryPickerErrorDomain] &&
                         error.code == EABluetoothAccessoryPickerResultCancelled;
        [owner finishBluetooth:LocationError(cancelled ? @"CANCELLED" : @"PAIRING_FAILED",
          cancelled ? @"已取消相机蓝牙配对。" : @"系统未完成蓝牙配对，请重新打开机身配对页面后重试。")];
      }
    });
  }];
#endif
}

- (void)locate:(FlutterResult)reply {
  if (self.locateReply) {
    reply(LocationError(@"BUSY", @"正在获取手机位置。"));
    return;
  }
  self.locateReply = reply;
  self.location = [[CLLocationManager alloc] init];
  self.location.delegate = self;
  self.location.desiredAccuracy = kCLLocationAccuracyBest;
  if (self.location.authorizationStatus == kCLAuthorizationStatusNotDetermined) {
    [self locationTimeoutAfter:40 message:@"等待位置权限超时，请在系统设置中允许定位后重试。"];
    [self.location requestWhenInUseAuthorization];
  } else {
    [self requestAuthorizedLocation];
  }
}

- (void)locationManagerDidChangeAuthorization:(CLLocationManager *)manager {
  if (manager == self.location) [self requestAuthorizedLocation];
}

- (void)requestAuthorizedLocation {
  if (!self.locateReply) return;
  CLAuthorizationStatus status = self.location.authorizationStatus;
  if (status == kCLAuthorizationStatusNotDetermined) return;
  if (status != kCLAuthorizationStatusAuthorizedWhenInUse && status != kCLAuthorizationStatusAuthorizedAlways) {
    [self finishLocation:LocationError(@"LOCATION_PERMISSION", @"请在 iPhone 设置中允许 Huevia 在使用期间访问位置。")];
    return;
  }
  if (self.requestLocationStarted) return;
  if (self.location.accuracyAuthorization == CLAccuracyAuthorizationReducedAccuracy) {
    [self finishLocation:LocationError(@"LOCATION_PERMISSION", @"请在 iPhone 设置中为 Huevia 开启精确位置。")];
    return;
  }
  self.requestLocationStarted = YES;
  [self locationTimeoutAfter:15 message:@"未能及时获取手机位置，请在信号良好的地方重试。"];
  [self.location requestLocation];
}

- (void)locationTimeoutAfter:(NSUInteger)seconds message:(NSString *)message {
  NSUInteger token = ++self.locationToken;
  __weak HueviaCameraLocation *weakSelf = self;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)seconds * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
    HueviaCameraLocation *owner = weakSelf;
    if (token == owner.locationToken && owner.locateReply) {
      [owner finishLocation:LocationError(@"TIMEOUT", message)];
    }
  });
}

- (void)finishLocation:(id)value {
  FlutterResult reply = self.locateReply;
  self.locateReply = nil;
  self.locationToken++;
  self.requestLocationStarted = NO;
  self.location.delegate = nil;
  [self.location stopUpdatingLocation];
  self.location = nil;
  if (reply) reply(value);
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
  if (manager != self.location || !self.locateReply) return;
  for (CLLocation *fix in locations.reverseObjectEnumerator) {
    NSTimeInterval age = -fix.timestamp.timeIntervalSinceNow;
    NSTimeInterval time = fix.timestamp.timeIntervalSince1970;
    if (!CLLocationCoordinate2DIsValid(fix.coordinate) || !isfinite(fix.horizontalAccuracy) ||
        fix.horizontalAccuracy < 0 || !isfinite(age) || age < -5 || age > 30 || !isfinite(time)) continue;
    id altitude = fix.verticalAccuracy >= 0 && isfinite(fix.altitude) ? @(fix.altitude) : NSNull.null;
    [self finishLocation:@{@"latitude": @(fix.coordinate.latitude), @"longitude": @(fix.coordinate.longitude),
                           @"altitude": altitude, @"accuracy": @(fix.horizontalAccuracy),
                           @"time": @((int64_t)llround(time * 1000.0))}];
    return;
  }
  [self finishLocation:LocationError(@"LOCATION_UNAVAILABLE", @"手机还没有获取到新的位置，请重试。")];
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
  if (manager != self.location || !self.locateReply) return;
  [self finishLocation:LocationError(@"LOCATION_UNAVAILABLE", @"无法获取手机位置，请检查定位权限和信号。")];
}

@end
