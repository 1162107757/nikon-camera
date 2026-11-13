// Standalone CoreGraphics/Vision geometry probe. No Flutter, JRE, model or photo dump.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>
#import <Vision/Vision.h>
#include <algorithm>
#include <cmath>
#include <vector>
#include <cstdio>

namespace {
void fail(NSString *message){@throw [NSException exceptionWithName:@"PortraitProbe" reason:message userInfo:nil];}
NSArray *point(CGPoint p){return @[@(p.x),@(p.y)];}
CGPoint repeatedMean(VNFaceLandmarkRegion2D *region){CGPoint p=CGPointZero;for(NSUInteger i=0;i<region.pointCount;i++){p.x+=region.normalizedPoints[i].x;p.y+=region.normalizedPoints[i].y;}p.x/=region.pointCount;p.y/=region.pointCount;return p;}
CGPoint topMean(CGPoint p,CGRect box,size_t w,size_t h){return CGPointMake((box.origin.x+p.x*box.size.width)*w,(1-box.origin.y-p.y*box.size.height)*h);}
NSDictionary *eye(VNFaceLandmarkRegion2D *region,CGRect box,size_t w,size_t h){
    if(!region||!region.pointCount)return @{@"pointCount":@0};
    CGPoint repeated=repeatedMean(region),cached=CGPointZero;NSUInteger count=region.pointCount;const CGPoint *points=region.normalizedPoints;
    if(!points)fail(@"No normalized points");for(NSUInteger i=0;i<count;i++){cached.x+=points[i].x;cached.y+=points[i].y;}cached.x/=count;cached.y/=count;
    const CGPoint *absolute=[region pointsInImageOfSize:CGSizeMake(w,h)];CGPoint native=CGPointZero;
    if(!absolute)fail(@"No image points");for(NSUInteger i=0;i<count;i++){native.x+=absolute[i].x;native.y+=absolute[i].y;}native.x/=count;native.y/=count;
    return @{@"pointCount":@(count),@"pointStructBytes":@(sizeof(points[0])),@"repeatedNormalizedMean":point(repeated),@"cachedNormalizedMean":point(cached),@"repeatedTopMean":point(topMean(repeated,box,w,h)),@"cachedTopMean":point(topMean(cached,box,w,h)),@"nativeImageMean":point(native),@"nativeTopMean":point(CGPointMake(native.x,h-native.y))};
}
NSDictionary *frame(NSArray *left,NSArray *right,size_t w,size_t h){
    CGPoint a=CGPointMake([left[0] doubleValue],[left[1] doubleValue]),b=CGPointMake([right[0] doubleValue],[right[1] doubleValue]);if(a.x>b.x)std::swap(a,b);
    double distance=std::hypot(b.x-a.x,b.y-a.y),angle=std::atan2(b.y-a.y,b.x-a.x);
    return @{@"cx":@(((a.x+b.x)*.5-std::sin(angle)*distance*.55)/w),@"cy":@(((a.y+b.y)*.5+std::cos(angle)*distance*.55)/h),@"rx":@(std::min(.5,.95*distance/w)),@"ry":@(std::min(.5,1.35*distance/h)),@"roll":@(angle*180/M_PI),@"eyeDistancePixels":@(distance)};
}
NSDictionary *analyze(CGImageRef image,BOOL cpu){
    VNDetectFaceLandmarksRequest *request=[VNDetectFaceLandmarksRequest new];request.usesCPUOnly=cpu;
    NSError *error=nil;VNImageRequestHandler *handler=[[VNImageRequestHandler alloc] initWithCGImage:image options:@{}];if(![handler performRequests:@[request] error:&error])fail(error.localizedDescription?:@"Vision request failed");
    NSMutableArray *faces=[NSMutableArray array];size_t w=CGImageGetWidth(image),h=CGImageGetHeight(image);
    for(VNFaceObservation *observation in request.results){
        CGRect box=observation.boundingBox;NSDictionary *left=eye(observation.landmarks.leftEye,box,w,h),*right=eye(observation.landmarks.rightEye,box,w,h);
        NSMutableDictionary *row=[@{@"confidence":@(observation.confidence),@"bbox":@[@(box.origin.x),@(box.origin.y),@(box.size.width),@(box.size.height)],@"observationRoll":observation.roll?:NSNull.null,@"leftEye":left,@"rightEye":right} mutableCopy];
        if([left[@"pointCount"] unsignedIntegerValue]&&[right[@"pointCount"] unsignedIntegerValue]){row[@"currentFrame"]=frame(left[@"repeatedTopMean"],right[@"repeatedTopMean"],w,h);row[@"cachedFrame"]=frame(left[@"cachedTopMean"],right[@"cachedTopMean"],w,h);row[@"nativeImageFrame"]=frame(left[@"nativeTopMean"],right[@"nativeTopMean"],w,h);}
        [faces addObject:row];
    }
    return @{@"cpuOnly":@(cpu),@"requestRevision":@(request.revision),@"faceCount":@(faces.count),@"faces":faces};
}
}
int main(int argc,char **argv){@autoreleasepool{
    @try {
        if(argc!=2)fail(@"Pass the fixed portrait JPEG path");NSString *path=[NSString stringWithUTF8String:argv[1]];
        CGImageSourceRef source=CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path],NULL);if(!source)fail(@"Image source unavailable");
        CGImageRef original=CGImageSourceCreateThumbnailAtIndex(source,0,(__bridge CFDictionaryRef)@{(__bridge id)kCGImageSourceCreateThumbnailFromImageAlways:@YES,(__bridge id)kCGImageSourceCreateThumbnailWithTransform:@NO,(__bridge id)kCGImageSourceShouldCacheImmediately:@YES,(__bridge id)kCGImageSourceThumbnailMaxPixelSize:@1280});CFRelease(source);if(!original)fail(@"Decode unavailable");
        size_t w=CGImageGetWidth(original),h=CGImageGetHeight(original);std::vector<uint32_t> pixels(w*h);CGColorSpaceRef color=CGColorSpaceCreateWithName(kCGColorSpaceSRGB);CGBitmapInfo info=kCGBitmapByteOrder32Little|kCGImageAlphaPremultipliedFirst;
        CGContextRef context=CGBitmapContextCreate(pixels.data(),w,h,8,w*4,color,info);if(!context)fail(@"Bitmap context unavailable");CGContextDrawImage(context,CGRectMake(0,0,w,h),original);CGContextRelease(context);
        CGDataProviderRef provider=CGDataProviderCreateWithData(NULL,pixels.data(),pixels.size()*4,NULL);CGImageRef raster=CGImageCreate(w,h,8,32,w*4,color,info,provider,NULL,true,kCGRenderingIntentDefault);CGDataProviderRelease(provider);CGColorSpaceRelease(color);if(!raster)fail(@"Raster image unavailable");
        NSDictionary *report=@{@"schema":@1,@"osVersion":NSProcessInfo.processInfo.operatingSystemVersionString,@"imageWidth":@(w),@"imageHeight":@(h),@"cgFloatBytes":@(sizeof(CGFloat)),@"directDefault":analyze(original,NO),@"rasterDefault":analyze(raster,NO),@"rasterCPU":analyze(raster,YES)};
        NSData *data=[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:nil];if(!data)fail(@"Non-finite geometry output");puts([[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding].UTF8String);CGImageRelease(raster);CGImageRelease(original);return 0;
    }@catch(NSException *error){fprintf(stderr,"Portrait geometry probe failed: %s\n",error.reason.UTF8String);return 1;}
}}
