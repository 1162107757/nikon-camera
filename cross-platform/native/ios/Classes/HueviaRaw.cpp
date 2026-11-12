#include "HueviaRaw.h"
#include <libraw/libraw.h>
#include "HueviaRawSafety.h"
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <cstdlib>
#include <memory>
#include <stdexcept>
#include <string>

namespace {
// Generated from the preserved Android bridge, with JNI error reporting adapted
// to exceptions. The illuminant/matrix math is identical on the two hosts.
#include "HueviaWhiteBalance.inc"
void bounded(int width,int height){if(width<1||height<1||width>65535||height>65535||uint64_t(width)*height>60000000)throw std::runtime_error("RAW image exceeds the 60 megapixel limit");}
void checked(int code,const char *stage){if(code!=LIBRAW_SUCCESS)throw std::runtime_error(std::string(stage)+": "+LibRaw::strerror(code));}
void message(char *output,int capacity,const char *text){if(output&&capacity>0)std::snprintf(output,size_t(capacity),"%s",text);}
struct Callback {HueviaRawProgress progress;void *context;};
int report(void *opaque,LibRaw_progress stage,int iteration,int expected){auto *cb=static_cast<Callback *>(opaque);if(!cb->progress)return 0;unsigned flags=unsigned(stage);int index=0;while(flags>1){flags>>=1;index++;}double local=expected>0?std::clamp(iteration/double(expected),0.0,1.0):0;return cb->progress(cb->context,.025+.80*std::min(1.0,(index+local)/20.0));}
void dimensions(LibRaw &raw,int &width,int &height,int &colors,int &bits){raw.get_mem_image_format(&width,&height,&colors,&bits);bounded(width,height);}
}
extern "C" const char *HueviaRawVersion(){return LibRaw::version();}
extern "C" int HueviaRawEmbeddedJpeg(const char *path,uint8_t **bytes,int *length){
  if(!bytes||!length)return -1;*bytes=nullptr;*length=0;
  try{
    auto storage=std::make_unique<HueviaRawProcessor>(LIBRAW_OPTIONS_NO_DATAERR_CALLBACK);auto &raw=*storage;raw.imgdata.rawparams.max_raw_memory_mb=512;
    if(raw.open_file(path)!=LIBRAW_SUCCESS||raw.imgdata.thumbnail.tlength>16*1024*1024||raw.unpack_thumb()!=LIBRAW_SUCCESS)return -1;
    int error=0;std::unique_ptr<libraw_processed_image_t,void(*)(libraw_processed_image_t*)> image(raw.dcraw_make_mem_thumb(&error),LibRaw::dcraw_clear_mem);
    if(!image||error!=LIBRAW_SUCCESS||image->type!=LIBRAW_IMAGE_JPEG||image->data_size<4||image->data_size>16*1024*1024)return -1;
    *bytes=static_cast<uint8_t *>(std::malloc(image->data_size));if(!*bytes)return -1;std::memcpy(*bytes,image->data,image->data_size);*length=int(image->data_size);return 0;
  }catch(...){return -1;}
}
extern "C" int HueviaRawInspect(const char *path,HueviaRawInfo *info,char *error,int capacity){
  try{
    if(!path||!info)throw std::runtime_error("Missing RAW input");
    // LibRaw's large inline metadata exceeds a GCD worker's stack allowance.
    auto storage=std::make_unique<HueviaRawProcessor>(LIBRAW_OPTIONS_NO_DATAERR_CALLBACK);auto &raw=*storage;raw.imgdata.rawparams.max_raw_memory_mb=512;raw.imgdata.params.half_size=0;raw.imgdata.params.output_bps=8;
    checked(raw.open_file(path),"RAW open failed");int width,height,colors,bits;dimensions(raw,width,height,colors,bits);
    *info={};info->width=width;info->height=height;info->rawWidth=raw.imgdata.sizes.raw_width;info->rawHeight=raw.imgdata.sizes.raw_height;
    unsigned maximum=raw.imgdata.color.maximum;while(maximum){info->bits++;maximum>>=1;}if(!info->bits)info->bits=16;
    static const int orientations[8]={1,2,4,3,5,8,6,7};int flip=raw.imgdata.sizes.flip;info->exifOrientation=flip>=0&&flip<8?orientations[flip]:1;
    std::snprintf(info->make,sizeof(info->make),"%s",raw.imgdata.idata.make);std::snprintf(info->model,sizeof(info->model),"%s",raw.imgdata.idata.model);return 0;
  }catch(const std::exception &failure){message(error,capacity,failure.what());return -1;}catch(...){message(error,capacity,"RAW inspection failed");return -1;}
}
extern "C" int HueviaRawDevelop(const char *path,const HueviaRawSettings *settings,uint32_t *argb,int requestedWidth,int requestedHeight,HueviaRawProgress progress,void *context,char *error,int capacity){
  try{
    if(!path||!settings||!argb)throw std::runtime_error("Missing RAW development input");const auto &s=*settings;
    if(s.whiteBalance<0||s.whiteBalance>2||s.kelvin<2000||s.kelvin>12000||s.tint< -100||s.tint>100||s.exposureTenths< -50||s.exposureTenths>50||s.highlights<0||s.highlights>9||(s.quality!=0&&s.quality!=3))throw std::runtime_error("Invalid RAW settings");
    if(progress&&progress(context,0))throw std::runtime_error("RAW development cancelled");
    auto storage=std::make_unique<HueviaRawProcessor>(LIBRAW_OPTIONS_NO_DATAERR_CALLBACK);auto &raw=*storage;raw.imgdata.rawparams.max_raw_memory_mb=512;Callback callback{progress,context};raw.set_progress_handler(report,&callback);
    auto &p=raw.imgdata.params;p.half_size=0;p.output_bps=8;p.output_color=1;p.no_auto_bright=1;p.user_qual=s.quality;p.highlight=s.highlights;p.use_camera_matrix=3;p.gamm[0]=1/2.4;p.gamm[1]=12.92;p.use_fuji_rotate=1;p.no_interpolation=0;p.no_auto_scale=0;
    hueviaRawSafety(raw,s.exposureTenths,s.highlights);
    checked(raw.open_file(path),"RAW open failed");int width,height,colors,bits;dimensions(raw,width,height,colors,bits);sharedWhiteBalance(raw,s.whiteBalance,s.kelvin,s.tint);
    checked(raw.unpack(),"RAW unpack failed");checked(raw.dcraw_process(),"RAW demosaic/color processing failed");dimensions(raw,width,height,colors,bits);
    if(width!=requestedWidth||height!=requestedHeight||bits!=8||(colors!=1&&colors!=3))throw std::runtime_error("RAW output dimensions or colour format changed");
    checked(raw.copy_mem_image(argb,width*4,0),"RAW pixel transfer failed");
    for(int y=0;y<height;y++){
      if((y&31)==0&&progress&&progress(context,.85+.04*y/double(height)))throw std::runtime_error("RAW development cancelled");
      auto *row=reinterpret_cast<uint8_t *>(argb+size_t(y)*width);
      for(int x=width-1;x>=0;x--){uint8_t r=row[x*colors],g=colors==1?r:row[x*colors+1],b=colors==1?r:row[x*colors+2];argb[size_t(y)*width+x]=0xff000000U|uint32_t(r)<<16|uint32_t(g)<<8|b;}
    }
    // LibRaw is destroyed before the subsequent shared filter/colour pipeline.
    return 0;
  }catch(const std::bad_alloc &){message(error,capacity,"Not enough memory for RAW development");return -1;}catch(const std::exception &failure){message(error,capacity,failure.what());return -1;}catch(...){message(error,capacity,"RAW development failed");return -1;}
}
