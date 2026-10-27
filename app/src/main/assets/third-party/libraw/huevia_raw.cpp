#include <jni.h>
#include <android/bitmap.h>
#include <libraw/libraw.h>
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <exception>
#include <new>
#include <string>

namespace {
constexpr uint64_t kMaxPixels=60000000;
void fail(JNIEnv* env,const char* type,const std::string& text){if(env->ExceptionCheck())return;jclass cls=env->FindClass(type);if(cls){env->ThrowNew(cls,text.c_str());env->DeleteLocalRef(cls);}}
void io(JNIEnv* env,const std::string& text){fail(env,"java/io/IOException",text);}
void resultError(JNIEnv* env,int result,const char* stage){if(result==LIBRAW_CANCELLED_BY_CALLBACK)fail(env,"java/io/InterruptedIOException","RAW development cancelled");else io(env,std::string(stage)+": "+LibRaw::strerror(result));}
struct Path {
    JNIEnv* env;jstring value;const char* chars;
    Path(JNIEnv* env,jstring value):env(env),value(value),chars(value?env->GetStringUTFChars(value,nullptr):nullptr){}
    ~Path(){if(chars)env->ReleaseStringUTFChars(value,chars);}
};
struct Callback {
    JNIEnv* env;jobject object;jmethodID isCancelled,onProgress;bool cancelled=false;
    Callback(JNIEnv* env,jobject object):env(env),object(object),isCancelled(nullptr),onProgress(nullptr){if(!object){io(env,"RAW callbacks missing");return;}jclass cls=env->GetObjectClass(object);if(cls){isCancelled=env->GetMethodID(cls,"cancelled","()Z");if(!env->ExceptionCheck())onProgress=env->GetMethodID(cls,"onProgress","(D)V");env->DeleteLocalRef(cls);}}
    bool check(){if(env->ExceptionCheck())return true;if(!isCancelled)return true;cancelled=env->CallBooleanMethod(object,isCancelled);return env->ExceptionCheck()||cancelled;}
    bool progress(double value){if(check())return false;env->CallVoidMethod(object,onProgress,value);return !check();}
};
int progress(void* opaque,enum LibRaw_progress stage,int iteration,int expected){Callback* callback=static_cast<Callback*>(opaque);unsigned flags=static_cast<unsigned>(stage);int index=0;while(flags>1){flags>>=1;index++;}double local=expected>0?std::max(0.0,std::min(1.0,iteration/static_cast<double>(expected))):0;return callback->progress(.025+.80*std::min(1.0,(index+local)/20.0))?0:1;}
void recycle(JNIEnv* env,jobject bitmap){if(!bitmap)return;jthrowable pending=env->ExceptionOccurred();if(pending)env->ExceptionClear();jclass cls=env->GetObjectClass(bitmap);if(cls){jmethodID method=env->GetMethodID(cls,"recycle","()V");if(method)env->CallVoidMethod(bitmap,method);env->DeleteLocalRef(cls);}if(pending){if(env->ExceptionCheck())env->ExceptionClear();env->Throw(pending);env->DeleteLocalRef(pending);}}
int exif(int flip){static const int values[8]={1,2,4,3,5,8,6,7};return flip>=0&&flip<8?values[flip]:1;}
bool dimensions(JNIEnv* env,int width,int height){if(width<1||height<1||width>65535||height>65535||static_cast<uint64_t>(width)*height>kMaxPixels){io(env,"Full RAW image exceeds the 60 megapixel development limit");return false;}return true;}
jstring metadata(JNIEnv* env,const char* value,size_t size){std::string clean;for(size_t i=0;i<size&&value[i];i++){unsigned char c=static_cast<unsigned char>(value[i]);clean.push_back(c>=32&&c<127?static_cast<char>(c):'?');}return env->NewStringUTF(clean.c_str());}
jobject info(JNIEnv* env,LibRaw& raw){
    int width=0,height=0,colors=0,bits=0;raw.get_mem_image_format(&width,&height,&colors,&bits);if(!dimensions(env,width,height))return nullptr;
    unsigned maximum=raw.imgdata.color.maximum;int sensorBits=0;while(maximum){sensorBits++;maximum>>=1;}if(sensorBits==0)sensorBits=16;
    jclass cls=env->FindClass("cc/huevia/album/RawDeveloper$Info");if(!cls)return nullptr;
    jmethodID ctor=env->GetMethodID(cls,"<init>","(IIIIIILjava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V");if(!ctor){env->DeleteLocalRef(cls);return nullptr;}
    const char* decoder=raw.unpack_function_name();jstring make=metadata(env,raw.imgdata.idata.make,sizeof(raw.imgdata.idata.make));if(env->ExceptionCheck()){env->DeleteLocalRef(cls);return nullptr;}jstring model=metadata(env,raw.imgdata.idata.model,sizeof(raw.imgdata.idata.model));if(env->ExceptionCheck()){env->DeleteLocalRef(make);env->DeleteLocalRef(cls);return nullptr;}jstring name=env->NewStringUTF(decoder?decoder:"LibRaw");if(env->ExceptionCheck()){env->DeleteLocalRef(make);env->DeleteLocalRef(model);env->DeleteLocalRef(cls);return nullptr;}jstring version=env->NewStringUTF(LibRaw::version());if(env->ExceptionCheck()){env->DeleteLocalRef(make);env->DeleteLocalRef(model);env->DeleteLocalRef(name);env->DeleteLocalRef(cls);return nullptr;}
    jobject result=env->NewObject(cls,ctor,width,height,raw.imgdata.sizes.raw_width,raw.imgdata.sizes.raw_height,sensorBits,exif(raw.imgdata.sizes.flip),make,model,name,version);
    env->DeleteLocalRef(make);env->DeleteLocalRef(model);env->DeleteLocalRef(name);env->DeleteLocalRef(version);env->DeleteLocalRef(cls);return result;
}

// Planck spectrum integrated with the asymmetric Gaussian approximations to CIE 1931 XYZ
// from Wyman, Sloan and Shirley (JCGT 2013). Temperature is an illuminant, not an RGB tint.
double gaussian(double wavelength,double mean,double left,double right){double value=(wavelength-mean)/(wavelength<mean?left:right);return std::exp(-.5*value*value);}
void illuminant(int kelvin,double xyz[3]){
    xyz[0]=xyz[1]=xyz[2]=0;
    for(int nm=380;nm<=780;nm+=5){double wavelength=nm/550.0,radiance=1/(std::pow(wavelength,5)*std::expm1(14387768.77/(nm*static_cast<double>(kelvin))));
        xyz[0]+=radiance*(1.056*gaussian(nm,599.8,37.9,31.0)+.362*gaussian(nm,442.0,16.0,26.7)-.065*gaussian(nm,501.1,20.4,26.2));
        xyz[1]+=radiance*(.821*gaussian(nm,568.8,46.9,40.5)+.286*gaussian(nm,530.9,16.3,31.1));
        xyz[2]+=radiance*(1.217*gaussian(nm,437.0,11.8,36.0)+.681*gaussian(nm,459.0,26.0,13.8));
    }
    double normalize=xyz[1];for(int i=0;i<3;i++)xyz[i]/=normalize;
}
bool whiteBalance(JNIEnv* env,LibRaw& raw,int mode,int kelvin,int tint){
    auto& params=raw.imgdata.params;params.use_camera_wb=mode==0;params.use_auto_wb=mode==1;
    if(mode!=2)return true;double xyz[3];illuminant(kelvin,xyz);int colors=raw.imgdata.idata.colors;
    if(colors<1||colors>4){io(env,"RAW camera color channels do not support custom white balance");return false;}
    double response[4]{};bool hasXyz=true;
    for(int c=0;c<colors;c++){for(int i=0;i<3;i++)response[c]+=raw.imgdata.color.cam_xyz[c][i]*xyz[i];if(!std::isfinite(response[c])||response[c]<=1e-6)hasXyz=false;}
    if(hasXyz){for(int c=0;c<colors;c++)params.user_mul[c]=static_cast<float>(std::min(64.0,std::max(.01,1/response[c])));}
    else{
        // DNG identifies into rgb_cam/pre_mul without retaining cam_xyz. Recover its
        // normalized camera response through M^T (M M^T)^-1, then undo pre_mul.
        double gram[3][3]{},inverse[3][3]{},rgb[3]={3.2404542*xyz[0]-1.5371385*xyz[1]-.4985314*xyz[2],-.9692660*xyz[0]+1.8760108*xyz[1]+.0415560*xyz[2],.0556434*xyz[0]-.2040259*xyz[1]+1.0572252*xyz[2]};
        for(int i=0;i<3;i++)for(int j=0;j<3;j++)for(int c=0;c<colors;c++)gram[i][j]+=raw.imgdata.color.rgb_cam[i][c]*raw.imgdata.color.rgb_cam[j][c];
        double det=gram[0][0]*(gram[1][1]*gram[2][2]-gram[1][2]*gram[2][1])-gram[0][1]*(gram[1][0]*gram[2][2]-gram[1][2]*gram[2][0])+gram[0][2]*(gram[1][0]*gram[2][1]-gram[1][1]*gram[2][0]);
        if(!std::isfinite(det)||std::abs(det)<1e-10){io(env,"RAW has no usable camera color matrix for custom white balance; use camera or auto white balance");return false;}
        for(int i=0;i<3;i++)for(int j=0;j<3;j++)inverse[i][j]=(gram[(j+1)%3][(i+1)%3]*gram[(j+2)%3][(i+2)%3]-gram[(j+1)%3][(i+2)%3]*gram[(j+2)%3][(i+1)%3])/det;
        double projected[3]{};for(int i=0;i<3;i++)for(int j=0;j<3;j++)projected[i]+=inverse[i][j]*rgb[j];
        for(int c=0;c<colors;c++){double value=0;for(int i=0;i<3;i++)value+=raw.imgdata.color.rgb_cam[i][c]*projected[i];double pre=raw.imgdata.color.pre_mul[c];if(!std::isfinite(value)||!std::isfinite(pre)||value<=1e-6||pre<=0){io(env,"RAW camera matrix cannot represent this custom white balance");return false;}params.user_mul[c]=static_cast<float>(std::min(64.0,std::max(.01,pre/value)));}
    }
    if(colors>=3)params.user_mul[1]*=static_cast<float>(std::exp(-tint*.004));if(colors<4)params.user_mul[3]=params.user_mul[1];else params.user_mul[3]*=static_cast<float>(std::exp(-tint*.004));
    return true;
}
}

