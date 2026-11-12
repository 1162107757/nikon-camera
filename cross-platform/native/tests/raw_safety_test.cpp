#include <libraw/libraw.h>
#include "HueviaRawSafety.h"
#include <cstdio>
#include <cstdlib>
#include <memory>
class Probe : public HueviaRawProcessor {public:using LibRaw::blend_highlights;};
int main(){
    auto raw=std::make_unique<Probe>();auto &d=raw->imgdata;
    d.sizes.width=4096;d.sizes.height=1;d.idata.colors=3;
    d.image=static_cast<unsigned short (*)[4]>(std::calloc(4096,sizeof(*d.image)));
    d.color.pre_mul[0]=.5;d.color.pre_mul[1]=1;d.color.pre_mul[2]=.5;d.color.pre_mul[3]=1;
    for(int x=0;x<4096;x++)for(int c=0;c<3;c++)d.image[x][c]=static_cast<unsigned short>(x*16);
    raw->blend_highlights();std::printf("Unmodified LibRaw H2 saturated grey: %u/%u/%u\n",d.image[3500][0],d.image[3500][1],d.image[3500][2]);
    for(int x=0;x<4096;x++)for(int c=0;c<3;c++)d.image[x][c]=static_cast<unsigned short>(x*16);
    hueviaBlendHighlights(raw.get());int checks=0;
    for(int x=0;x<4096;x++)for(int c=0;c<3;c++){checks++;if(d.image[x][c]!=x*16)return 1;}
    float previous=0;for(int ev=-50;ev<=50;ev++){hueviaRawSafety(*raw,ev,2);checks++;if(d.params.exp_correc||d.params.adjust_maximum_thr!=0||d.params.bright<previous)return 2;previous=d.params.bright;}
    std::printf("PASS %d native RAW checks; full achromatic ramp preserved, EV transfer is monotonic and sensor-white adaptation disabled\n",checks);
    std::free(d.image);d.image=nullptr;return 0;
}
