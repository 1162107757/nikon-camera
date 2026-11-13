#import "HueviaPortraitInference.h"
#import <TensorFlowLiteC/c_api.h>
#import <CommonCrypto/CommonDigest.h>
#import <zlib.h>
#import "cc/huevia/shared/SharedPortraitInference.h"
#import "cc/huevia/shared/SharedRetouch.h"
#import "java/io/IOException.h"
#import "java/io/InterruptedIOException.h"
#import "IOSPrimitiveArray.h"
#include <atomic>
#include <thread>
#include <chrono>
#include <vector>

namespace {
void fail(NSString *s){@throw [[JavaIoIOException alloc] initWithNSString:s];}
void check(HueviaTask *task){if(task.cancelled)@throw [[JavaIoInterruptedIOException alloc] initWithNSString:@"人物推理已停止。"] ;}
NSString *json(id value){NSData *d=[NSJSONSerialization dataWithJSONObject:value options:0 error:nil];if(!d)fail(@"人物推理数据无效。");return [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];}
NSDictionary *object(NSString *s){id v=[NSJSONSerialization JSONObjectWithData:[s dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];if(![v isKindOfClass:NSDictionary.class])fail(@"人物推理结果无效。");return v;}
NSString *sha(NSData *data){unsigned char bytes[CC_SHA256_DIGEST_LENGTH];CC_SHA256(data.bytes,(CC_LONG)data.length,bytes);NSMutableString *s=[NSMutableString string];for(int i=0;i<CC_SHA256_DIGEST_LENGTH;i++)[s appendFormat:@"%02x",bytes[i]];return s;}
NSData *asset(NSString *name){NSURL *bundleURL=[NSBundle.mainBundle URLForResource:@"HueviaNativeAssets" withExtension:@"bundle"]?:[[NSBundle bundleForClass:HueviaPortraitInference.class] URLForResource:@"HueviaNativeAssets" withExtension:@"bundle"];NSBundle *bundle=[NSBundle bundleWithURL:bundleURL];NSURL *url=[bundle URLForResource:name withExtension:nil subdirectory:@"portrait"]?:[bundle URLForResource:name withExtension:nil];NSData *data=url?[NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:nil]:nil;if(!data)fail(@"原版人像模型尚未安装，请重新安装应用。");return data;}
NSData *model(BOOL skin,HueviaTask *task){
  static NSData *skinModel=nil,*meshModel=nil;
  @synchronized(HueviaPortraitInference.class){
    check(task);if(skin&&skinModel)return skinModel;if(!skin&&meshModel)return meshModel;
    if(!skin){NSData *data=asset(@"face_landmarks_detector.tflite");if(data.length!=2553590||![sha(data) isEqual:@"c7d54204ce0448474c7f3fa9af494787c0965cbdd6f20fc72867e43046bd43d5"])fail(@"面部关键点模型校验失败。");meshModel=data;return data;}
    NSData *packed=asset(@"face_skin_multiclass.shuffle4.zlib");if(packed.length!=13881786||![sha(packed) isEqual:@"9920fafc503c9090b3840c6fb433efc7eeb117bb00176b04034bd589c0e19bb0"])fail(@"语义皮肤模型压缩包校验失败。");
    const NSUInteger count=16371837,words=count/4;NSMutableData *planes=[NSMutableData dataWithLength:count],*decoded=[NSMutableData dataWithLength:count];uLongf length=count;
    if(uncompress((Bytef *)planes.mutableBytes,&length,(const Bytef *)packed.bytes,(uLong)packed.length)!=Z_OK||length!=count)fail(@"语义皮肤模型解压失败。");
    uint8_t *out=(uint8_t *)decoded.mutableBytes;const uint8_t *in=(const uint8_t *)planes.bytes;
    for(NSUInteger plane=0;plane<4;plane++)for(NSUInteger word=0;word<words;word++){if((word&65535)==0)check(task);out[word*4+plane]=in[plane*words+word];}
    for(NSUInteger i=words*4;i<count;i++)out[i]=in[i];check(task);if(![sha(decoded) isEqual:@"c6748b1253a99067ef71f7e26ca71096cd449baefa8f101900ea23016507e0e0"])fail(@"语义皮肤模型还原校验失败。");skinModel=decoded;return skinModel;
  }
}
struct CPU {
  __strong NSData *bytes;TfLiteModel *modelRef=nullptr;TfLiteInterpreterOptions *options=nullptr;TfLiteInterpreter *interpreter=nullptr;
  CPU(BOOL skin,HueviaTask *task){bytes=model(skin,task);modelRef=TfLiteModelCreate(bytes.bytes,bytes.length);options=TfLiteInterpreterOptionsCreate();TfLiteInterpreterOptionsSetNumThreads(options,2);TfLiteInterpreterOptionsEnableCancellation(options,true);interpreter=TfLiteInterpreterCreate(modelRef,options);if(!interpreter||TfLiteInterpreterAllocateTensors(interpreter)!=kTfLiteOk)fail(@"原版人像模型无法建立CPU推理。");TfLiteTensor *input=TfLiteInterpreterGetInputTensor(interpreter,0);if(TfLiteInterpreterGetInputTensorCount(interpreter)!=1||TfLiteTensorType(input)!=kTfLiteFloat32||TfLiteTensorNumDims(input)!=4||TfLiteTensorDim(input,0)!=1||TfLiteTensorDim(input,1)!=256||TfLiteTensorDim(input,2)!=256||TfLiteTensorDim(input,3)!=3)fail(@"原版人像模型输入格式不符。");}
  ~CPU(){if(interpreter)TfLiteInterpreterDelete(interpreter);if(options)TfLiteInterpreterOptionsDelete(options);if(modelRef)TfLiteModelDelete(modelRef);}
  IOSFloatArray *output(int index){if(index>=TfLiteInterpreterGetOutputTensorCount(interpreter))fail(@"原版模型输出数量不符。");const TfLiteTensor *tensor=TfLiteInterpreterGetOutputTensor(interpreter,index);if(TfLiteTensorType(tensor)!=kTfLiteFloat32||TfLiteTensorByteSize(tensor)%sizeof(float))fail(@"原版模型输出格式不符。");size_t n=TfLiteTensorByteSize(tensor)/sizeof(float);if(n>256*256*6)fail(@"模型输出超出上限。");IOSFloatArray *out=[IOSFloatArray arrayWithLength:(jint)n];std::vector<float> buffer(n);if(TfLiteTensorCopyToBuffer(tensor,buffer.data(),n*sizeof(float))!=kTfLiteOk)fail(@"无法读取人像模型输出。");for(size_t i=0;i<n;i++)IOSFloatArray_Set(out,(jint)i,buffer[i]);return out;}
  void run(IOSFloatArray *input,HueviaTask *task){check(task);if(input.length!=256*256*3)fail(@"模型输入像素无效。");std::vector<float> values(input.length);for(int i=0;i<input.length;i++)values[i]=IOSFloatArray_Get(input,i);if(TfLiteTensorCopyFromBuffer(TfLiteInterpreterGetInputTensor(interpreter,0),values.data(),values.size()*sizeof(float))!=kTfLiteOk)fail(@"无法写入人像模型输入。");
    std::atomic<bool> done(false);std::thread cancellation([&]{while(!done.load()){if(task.cancelled){TfLiteInterpreterCancel(interpreter);break;}std::this_thread::sleep_for(std::chrono::milliseconds(20));}});TfLiteStatus status=TfLiteInterpreterInvoke(interpreter);done.store(true);cancellation.join();check(task);if(status!=kTfLiteOk)fail(@"人像模型推理未完成，请重试。");}
};
}
@implementation HueviaPortraitInference
+ (NSDictionary *)analyze:(NSDictionary *)p candidates:(NSArray<NSDictionary *> *)proposals image:(HueviaRaster *)image task:(HueviaTask *)task {
  check(task);IOSIntArray *pixels=[IOSIntArray arrayWithLength:image.pixelWidth*image.pixelHeight];for(int i=0;i<pixels.length;i++)IOSIntArray_Set(pixels,i,(jint)image.pixels[i]);
  NSString *mode=p[@"mode"];NSMutableArray *faces=[NSMutableArray array];CPU semantic(YES,task);
  @try {if(proposals.count){CPU mesh(NO,task);for(NSDictionary *face in proposals){@autoreleasepool{check(task);NSMutableDictionary *sampled=[face mutableCopy];uint32_t rgb=(uint32_t)[CcHueviaSharedSharedPortraitInference sampleSkinWithIntArray:pixels withInt:image.pixelWidth withInt:image.pixelHeight withNSString:json(face)];sampled[@"skinR"]=@((rgb>>16)&255);sampled[@"skinG"]=@((rgb>>8)&255);sampled[@"skinB"]=@(rgb&255);NSString *encoded=json(sampled);IOSFloatArray *input=[CcHueviaSharedSharedPortraitInference inputWithIntArray:pixels withInt:image.pixelWidth withInt:image.pixelHeight withNSString:encoded withBoolean:NO withJavaUtilFunctionBooleanSupplier:task];mesh.run(input,task);IOSFloatArray *points=mesh.output(0),*presence=mesh.output(1);if(presence.length!=1)fail(@"面部存在性输出无效。");float logit=IOSFloatArray_Get(presence,0);if(logit<0)continue;
    input=[CcHueviaSharedSharedPortraitInference inputWithIntArray:pixels withInt:image.pixelWidth withInt:image.pixelHeight withNSString:encoded withBoolean:YES withJavaUtilFunctionBooleanSupplier:task];semantic.run(input,task);
    NSString *refined=[CcHueviaSharedSharedPortraitInference faceWithNSString:encoded withInt:image.pixelWidth withInt:image.pixelHeight withFloatArray:points withFloat:logit withFloatArray:semantic.output(0) withJavaUtilFunctionBooleanSupplier:task];if(refined.length)[faces addObject:object(refined)];}}}}@catch(NSException *failure){(void)failure;check(task);if([mode isEqual:@"face"])@throw;[faces removeAllObjects];}
  if(faces.count>1){NSString *all=json(faces);NSMutableArray *isolated=[NSMutableArray array];for(NSDictionary *face in faces)[isolated addObject:object([CcHueviaSharedSharedPortraitInference isolateWithNSString:json(face) withNSString:all withInt:image.pixelWidth withInt:image.pixelHeight withJavaUtilFunctionBooleanSupplier:task])];faces=isolated;}
  NSString *skin=nil,*body=nil,*protection=nil;NSArray *people=nil;
  if([mode isEqual:@"skin"]||[mode isEqual:@"body"]){IOSFloatArray *input=[CcHueviaSharedSharedPortraitInference inputWithIntArray:pixels withInt:image.pixelWidth withInt:image.pixelHeight withNSString:@"" withBoolean:YES withJavaUtilFunctionBooleanSupplier:task];semantic.run(input,task);NSDictionary *person=object([CcHueviaSharedSharedPortraitInference personWithIntArray:pixels withInt:image.pixelWidth withInt:image.pixelHeight withFloatArray:semantic.output(0) withNSString:json(faces) withJavaUtilFunctionBooleanSupplier:task]);skin=person[@"skin"];if([mode isEqual:@"body"]){people=person[@"people"];NSInteger selected=[p[@"person"] integerValue];if(![people isKindOfClass:NSArray.class]||selected<0||selected>=people.count)fail(@"未识别到完整人物，请手动调整塑形范围。");body=json(people[selected]);protection=person[@"protection"];}}
  NSString *acceptedFaces=[mode isEqual:@"body"]?nil:(([mode isEqual:@"face"]||faces.count)?json(faces):nil);NSString *result=[CcHueviaSharedSharedRetouch analysisWithNSString:json(p) withNSString:acceptedFaces withNSString:skin withNSString:body withNSString:protection withJavaUtilFunctionBooleanSupplier:task];NSMutableDictionary *value=[object(result) mutableCopy];value[@"analysisEngine"]=@"TensorFlowLiteC-2.17.0-CPU";value[@"skinMode"]=@"original-six-class-semantic";value[@"meshPoints"]=faces.count?@468:@0;if(people){value[@"people"]=people;value[@"selectedPerson"]=p[@"person"]?:@0;}check(task);return value;
}
@end