extern "C" JNIEXPORT jstring JNICALL Java_cc_huevia_album_RawDeveloper_nativeVersion(JNIEnv* env,jclass){return env->NewStringUTF(LibRaw::version());}
extern "C" JNIEXPORT jobject JNICALL Java_cc_huevia_album_RawDeveloper_nativeInspect(JNIEnv* env,jclass,jstring path){
    try{Path file(env,path);if(!file.chars)return nullptr;LibRaw raw(LIBRAW_OPTIONS_NO_DATAERR_CALLBACK);raw.imgdata.rawparams.max_raw_memory_mb=512;raw.imgdata.params.half_size=0;raw.imgdata.params.output_bps=8;
        int result=raw.open_file(file.chars);if(result!=LIBRAW_SUCCESS){resultError(env,result,"RAW open failed");return nullptr;}return info(env,raw);
    }catch(const std::bad_alloc&){io(env,"Not enough native memory to inspect RAW");}catch(const std::exception& error){io(env,std::string("RAW inspect failed: ")+error.what());}catch(...){io(env,"RAW inspect failed");}return nullptr;
}
extern "C" JNIEXPORT jobject JNICALL Java_cc_huevia_album_RawDeveloper_nativeDevelop(JNIEnv* env,jclass,jstring path,jint mode,jint kelvin,jint tint,jint exposure,jint highlights,jint quality,jobject callbacks){
    jobject bitmap=nullptr;bool locked=false;
    try{
        if(mode<0||mode>2||kelvin<2000||kelvin>12000||tint< -100||tint>100||exposure< -50||exposure>50||highlights<0||highlights>9||(quality!=0&&quality!=3)){io(env,"RAW development parameters invalid");return nullptr;}
        Path file(env,path);if(!file.chars)return nullptr;Callback callback(env,callbacks);if(callback.check()){if(!env->ExceptionCheck())fail(env,"java/io/InterruptedIOException","RAW development cancelled");return nullptr;}
        LibRaw raw(LIBRAW_OPTIONS_NO_DATAERR_CALLBACK);raw.imgdata.rawparams.max_raw_memory_mb=512;raw.set_progress_handler(progress,&callback);
        auto& params=raw.imgdata.params;params.half_size=0;params.output_bps=8;params.output_color=1;params.no_auto_bright=1;params.user_qual=quality;params.highlight=highlights;params.use_camera_matrix=3;params.gamm[0]=1/2.4;params.gamm[1]=12.92;params.use_fuji_rotate=1;params.no_interpolation=0;params.no_auto_scale=0;
        double gain=std::pow(2,exposure/10.0),linear=std::min(8.0,std::max(.25,gain));params.exp_correc=exposure!=0;params.exp_shift=static_cast<float>(linear);params.exp_preser=0;params.bright=static_cast<float>(gain/linear);
        int result=raw.open_file(file.chars);if(result!=LIBRAW_SUCCESS){resultError(env,result,"RAW open failed");return nullptr;}
        int width=0,height=0,colors=0,bps=0;raw.get_mem_image_format(&width,&height,&colors,&bps);if(!dimensions(env,width,height)||!whiteBalance(env,raw,mode,kelvin,tint))return nullptr;
        result=raw.unpack();if(result!=LIBRAW_SUCCESS){resultError(env,result,"RAW sensor decoding failed");return nullptr;}if(!callback.progress(.16)){if(!env->ExceptionCheck())fail(env,"java/io/InterruptedIOException","RAW development cancelled");return nullptr;}
        result=raw.dcraw_process();if(result!=LIBRAW_SUCCESS){resultError(env,result,"RAW demosaic/color processing failed");return nullptr;}if(!callback.progress(.84)){if(!env->ExceptionCheck())fail(env,"java/io/InterruptedIOException","RAW development cancelled");return nullptr;}
        raw.get_mem_image_format(&width,&height,&colors,&bps);if(!dimensions(env,width,height))return nullptr;if(bps!=8||(colors!=1&&colors!=3)){io(env,"RAW output is not a supported 8-bit grayscale/RGB image");return nullptr;}
        jclass bitmapClass=env->FindClass("android/graphics/Bitmap");if(!bitmapClass)return nullptr;jclass configClass=env->FindClass("android/graphics/Bitmap$Config");if(!configClass){env->DeleteLocalRef(bitmapClass);return nullptr;}
        jfieldID configId=env->GetStaticFieldID(configClass,"ARGB_8888","Landroid/graphics/Bitmap$Config;");if(!configId){env->DeleteLocalRef(bitmapClass);env->DeleteLocalRef(configClass);return nullptr;}jmethodID create=env->GetStaticMethodID(bitmapClass,"createBitmap","(IILandroid/graphics/Bitmap$Config;)Landroid/graphics/Bitmap;");if(!create){env->DeleteLocalRef(bitmapClass);env->DeleteLocalRef(configClass);return nullptr;}
        jobject config=env->GetStaticObjectField(configClass,configId);bitmap=env->CallStaticObjectMethod(bitmapClass,create,width,height,config);env->DeleteLocalRef(config);env->DeleteLocalRef(configClass);env->DeleteLocalRef(bitmapClass);if(env->ExceptionCheck()||!bitmap)return nullptr;
        AndroidBitmapInfo bitmapInfo{};void* pixels=nullptr;if(AndroidBitmap_getInfo(env,bitmap,&bitmapInfo)!=ANDROID_BITMAP_RESULT_SUCCESS||bitmapInfo.format!=ANDROID_BITMAP_FORMAT_RGBA_8888||AndroidBitmap_lockPixels(env,bitmap,&pixels)!=ANDROID_BITMAP_RESULT_SUCCESS){io(env,"Cannot lock RAW output bitmap");recycle(env,bitmap);return nullptr;}locked=true;
        // Write RGB8 directly into the destination stride. Expand backwards in each row,
        // avoiding a second full photograph buffer or a giant JNI/Java pixel array.
        result=raw.copy_mem_image(pixels,static_cast<int>(bitmapInfo.stride),0);if(result!=LIBRAW_SUCCESS){AndroidBitmap_unlockPixels(env,bitmap);locked=false;resultError(env,result,"RAW bitmap transfer failed");recycle(env,bitmap);return nullptr;}
        for(int row=0;row<height;row++){if((row&31)==0&&!callback.progress(.85+.04*row/static_cast<double>(height))){AndroidBitmap_unlockPixels(env,bitmap);locked=false;if(!env->ExceptionCheck())fail(env,"java/io/InterruptedIOException","RAW development cancelled");recycle(env,bitmap);return nullptr;}uint8_t* bytes=static_cast<uint8_t*>(pixels)+static_cast<size_t>(row)*bitmapInfo.stride;for(int x=width-1;x>=0;x--){uint8_t r=bytes[x*colors],g=colors==1?r:bytes[x*colors+1],b=colors==1?r:bytes[x*colors+2];bytes[x*4]=r;bytes[x*4+1]=g;bytes[x*4+2]=b;bytes[x*4+3]=255;}}
        AndroidBitmap_unlockPixels(env,bitmap);locked=false;if(!callback.progress(.90)){if(!env->ExceptionCheck())fail(env,"java/io/InterruptedIOException","RAW development cancelled");recycle(env,bitmap);return nullptr;}return bitmap;
    }catch(const std::bad_alloc&){io(env,"Not enough native memory for full RAW development");}catch(const std::exception& error){io(env,std::string("RAW development failed: ")+error.what());}catch(...){io(env,"RAW development failed");}
    if(locked&&bitmap)AndroidBitmap_unlockPixels(env,bitmap);if(bitmap)recycle(env,bitmap);return nullptr;
}
