#include <libraw/libraw.h>
#include "HueviaRawSafety.h"
#include <cstdio>
#include <memory>
#include <stdexcept>
int main(int argc,char **argv){
  try{for(int i=1;i<argc;i++){
    double previous=-1;int expectedWidth=0,expectedHeight=0;
    for(int ev:{0,10,30}){
      auto raw=std::make_unique<HueviaRawProcessor>(LIBRAW_OPTIONS_NO_DATAERR_CALLBACK);
      auto &p=raw->imgdata.params;p.half_size=0;p.output_bps=8;p.output_color=1;p.user_qual=3;p.highlight=2;p.use_camera_matrix=3;p.use_camera_wb=1;p.gamm[0]=1/2.4;p.gamm[1]=12.92;p.use_fuji_rotate=1;p.no_interpolation=0;p.no_auto_scale=0;
      hueviaRawSafety(*raw,ev,2);raw->imgdata.rawparams.max_raw_memory_mb=512;
      int code=raw->open_file(argv[i]);if(code)throw std::runtime_error(LibRaw::strerror(code));
      if((code=raw->unpack())||(code=raw->dcraw_process()))throw std::runtime_error(LibRaw::strerror(code));
      int error=0;std::unique_ptr<libraw_processed_image_t,void(*)(libraw_processed_image_t*)> pixels(raw->dcraw_make_mem_image(&error),LibRaw::dcraw_clear_mem);
      if(!pixels||error||pixels->bits!=8||pixels->colors!=3)throw std::runtime_error("Unexpected RGB output");
      if(!expectedWidth){expectedWidth=pixels->width;expectedHeight=pixels->height;}
      if(pixels->width!=expectedWidth||pixels->height!=expectedHeight)throw std::runtime_error("Exposure changed geometry");
      double total=0;size_t white=0,black=0,count=size_t(pixels->width)*pixels->height;
      for(size_t n=0;n<count;n++){const auto *rgb=pixels->data+3*n;total+=.2126*rgb[0]+.7152*rgb[1]+.0722*rgb[2];white+=rgb[0]>245&&rgb[1]>245&&rgb[2]>245;black+=rgb[0]<3&&rgb[1]<3&&rgb[2]<3;}
      double mean=total/count;if(mean+0.5<previous)throw std::runtime_error("EV decreased image brightness");previous=mean;
      std::printf("NEF %d %s %s EV=%+.1f %dx%d mean=%.4f white=%zu black=%zu\n",i,raw->imgdata.idata.make,raw->imgdata.idata.model,ev/10.,expectedWidth,expectedHeight,mean,white,black);std::fflush(stdout);
    }
  }std::puts("PASS real NEF neutral development at 0/+1/+3 EV; geometry and monotonic brightness");return 0;
  }catch(const std::exception &error){std::fprintf(stderr,"FAIL %s\n",error.what());return 1;}
}
