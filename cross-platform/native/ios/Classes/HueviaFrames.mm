#import "HueviaFrames.h"
#import <UIKit/UIKit.h>
#import <CoreText/CoreText.h>
#import "IOSPrimitiveArray.h"
#import "java/io/IOException.h"
#include <algorithm>
#include <vector>

namespace {
void draw(CGContextRef context,CGImageRef image,CGRect rect){CGContextSaveGState(context);CGContextTranslateCTM(context,rect.origin.x,rect.origin.y+rect.size.height);CGContextScaleCTM(context,1,-1);CGContextDrawImage(context,CGRectMake(0,0,rect.size.width,rect.size.height),image);CGContextRestoreGState(context);}
void text(NSString *value,CGFloat x,CGFloat baseline,CGFloat size,CGFloat max,UIColor *color,BOOL bold,NSString *face=nil){
  if(!value.length||max<=0)return;
  UIFont *font=face?[UIFont fontWithName:face size:size]:[UIFont systemFontOfSize:size weight:bold?UIFontWeightBold:UIFontWeightRegular];
  CGFloat width=[value sizeWithAttributes:@{NSFontAttributeName:font}].width;
  if(width>max)font=[font fontWithSize:size*max/width];
  [value drawAtPoint:CGPointMake(x,baseline-font.ascender) withAttributes:@{NSFontAttributeName:font,NSForegroundColorAttributeName:color}];
}
NSBundle *assets(){NSURL *url=[NSBundle.mainBundle URLForResource:@"HueviaNativeAssets" withExtension:@"bundle"];if(!url)url=[[NSBundle bundleForClass:HueviaFrames.class] URLForResource:@"HueviaNativeAssets" withExtension:@"bundle"];return url?[NSBundle bundleWithURL:url]:nil;}
CGFloat brand(CGContextRef context,CcHueviaNcpPhotoBorder *b,CcHueviaSharedSharedCaptureInfo *info,CGFloat x,CGFloat y,CGFloat height,BOOL white,CGFloat max){
  NSString *name=[info brandWithCcHueviaNcpPhotoBorder:b];if(!name.length)return 0;
  if([name isEqualToString:@"NIKON"]){
    NSString *file=b->logo_==1?@"nikon-yellow-square":b->logo_==2?@"nikon-wordmark-white":b->logo_==3?@"nikon-wordmark-black":white?@"nikon-wordmark-white":@"nikon-yellow-square";
    NSURL *url=[assets() URLForResource:file withExtension:@"png"];
    UIImage *image=url?[UIImage imageWithContentsOfFile:url.path]:nil;
    if(!image)@throw [[JavaIoIOException alloc] initWithNSString:@"边框标识素材尚未就绪。"];
    CGFloat width=height*image.size.width/image.size.height;if(width>max){CGFloat h=height*max/width;y+=(height-h)/2;height=h;width=max;}
    draw(context,image.CGImage,CGRectMake(x,y,width,height));return width;
  }
  NSString *label=[name isEqualToString:@"CANON"]?@"Canon":name;
  UIFont *font=[UIFont boldSystemFontOfSize:height];CGFloat width=[label sizeWithAttributes:@{NSFontAttributeName:font}].width;
  if(width>max){height*=max/width;width=max;font=[UIFont boldSystemFontOfSize:height];}
  [label drawAtPoint:CGPointMake(x,y+(height-font.lineHeight)/2) withAttributes:@{NSFontAttributeName:font,NSForegroundColorAttributeName:white?UIColor.whiteColor:UIColor.blackColor}];return width;
}
void box(uint32_t *pixels,int width,int height,int radius){
  std::vector<uint32_t> temporary(size_t(width)*height);
  for(int axis=0;axis<2;axis++){
    int length=axis==0?width:height,lines=axis==0?height:width;
    for(int line=0;line<lines;line++){
      int64_t red=0,green=0,blue=0;
      for(int k=-radius;k<=radius;k++){int pos=std::clamp(k,0,length-1);uint32_t v=pixels[axis==0?line*width+pos:pos*width+line];red+=(v>>16)&255;green+=(v>>8)&255;blue+=v&255;}
      for(int j=0;j<length;j++){
        int count=2*radius+1;temporary[axis==0?line*width+j:j*width+line]=0xff000000U|uint32_t(red/count)<<16|uint32_t(green/count)<<8|uint32_t(blue/count);
        int old=std::max(0,j-radius),next=std::min(length-1,j+radius+1);uint32_t v=pixels[axis==0?line*width+old:old*width+line],n=pixels[axis==0?line*width+next:next*width+line];red+=int((n>>16)&255)-int((v>>16)&255);green+=int((n>>8)&255)-int((v>>8)&255);blue+=int(n&255)-int(v&255);
      }
    }
    std::copy(temporary.begin(),temporary.end(),pixels);
  }
}
void background(CGContextRef context,HueviaRaster *photo,CcHueviaNcpPhotoBorder *b,CGFloat width,CGFloat height,NSString *root){
  int w=photo.pixelWidth,h=photo.pixelHeight,sw=w>=h?144:std::max(2,int(std::lround(144.0*w/h))),sh=h>=w?144:std::max(2,int(std::lround(144.0*h/w)));
  HueviaRaster *sample=[[HueviaRaster alloc] initWithWidth:sw height:sh root:root];CGContextRef small=[sample newContext];CGImageRef image=[photo newImage];CGContextSetInterpolationQuality(small,kCGInterpolationHigh);CGContextDrawImage(small,CGRectMake(0,0,sw,sh),image);CGImageRelease(image);CGContextRelease(small);
  if(b->blur_>0){int radius=std::max(1,int(std::lround(10*b->blur_/100.0)));for(int i=0;i<3;i++)box(sample.pixels,sw,sh,radius);}
  CGFloat scale=std::max(width/sw,height/sh),bw=sw*scale,bh=sh*scale;CGImageRef blurred=[sample newImage];draw(context,blurred,CGRectMake((width-bw)/2,(height-bh)/2,bw,bh));CGImageRelease(blurred);
}
}
@implementation HueviaFrames
+ (HueviaRaster *)apply:(HueviaRaster *)photo border:(CcHueviaNcpPhotoBorder *)b capture:(CcHueviaSharedSharedCaptureInfo *)info root:(NSString *)root task:(HueviaTask *)task {
  if([b isNone])return photo;if(task.cancelled)@throw [[JavaIoIOException alloc] initWithNSString:@"边框处理已取消。"];
  int w=photo.pixelWidth,h=photo.pixelHeight;IOSIntArray *size=[b dimensionsWithInt:w withInt:h];
  HueviaRaster *output=[[HueviaRaster alloc] initWithWidth:size->buffer_[0] height:size->buffer_[1] root:root];
  CGContextRef context=[output newContext];CGContextTranslateCTM(context,0,output.pixelHeight);CGContextScaleCTM(context,1,-1);UIGraphicsPushContext(context);
  @try {
    CGImageRef image=[photo newImage];CGFloat m=b->margin_/100.0;
    if(b->template_==3){
      CGContextSetRGBFillColor(context,1,1,1,1);CGContextFillRect(context,CGRectMake(0,0,output.pixelWidth,output.pixelHeight));draw(context,image,CGRectMake(0,0,w,h));
      CGFloat fh=output.pixelHeight-h,first=h+fh*.43,second=h+fh*.76;
      text([info companyWithCcHueviaNcpPhotoBorder:b],w*.04,first,w*.024,w*.51,UIColor.blackColor,YES);
      if([b showsWithInt:0])text([info modelWithCcHueviaNcpPhotoBorder:b],w*.04,second,w*.018,w*.51,[UIColor colorWithWhite:.467 alpha:1],NO);
      CGFloat logoHeight=fh*.40;NSString *maker=[info brandWithCcHueviaNcpPhotoBorder:b];if([maker isEqualToString:@"NIKON"]&&(b->logo_==2||b->logo_==3))logoHeight=w*.042/3.612;
      brand(context,b,info,w*.606,h+fh*.50-logoHeight/2,logoHeight,NO,w*.045);
      if(maker.length){CGContextSetRGBStrokeColor(context,.835,.835,.835,1);CGContextSetLineWidth(context,std::max(1.0,w*.0006));CGContextMoveToPoint(context,w*.664,h+fh*.24);CGContextAddLineToPoint(context,w*.664,h+fh*.78);CGContextStrokePath(context);}
      text([info parametersWithCcHueviaNcpPhotoBorder:b],w*.68,first,w*.023,w*.28,UIColor.blackColor,YES);
      if([b showsWithInt:5])text([info fieldWithCcHueviaNcpPhotoBorder:b withInt:4],w*.68,second,w*.020,w*.28,[UIColor colorWithWhite:.467 alpha:1],NO);
    }else{
      background(context,photo,b,output.pixelWidth,output.pixelHeight,root);
      CGFloat x=b->template_==1?(output.pixelWidth-w)/2.0:output.pixelWidth-w-w*.08*m,y=w*(b->template_==1?.06:.07)*m,radius=w*.025*b->corner_/100;
      CGRect rect=CGRectMake(x,y,w,h);CGPathRef clip=CGPathCreateWithRoundedRect(rect,radius,radius,NULL);
      if(b->shadow_>0){CGContextSaveGState(context);CGContextSetShadowWithColor(context,CGSizeMake(0,w*.014),w*.025*b->shadow_/100,[UIColor colorWithWhite:0 alpha:.69].CGColor);CGContextSetRGBFillColor(context,0,0,0,.6);CGContextAddPath(context,clip);CGContextFillPath(context);CGContextRestoreGState(context);}
      CGContextSaveGState(context);CGContextAddPath(context,clip);CGContextClip(context);draw(context,image,rect);CGContextRestoreGState(context);CGPathRelease(clip);
      if(b->template_==1){
        CGFloat logoHeight=w*.027*m,baseline=y+h+w*.048*m;NSString *model=[b showsWithInt:0]?[info modelWithCcHueviaNcpPhotoBorder:b]:@"",*maker=[info brandWithCcHueviaNcpPhotoBorder:b];
        UIFont *font=[UIFont systemFontOfSize:w*.021*m];CGFloat modelWidth=std::min(w*.58,[model sizeWithAttributes:@{NSFontAttributeName:font}].width);
        CGFloat logoWidth=!maker.length?0:[maker isEqualToString:@"NIKON"]?(b->logo_==1?logoHeight:logoHeight*(1600.0/443)):std::min(w*.25,[maker sizeWithAttributes:@{NSFontAttributeName:[UIFont boldSystemFontOfSize:logoHeight]}].width);
        CGFloat gap=!model.length||logoWidth==0?0:w*.02,start=(output.pixelWidth-logoWidth-gap-modelWidth)/2;
        brand(context,b,info,start,baseline-logoHeight,logoHeight,YES,w*.25);text(model,start+logoWidth+gap,baseline,w*.021*m,w*.58,UIColor.whiteColor,NO);
        NSString *line=[info parametersWithCcHueviaNcpPhotoBorder:b];CGFloat lineWidth=std::min(w*.82,[line sizeWithAttributes:@{NSFontAttributeName:[UIFont systemFontOfSize:w*.018*m]}].width);text(line,(output.pixelWidth-lineWidth)/2,baseline+w*.028*m,w*.018*m,w*.82,UIColor.whiteColor,NO);
      }else{
        brand(context,b,info,w*.085*m,y+h*.16,w*.049*m,YES,x-w*.125*m);
        NSString *names[3]={@"F",@"ISO",@"S"};int fields[3]={1,3,2};
        for(int row=0;row<3;row++){
          int field=fields[row];NSString *value=[info fieldWithCcHueviaNcpPhotoBorder:b withInt:field];if(![b showsWithInt:field+1]||!value.length)continue;
          if(field==1&&[value.uppercaseString hasPrefix:@"F"])value=[value substringFromIndex:1];if(field==3&&[value.uppercaseString hasPrefix:@"ISO"])value=[value substringFromIndex:3];if(field==2&&[value hasSuffix:@"s"])value=[value substringToIndex:value.length-1];
          CGFloat top=y+h*(.46+row*.175),left=w*.09*m,bw=w*.09*m,bh=w*.047*m;CGRect badge=CGRectMake(left,top,bw,bh);UIBezierPath *path=[UIBezierPath bezierPathWithRoundedRect:badge cornerRadius:w*.009*m];[UIColor.whiteColor setStroke];path.lineWidth=w*.0033*m;[path stroke];CGFloat labelWidth=[names[row] sizeWithAttributes:@{NSFontAttributeName:[UIFont boldSystemFontOfSize:w*.022*m]}].width;text(names[row],left+(bw-labelWidth)/2,top+bh*.69,w*.022*m,bw,UIColor.whiteColor,YES);text(value,left+bw+w*.045*m,top+bh*.7,w*.027*m,x-left-bw-w*.06*m,UIColor.whiteColor,YES);
        }
      }
    }
    CGImageRelease(image);
  }@finally{UIGraphicsPopContext();CGContextRelease(context);}
  return output;
}
@end
