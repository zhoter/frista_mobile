#include <jni.h>
#include <android/bitmap.h>
#include <android/log.h>
#include <string>
#include <vector>
#include <memory>

#include "dlib/dnn.h"
#include "dlib/image_processing.h"
#include "dlib/image_processing/frontal_face_detector.h"

#define LOG_TAG "NativeDlib"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

using namespace dlib;
using namespace std;

// ResNet 29-layer model definition
template <template <int,template<typename>class,int,typename> class block, int N, template<typename>class BN, typename SUBNET>
using residual = add_prev1<block<N,BN,1,tag1<SUBNET>>>;

template <template <int,template<typename>class,int,typename> class block, int N, template<typename>class BN, typename SUBNET>
using residual_down = add_prev2<avg_pool<2,2,2,2,skip1<tag2<block<N,BN,2,tag1<SUBNET>>>>>>;

template <int N, template <typename> class BN, int stride, typename SUBNET>
using block  = BN<con<N,3,3,1,1,relu<BN<con<N,3,3,stride,stride,SUBNET>>>>>;

template <int N, typename SUBNET> using ares      = relu<residual<block,N,affine,SUBNET>>;
template <int N, typename SUBNET> using ares_down = relu<residual_down<block,N,affine,SUBNET>>;

template <typename SUBNET> using alevel0 = ares_down<256,SUBNET>;
template <typename SUBNET> using alevel1 = ares<256,ares<256,ares_down<256,SUBNET>>>;
template <typename SUBNET> using alevel2 = ares<128,ares<128,ares_down<128,SUBNET>>>;
template <typename SUBNET> using alevel3 = ares<64,ares<64,ares<64,ares_down<64,SUBNET>>>>;
template <typename SUBNET> using alevel4 = ares<32,ares<32,ares<32,SUBNET>>>;

using anet_type = loss_metric<fc_no_bias<128,avg_pool_everything<
                            alevel0<
                            alevel1<
                            alevel2<
                            alevel3<
                            alevel4<
                            max_pool<3,3,2,2,relu<affine<con<32,7,7,2,2,
                            input_rgb_image_sized<150>
                            >>>>>>>>>>>>;

static std::unique_ptr<anet_type> s_net;
static std::unique_ptr<shape_predictor> s_sp;
static std::unique_ptr<frontal_face_detector> s_detector;

extern "C" {

JNIEXPORT jboolean JNICALL
Java_com_faskes_frista_frista_1mobile_DlibBridge_nativeInit(
    JNIEnv* env,
    jobject /* this */,
    jstring spPath,
    jstring resnetPath) {
    try {
        const char* c_sp = env->GetStringUTFChars(spPath, nullptr);
        const char* c_res = env->GetStringUTFChars(resnetPath, nullptr);

        LOGI("Loading shape predictor: %s", c_sp);
        s_sp = std::make_unique<shape_predictor>();
        deserialize(c_sp) >> (*s_sp);

        LOGI("Loading resnet model: %s", c_res);
        s_net = std::make_unique<anet_type>();
        deserialize(c_res) >> (*s_net);

        s_detector = std::make_unique<frontal_face_detector>(get_frontal_face_detector());

        env->ReleaseStringUTFChars(spPath, c_sp);
        env->ReleaseStringUTFChars(resnetPath, c_res);

        LOGI("Dlib models loaded successfully!");
        return JNI_TRUE;
    } catch (const std::exception& e) {
        LOGE("Error initializing dlib: %s", e.what());
        return JNI_FALSE;
    }
}

JNIEXPORT jfloatArray JNICALL
Java_com_faskes_frista_frista_1mobile_DlibBridge_nativeComputeDescriptor(
    JNIEnv* env,
    jobject /* this */,
    jobject bitmap,
    jint left,
    jint top,
    jint right,
    jint bottom) {

    if (!s_net || !s_sp) {
        LOGE("Models not initialized!");
        return nullptr;
    }

    AndroidBitmapInfo info;
    if (AndroidBitmap_getInfo(env, bitmap, &info) < 0) {
        LOGE("Failed to get bitmap info");
        return nullptr;
    }

    void* pixels = nullptr;
    if (AndroidBitmap_lockPixels(env, bitmap, &pixels) < 0 || !pixels) {
        LOGE("Failed to lock pixels");
        return nullptr;
    }

    matrix<rgb_pixel> img(info.height, info.width);
    const uint8_t* src = static_cast<const uint8_t*>(pixels);
    for (uint32_t r = 0; r < info.height; ++r) {
        const uint8_t* row_src = src + r * info.stride;
        for (uint32_t c = 0; c < info.width; ++c) {
            img(r, c) = rgb_pixel(row_src[c * 4], row_src[c * 4 + 1], row_src[c * 4 + 2]);
        }
    }
    AndroidBitmap_unlockPixels(env, bitmap);

    try {
        rectangle face_rect;
        if (right > left && bottom > top) {
            face_rect = rectangle(left, top, right, bottom);
        } else {
            // Auto detect
            std::vector<rectangle> faces = (*s_detector)(img);
            if (faces.empty()) {
                LOGI("No face detected in current orientation");
                return nullptr;
            } else {
                face_rect = faces[0];
            }
        }

        full_object_detection shape = (*s_sp)(img, face_rect);
        matrix<rgb_pixel> face_chip;
        extract_image_chip(img, get_face_chip_details(shape, 150, 0.25), face_chip);

        matrix<float, 0, 1> desc = (*s_net)(face_chip);
        jfloatArray result = env->NewFloatArray(128);
        if (!result) return nullptr;

        jfloat buf[128];
        for (int i = 0; i < 128; ++i) {
            buf[i] = desc(i);
        }
        env->SetFloatArrayRegion(result, 0, 128, buf);
        LOGI("Face descriptor computed successfully (128 floats)");
        return result;

    } catch (const std::exception& e) {
        LOGE("Error computing face descriptor: %s", e.what());
        return nullptr;
    }
}

}
