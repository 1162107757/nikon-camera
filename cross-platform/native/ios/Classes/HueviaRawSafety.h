// H2 opponent-colour transform adapted from LibRaw 0.22.3.
// Copyright 2019-2025 LibRaw LLC (info@libraw.org).
// Available under LGPL 2.1 or CDDL 1.0, as in the bundled LibRaw notices.
// Huevia changes: preserve zero chroma, clamp conversions and fixed-white EV.
#pragma once
#include <algorithm>
#include <cmath>
#include <stdexcept>

class HueviaRawProcessor : public LibRaw {
public:
    using LibRaw::LibRaw;
    libraw_callbacks_t &processingCallbacks(){return callbacks;}
};

// LibRaw 0.22.3 H2 divides 0/0 for an achromatic clipped pixel. Keep the
// original opponent-colour blend, explicitly preserving its achromatic limit.
// A callback avoids modifying/replacing the preserved LibRaw libraries.
inline void hueviaBlendHighlights(void *context) {
    auto &raw=*static_cast<HueviaRawProcessor *>(context);auto &d=raw.imgdata;auto &callbacks=raw.processingCallbacks();
    const int colors=d.idata.colors;if(colors!=3&&colors!=4)return;
    const float trans[2][4][4]={{{1,1,1},{1.7320508f,-1.7320508f,0},{-1,-1,2}},{{1,1,1,1},{1,-1,1,-1},{1,1,-1,-1},{1,-1,-1,1}}};
    const float inverse[2][4][4]={{{1,.8660254f,-.5f},{1,-.8660254f,-.5f},{1,0,1}},{{1,1,1,1},{1,-1,1,-1},{1,1,-1,-1},{1,-1,-1,1}}};
    int clip=65535;for(int c=0;c<colors;c++)clip=std::min(clip,int(65535.f*d.color.pre_mul[c]));
    const int transform=colors-3;
    for(int y=0;y<d.sizes.height;y++){
        if((y&31)==0&&callbacks.progress_cb&&callbacks.progress_cb(callbacks.progresscb_data,LIBRAW_PROGRESS_HIGHLIGHTS,y,d.sizes.height))throw std::runtime_error("RAW development cancelled");
        for(int x=0;x<d.sizes.width;x++){
            auto &pixel=d.image[size_t(y)*d.sizes.width+x];bool clipped=false;for(int c=0;c<colors;c++)clipped|=pixel[c]>clip;if(!clipped)continue;
            float lab[2][4]={},energy[2]={};
            for(int i=0;i<2;i++){
                for(int c=0;c<colors;c++)for(int j=0;j<colors;j++)lab[i][c]+=int(trans[transform][c][j]*(i==0?pixel[j]:std::min(int(pixel[j]),clip)));
                for(int c=1;c<colors;c++)energy[i]+=lab[i][c]*lab[i][c];
            }
            // Zero chroma needs no correction; the original lightness is valid.
            if(energy[0]<=0)continue;
            const float ratio=std::sqrt(energy[1]/energy[0]);
            for(int c=1;c<colors;c++)lab[0][c]*=ratio;
            for(int c=0;c<colors;c++){float value=0;for(int j=0;j<colors;j++)value+=inverse[transform][c][j]*lab[0][j];value/=colors;pixel[c]=static_cast<unsigned short>(std::clamp(value,0.f,65535.f));}
        }
    }
}

inline void hueviaRawSafety(HueviaRawProcessor &raw,int exposureTenths,int highlights){
    auto &p=raw.imgdata.params;
    p.no_auto_bright=1;p.adjust_maximum_thr=0;
    // exp_bef changes the sensor white level before scaling. Apply the user's
    // EV once in the output transfer instead, preserving a fixed sensor white.
    p.exp_correc=0;p.exp_shift=1;p.exp_preser=0;p.bright=float(std::pow(2.,exposureTenths/10.));
    if(highlights==2){p.highlight=1;raw.processingCallbacks().post_interpolate_cb=hueviaBlendHighlights;}
}
