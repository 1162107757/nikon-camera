#import "HueviaRetouch.h"
#import "HueviaPortraitInference.h"
#import <Vision/Vision.h>
#import <CoreVideo/CoreVideo.h>
#import "cc/huevia/shared/SharedRetouch.h"
#import "cc/huevia/shared/SharedPortraitInference.h"
#import "java/io/IOException.h"
#import "java/io/InterruptedIOException.h"
#import "IOSPrimitiveArray.h"
#include <algorithm>
#include <cmath>
#include <vector>

namespace {
void fail(NSString *s){@throw [[JavaIoIOException alloc] initWithNSString:s];}
void check(HueviaTask *task){if(task.cancelled)@throw [[JavaIoInterruptedIOException alloc] initWithNSString:@"编辑计算已停止。"] ;}
NSString *json(id value){NSData *data=[NSJSONSerialization dataWithJSONObject:value options:0 error:nil];if(!data)fail(@"编辑数据无效。");return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];}
NSDictionary *decoded(NSString *s){NSDictionary *v=[NSJSONSerialization JSONObjectWithData:[s dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];if(![v isKindOfClass:NSDictionary.class])fail(@"编辑结果无效。");return v;}
void run(VNRequest *request,CGImageRef image,HueviaTask *task){check(task);NSError *error=nil;VNImageRequestHandler *handler=[[VNImageRequestHandler alloc] initWithCGImage:image options:@{}];if(![handler performRequests:@[request] error:&error])fail(error.localizedDescription?:@"人物识别未完成，请重试。");check(task);}
NSArray *channelMeans(HueviaRaster *image,int firstRow,int rows){uint64_t sums[4]={0,0,0,0};for(int y=firstRow;y<firstRow+rows;y++)for(int x=0;x<image.pixelWidth;x++){uint32_t p=image.pixels[y*image.pixelWidth+x];for(int c=0;c<4;c++)sums[c]+=(p>>(24-c*8))&255;}double count=double(image.pixelWidth)*rows;return @[@(sums[0]/count),@(sums[1]/count),@(sums[2]/count),@(sums[3]/count)];}
NSDictionary *eyeMeans(VNFaceLandmarkRegion2D *region,CGRect box,HueviaRaster *image){
  NSUInteger count=region.pointCount;const CGPoint *normalized=region.normalizedPoints;CGPoint mean=CGPointZero;
  if(!count||!normalized)return @{@"pointCount":@(count),@"available":@NO};
  for(NSUInteger i=0;i<count;i++){mean.x+=normalized[i].x;mean.y+=normalized[i].y;}mean.x/=count;mean.y/=count;
  // Capture the normalized mean before requesting the separately owned image buffer.
  CGPoint manual=CGPointMake((box.origin.x+mean.x*box.size.width)*image.pixelWidth,(1-box.origin.y-mean.y*box.size.height)*image.pixelHeight);
  const CGPoint *absolute=[region pointsInImageOfSize:CGSizeMake(image.pixelWidth,image.pixelHeight)];CGPoint native=CGPointZero;
  if(!absolute)return @{@"pointCount":@(count),@"available":@NO};for(NSUInteger i=0;i<count;i++){native.x+=absolute[i].x;native.y+=absolute[i].y;}native.x/=count;native.y/=count;
  return @{@"pointCount":@(count),@"normalizedMean":@[@(mean.x),@(mean.y)],@"manualTopMean":@[@(manual.x),@(manual.y)],@"nativeImageMean":@[@(native.x),@(native.y)],@"nativeTopMean":@[@(native.x),@(image.pixelHeight-native.y)]};
}
NSMutableDictionary *candidate(HueviaRaster *image,double cx,double cy,double rx,double ry,double roll,NSString *source){
  if(!std::isfinite(cx)||!std::isfinite(cy)||!std::isfinite(rx)||!std::isfinite(ry)||!std::isfinite(roll)||cx<0||cx>1||cy<0||cy>1||rx<=0||rx>1||ry<=0||ry>1||roll< -180||roll>180)return nil;
  int x=std::clamp(int(cx*image.pixelWidth),0,image.pixelWidth-1),y=std::clamp(int(cy*image.pixelHeight),0,image.pixelHeight-1);uint32_t color=image.pixels[y*image.pixelWidth+x];
  return [@{@"cx":@(cx),@"cy":@(cy),@"rx":@(rx),@"ry":@(ry),@"roll":@(roll),@"skinR":@((color>>16)&255),@"skinG":@((color>>8)&255),@"skinB":@(color&255),@"candidateSource":source} mutableCopy];
}
NSDictionary *candidateFrame(NSDictionary *face,HueviaRaster *image){double rx=[face[@"rx"] doubleValue]*image.pixelWidth,ry=[face[@"ry"] doubleValue]*image.pixelHeight;return @{@"cx":face[@"cx"],@"cy":face[@"cy"],@"rx":face[@"rx"],@"ry":face[@"ry"],@"roll":face[@"roll"],@"source":face[@"candidateSource"]?:@"vision-eyes",@"cropSidePixels":@(3.5*std::max(rx,ry)),@"cropShiftPixels":@(-.30*rx/.95)};}
}
@implementation HueviaRetouch
+ (NSDictionary *)request:(NSString *)operation payload:(NSDictionary *)p image:(HueviaRaster *)image task:(HueviaTask *)task {
  NSString *input=json(p),*result=nil;check(task);
  if([operation isEqual:@"media.retouchDescribe"]||[operation isEqual:@"media.retouchChange"]){
    if([p[@"action"] isEqual:@"manualFace"]){if(!image)fail(@"无法读取肤色取样照片。");IOSIntArray *pixels=[IOSIntArray arrayWithLength:image.pixelWidth*image.pixelHeight];for(int i=0;i<pixels.length;i++)*IOSIntArray_GetRef(pixels,i)=(jint)image.pixels[i];NSMutableDictionary *value=[p[@"value"] mutableCopy];value[@"rx"]=value[@"rx"]?:@.12;value[@"ry"]=value[@"ry"]?:@.18;uint32_t color=(uint32_t)[CcHueviaSharedSharedPortraitInference sampleSkinWithIntArray:pixels withInt:image.pixelWidth withInt:image.pixelHeight withNSString:json(value)];value[@"skinR"]=@((color>>16)&255);value[@"skinG"]=@((color>>8)&255);value[@"skinB"]=@(color&255);NSMutableDictionary *next=[p mutableCopy];next[@"value"]=value;input=json(next);}
    return decoded([CcHueviaSharedSharedRetouch requestWithNSString:operation withNSString:input withJavaUtilFunctionBooleanSupplier:task]);
  }
  if(!image||image.pixelWidth<2||image.pixelHeight<2)fail(@"无法读取分析照片。");
  if([operation isEqual:@"media.retouchHeal"]){IOSIntArray *pixels=[IOSIntArray arrayWithLength:image.pixelWidth*image.pixelHeight];for(int i=0;i<pixels.length;i++)*IOSIntArray_GetRef(pixels,i)=(jint)image.pixels[i];return decoded([CcHueviaSharedSharedPortraitInference healWithNSString:input withIntArray:pixels withInt:image.pixelWidth withInt:image.pixelHeight withJavaUtilFunctionBooleanSupplier:task]);}
  if([operation isEqual:@"media.retouchPatch"]){
    if(image.pixelWidth>384||image.pixelHeight>384)fail(@"修补分析图片超过上限。");
    IOSIntArray *pixels=[IOSIntArray arrayWithLength:image.pixelWidth*image.pixelHeight];for(int i=0;i<pixels.length;i++)*IOSIntArray_GetRef(pixels,i)=(jint)image.pixels[i];
    return decoded([CcHueviaSharedSharedRetouch patchWithNSString:input withIntArray:pixels withInt:image.pixelWidth withInt:image.pixelHeight withJavaUtilFunctionBooleanSupplier:task]);
  }
  if(![operation isEqual:@"media.retouchAnalyze"])fail(@"未知的人像操作。");
  if([p[@"mode"] isEqual:@"autoBlemish"]||([p[@"mode"] isEqual:@"overlay"]||[p[@"mode"] isEqual:@"hitFace"]))return [HueviaPortraitInference analyze:p candidates:@[] image:image task:task];
  if([p[@"mode"] isEqual:@"faceBody"]){if([p[@"engine"] isEqual:@"system"])fail(@"逐人全身皮肤需要原版语义模型，请切换分析引擎。");return [HueviaPortraitInference analyze:p candidates:@[] image:image task:task];}
  CGImageRef cg=[image newImage];if(!cg)fail(@"无法创建人物分析图片。");
  @try {
    if(![p[@"engine"] isEqual:@"system"]){
      VNDetectFaceLandmarksRequest *request=[VNDetectFaceLandmarksRequest new];run(request,cg,task);
      NSMutableArray *proposals=[NSMutableArray array];
      BOOL diagnose=[p[@"diagnostics"] isKindOfClass:NSNumber.class]&&[p[@"diagnostics"] boolValue];
      NSUInteger lowConfidence=0,missingEyes=0,smallEyes=0,outsideFrame=0;
      NSMutableArray *confidenceSamples=[NSMutableArray array],*eyeGeometry=[NSMutableArray array];
      for(VNFaceObservation *observation in request.results){
        // One slot belongs to one real observation, not to each attempted crop.
        if(proposals.count>=12)break;
        if(diagnose&&confidenceSamples.count<12)[confidenceSamples addObject:@(observation.confidence)];
        if(observation.confidence<.4){lowConfidence++;continue;}
        CGRect box=observation.boundingBox;
        double boxRoll=observation.roll?-observation.roll.doubleValue*180/M_PI:0;
        NSMutableDictionary *bbox=candidate(image,CGRectGetMidX(box),1-CGRectGetMidY(box),box.size.width*.5,box.size.height*.5,boxRoll,@"vision-bbox");
        VNFaceLandmarkRegion2D *leftEye=observation.landmarks.leftEye,*rightEye=observation.landmarks.rightEye;
        NSMutableDictionary *primary=nil;
        if(leftEye.pointCount&&rightEye.pointCount){
          auto center=[&](VNFaceLandmarkRegion2D *region){CGPoint mean=CGPointZero;const CGPoint *points=region.normalizedPoints;NSUInteger count=region.pointCount;for(NSUInteger i=0;i<count;i++){mean.x+=points[i].x;mean.y+=points[i].y;}mean.x/=count;mean.y/=count;return CGPointMake((box.origin.x+mean.x*box.size.width)*image.pixelWidth,(1-box.origin.y-mean.y*box.size.height)*image.pixelHeight);};
          CGPoint a=center(leftEye),b=center(rightEye);
          if(diagnose)[eyeGeometry addObject:@{@"bbox":@[@(box.origin.x),@(box.origin.y),@(box.size.width),@(box.size.height)],@"observationRoll":observation.roll?:NSNull.null,@"leftEye":eyeMeans(leftEye,box,image),@"rightEye":eyeMeans(rightEye,box,image),@"currentLeftTopMean":@[@(a.x),@(a.y)],@"currentRightTopMean":@[@(b.x),@(b.y)]}];
          if(a.x>b.x)std::swap(a,b);
          double distance=std::hypot(b.x-a.x,b.y-a.y);
          if(distance<5)smallEyes++;
          else {
            double roll=std::atan2(b.y-a.y,b.x-a.x),cx=((a.x+b.x)*.5-std::sin(roll)*distance*.55)/image.pixelWidth,cy=((a.y+b.y)*.5+std::cos(roll)*distance*.55)/image.pixelHeight;
            primary=candidate(image,cx,cy,std::min(.5,.95*distance/image.pixelWidth),std::min(.5,1.35*distance/image.pixelHeight),roll*180/M_PI,@"vision-eyes");
            if(!primary)outsideFrame++;
          }
        }else missingEyes++;
        if(primary){if(bbox)primary[@"bboxFallback"]=bbox;[proposals addObject:primary];}
        else if(bbox)[proposals addObject:bbox];
      }
      NSMutableDictionary *parameters=[p mutableCopy];
      if(diagnose){
        NSMutableArray *frames=[NSMutableArray array];
        for(NSDictionary *face in proposals){NSMutableDictionary *frame=[candidateFrame(face,image) mutableCopy];if(face[@"bboxFallback"])frame[@"fallback"]=candidateFrame(face[@"bboxFallback"],image);[frames addObject:frame];}
        NSDictionary *details=@{@"imageWidth":@(image.pixelWidth),@"imageHeight":@(image.pixelHeight),@"imageOrientation":@(image.orientation),@"bitmapInfo":@((NSUInteger)CGImageGetBitmapInfo(cg)),@"visionFaceCount":@(request.results.count),@"visionConfidence":confidenceSamples,@"lowConfidence":@(lowConfidence),@"missingEyes":@(missingEyes),@"smallEyes":@(smallEyes),@"outsideFrame":@(outsideFrame),@"proposalCount":@(proposals.count),@"proposalFrames":frames,@"eyeGeometry":eyeGeometry,@"rasterMeanARGB":channelMeans(image,0,image.pixelHeight),@"rasterFirstRowMeanARGB":channelMeans(image,0,1),@"rasterLastRowMeanARGB":channelMeans(image,image.pixelHeight-1,1)};
        parameters[@"_visionDiagnostics"]=details;NSLog(@"HueviaRetouch stages %@",details);
      }
      return [HueviaPortraitInference analyze:parameters candidates:proposals image:image task:task];
    }
    NSString *mode=p[@"mode"],*facesJson=nil,*skin=nil,*body=nil,*foreground=nil;
    NSMutableArray *faces=[NSMutableArray array];
    if([mode isEqual:@"face"]||[mode isEqual:@"skin"]){
      VNDetectFaceLandmarksRequest *request=[VNDetectFaceLandmarksRequest new];run(request,cg,task);
      for(VNFaceObservation *observation in request.results){
        if(faces.count>=12)break;if(observation.confidence<.4)continue;CGRect r=observation.boundingBox;
        double cx=CGRectGetMidX(r),cy=1-CGRectGetMidY(r),rx=r.size.width*.5,ry=r.size.height*.5;
        int x=std::clamp(int(cx*image.pixelWidth),0,image.pixelWidth-1),y=std::clamp(int((cy+ry*.2)*image.pixelHeight),0,image.pixelHeight-1);uint32_t rgb=image.pixels[y*image.pixelWidth+x];
        [faces addObject:@{@"cx":@(cx),@"cy":@(cy),@"rx":@(rx),@"ry":@(ry),@"roll":@(-(observation.roll.doubleValue)*180/M_PI),@"skinR":@((rgb>>16)&255),@"skinG":@((rgb>>8)&255),@"skinB":@(rgb&255)}];
      }
      facesJson=json(faces);
      if([mode isEqual:@"skin"]){
        if(faces.count==0)fail(@"未识别到可取样的人脸。请手动添加人脸，或使用局部画笔处理皮肤。");
        // Vision identifies people; sampled chroma selects skin inside that real matte.
        // This is explicitly a sampled colour range, not a semantic skin model.
        std::vector<uint8_t> matte(128*128,255);
        if(@available(iOS 15.0,*)){
          VNGeneratePersonSegmentationRequest *segment=[VNGeneratePersonSegmentationRequest new];segment.qualityLevel=VNGeneratePersonSegmentationRequestQualityLevelAccurate;segment.outputPixelFormat=kCVPixelFormatType_OneComponent8;run(segment,cg,task);
          CVPixelBufferRef buffer=segment.results.firstObject.pixelBuffer;if(buffer){CVPixelBufferLockBaseAddress(buffer,kCVPixelBufferLock_ReadOnly);size_t w=CVPixelBufferGetWidth(buffer),h=CVPixelBufferGetHeight(buffer),stride=CVPixelBufferGetBytesPerRow(buffer);uint8_t *base=(uint8_t *)CVPixelBufferGetBaseAddress(buffer);for(int y=0;y<128;y++)for(int x=0;x<128;x++)matte[y*128+x]=base[std::min(h-1,size_t((y+.5)*h/128))*stride+std::min(w-1,size_t((x+.5)*w/128))];CVPixelBufferUnlockBaseAddress(buffer,kCVPixelBufferLock_ReadOnly);}
        }
        NSMutableData *mask=[NSMutableData dataWithLength:128*128];uint8_t *out=(uint8_t *)mask.mutableBytes;
        for(int y=0;y<128;y++){check(task);for(int x=0;x<128;x++){
          double nx=(x+.5)/128,ny=(y+.5)/128;uint32_t c=image.pixels[std::min(image.pixelHeight-1,int(ny*image.pixelHeight))*image.pixelWidth+std::min(image.pixelWidth-1,int(nx*image.pixelWidth))];double r=(c>>16)&255,g=(c>>8)&255,b=c&255,cb=128-.168736*r-.331264*g+.5*b,cr=128+.5*r-.418688*g-.081312*b,best=0;
          for(NSDictionary *f in faces){double sr=[f[@"skinR"] doubleValue],sg=[f[@"skinG"] doubleValue],sb=[f[@"skinB"] doubleValue],scb=128-.168736*sr-.331264*sg+.5*sb,scr=128+.5*sr-.418688*sg-.081312*sb,distance=std::hypot(cb-scb,cr-scr);double weight=std::clamp((30-distance)/18,0.0,1.0);double fx=(nx-[f[@"cx"] doubleValue])/[f[@"rx"] doubleValue],fy=(ny-[f[@"cy"] doubleValue])/[f[@"ry"] doubleValue];if(std::abs(fx)<.85&&((fy>-.55&&fy<-.15)||(fy>.35&&fy<.68)))weight=0;best=std::max(best,weight);}
          out[y*128+x]=uint8_t(std::round(matte[y*128+x]*best));
        }}skin=[mask base64EncodedStringWithOptions:0];
      }
    }else if([mode isEqual:@"body"]){
      VNDetectHumanRectanglesRequest *request=[VNDetectHumanRectanglesRequest new];request.upperBodyOnly=NO;run(request,cg,task);
      NSInteger selected=[p[@"person"] integerValue];if(selected<0||selected>=request.results.count)fail(@"未识别到完整人物，请手动调整塑形范围。");
      VNHumanObservation *person=request.results[selected];CGRect r=person.boundingBox;double left=std::max(0.0,r.origin.x),right=std::min(1.0,CGRectGetMaxX(r)),top=std::max(0.0,1-CGRectGetMaxY(r)+r.size.height*.2),bottom=std::min(.96,1-r.origin.y);
      if(right-left<.06||bottom-top<.14)fail(@"人物过小，请手动调整塑形范围。");body=json(@{@"left":@(left),@"right":@(right),@"top":@(top),@"bottom":@(bottom)});
      if(@available(iOS 15.0,*)){VNGeneratePersonSegmentationRequest *segment=[VNGeneratePersonSegmentationRequest new];segment.qualityLevel=VNGeneratePersonSegmentationRequestQualityLevelAccurate;segment.outputPixelFormat=kCVPixelFormatType_OneComponent8;run(segment,cg,task);CVPixelBufferRef buffer=segment.results.firstObject.pixelBuffer;if(buffer){NSMutableData *data=[NSMutableData dataWithLength:128*128];uint8_t *out=(uint8_t *)data.mutableBytes;CVPixelBufferLockBaseAddress(buffer,kCVPixelBufferLock_ReadOnly);size_t w=CVPixelBufferGetWidth(buffer),h=CVPixelBufferGetHeight(buffer),stride=CVPixelBufferGetBytesPerRow(buffer);uint8_t *base=(uint8_t *)CVPixelBufferGetBaseAddress(buffer);for(int y=0;y<128;y++)for(int x=0;x<128;x++)out[y*128+x]=base[std::min(h-1,size_t((y+.5)*h/128))*stride+std::min(w-1,size_t((x+.5)*w/128))];CVPixelBufferUnlockBaseAddress(buffer,kCVPixelBufferLock_ReadOnly);foreground=[data base64EncodedStringWithOptions:0];}}
    }else fail(@"请选择人脸、皮肤或身体分析。");
    if(foreground.length){IOSIntArray *pixels=[IOSIntArray arrayWithLength:image.pixelWidth*image.pixelHeight];for(int i=0;i<pixels.length;i++)*IOSIntArray_GetRef(pixels,i)=(jint)image.pixels[i];foreground=[CcHueviaSharedSharedPortraitInference backgroundWithIntArray:pixels withInt:image.pixelWidth withInt:image.pixelHeight withNSString:foreground withJavaUtilFunctionBooleanSupplier:task];}
    result=[CcHueviaSharedSharedRetouch analysisWithNSString:input withNSString:facesJson withNSString:skin withNSString:body withNSString:foreground withJavaUtilFunctionBooleanSupplier:task];
    NSMutableDictionary *value=[decoded(result) mutableCopy];value[@"analysisEngine"]=@"Vision";value[@"skinMode"]=@"sampled-chroma-with-person-matte";return value;
  }@finally{CGImageRelease(cg);}
}
@end
