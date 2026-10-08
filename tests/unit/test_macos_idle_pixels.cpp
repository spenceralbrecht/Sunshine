#ifdef __APPLE__
#include "src/platform/macos/av_img_t.h"
#include <gtest/gtest.h>

namespace {
  std::shared_ptr<platf::av_img_t> image(OSType format, size_t width = 8) {
    CVPixelBufferRef buffer = nullptr;
    if (CVPixelBufferCreate(nullptr, width, 4, format, nullptr, &buffer) != kCVReturnSuccess) {
      return nullptr;
    }
    CMVideoFormatDescriptionRef description = nullptr;
    CMVideoFormatDescriptionCreateForImageBuffer(nullptr, buffer, &description);
    CMSampleBufferRef sample = nullptr;
    CMSampleTimingInfo timing {kCMTimeInvalid, kCMTimeZero, kCMTimeInvalid};
    auto result = CMSampleBufferCreateReadyWithImageBuffer(nullptr, buffer, description, &timing, &sample);
    CFRelease(description);
    CVPixelBufferRelease(buffer);
    if (result != noErr) {
      return nullptr;
    }
    auto img = std::make_shared<platf::av_img_t>();
    img->sample_buffer = std::make_shared<platf::av_sample_buf_t>(sample);
    img->pixel_buffer = std::make_shared<platf::av_pixel_buf_t>(sample);
    CFRelease(sample);
    auto buf = img->pixel_buffer->buf;
    if (CVPixelBufferIsPlanar(buf)) {
      for (size_t plane = 0; plane < CVPixelBufferGetPlaneCount(buf); ++plane) {
        std::memset(CVPixelBufferGetBaseAddressOfPlane(buf, plane), 42,
          CVPixelBufferGetBytesPerRowOfPlane(buf, plane) * CVPixelBufferGetHeightOfPlane(buf, plane));
      }
    } else {
      std::memset(CVPixelBufferGetBaseAddress(buf), 42, CVPixelBufferGetBytesPerRow(buf) * CVPixelBufferGetHeight(buf));
    }
    return img;
  }
}

TEST(MacosIdlePixels, ActualNV12AndP010DetectChromaChanges) {
  for (auto format : {kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange}) {
    auto a = image(format);
    auto b = image(format);
    ASSERT_TRUE(a && b);
    EXPECT_TRUE(a->same_pixels(*b));
    auto chroma = static_cast<uint8_t *>(CVPixelBufferGetBaseAddressOfPlane(b->pixel_buffer->buf, 1));
    chroma[format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange ? 7 : 15] ^= 1;
    EXPECT_FALSE(a->same_pixels(*b));
  }
}

TEST(MacosIdlePixels, BGRAChangesDimensionsAndUnknownFormatsFailOpen) {
  auto a = image(kCVPixelFormatType_32BGRA);
  auto b = image(kCVPixelFormatType_32BGRA);
  auto resized = image(kCVPixelFormatType_32BGRA, 16);
  auto unknown = image(kCVPixelFormatType_32ARGB);
  ASSERT_TRUE(a && b && resized && unknown);
  EXPECT_TRUE(a->same_pixels(*b));
  b->pixel_buffer->data()[31] ^= 1;
  EXPECT_FALSE(a->same_pixels(*b));
  EXPECT_FALSE(a->same_pixels(*resized));
  EXPECT_FALSE(unknown->same_pixels(*unknown));
  platf::av_img_t empty;
  EXPECT_FALSE(a->same_pixels(empty));
}
#endif
