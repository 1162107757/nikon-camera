#pragma once
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct {int width,height,rawWidth,rawHeight,bits,exifOrientation;char make[128],model[128];} HueviaRawInfo;
typedef struct {int whiteBalance,kelvin,tint,exposureTenths,highlights,quality;} HueviaRawSettings;
typedef int (*HueviaRawProgress)(void *context,double progress);
int HueviaRawInspect(const char *path,HueviaRawInfo *info,char *error,int capacity);
int HueviaRawDevelop(const char *path,const HueviaRawSettings *settings,uint32_t *argb,int width,int height,HueviaRawProgress progress,void *context,char *error,int capacity);
const char *HueviaRawVersion(void);
int HueviaRawEmbeddedJpeg(const char *path,uint8_t **bytes,int *length);
#ifdef __cplusplus
}
#endif
