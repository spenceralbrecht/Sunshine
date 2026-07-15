/**
 * @file src/platform/macos/display.mm
 * @brief Definitions for display capture on macOS.
 */
// standard includes
#include <atomic>
#include <chrono>
#include <cstdint>
#include <memory>
#include <mutex>
#include <optional>
#include <vector>

// local includes
#include "src/config.h"
#include "src/logging.h"
#include "src/platform/common.h"
#include "src/platform/macos/av_img_t.h"
#include "src/platform/macos/av_video.h"
#include "src/platform/macos/misc.h"
#include "src/platform/macos/nv12_zero_device.h"

// Avoid conflict between AVFoundation and libavutil both defining AVMediaType
#define AVMediaType AVMediaType_FFmpeg
#include "src/video.h"
#undef AVMediaType

namespace fs = std::filesystem;

namespace platf {
  using namespace std::literals;

  namespace {
    constexpr auto capture_poll_timeout = 250ms;
    constexpr auto dummy_capture_timeout = 5s;
    constexpr auto capture_stats_log_interval = 30s;

    struct capture_stats_t {
      std::atomic<uint64_t> real_frames {0};
      std::atomic<uint64_t> no_frame_ticks {0};
      std::atomic<uint64_t> pull_interrupts {0};
      std::atomic<uint64_t> push_interrupts {0};
      std::mutex log_mutex;
      std::chrono::steady_clock::time_point last_log = std::chrono::steady_clock::now();
      uint64_t last_real_frames {};
      uint64_t last_no_frame_ticks {};
      uint64_t last_pull_interrupts {};
      uint64_t last_push_interrupts {};
    };

    void maybe_log_capture_stats(const std::shared_ptr<capture_stats_t> &stats, bool force = false) {
      auto now = std::chrono::steady_clock::now();
      std::scoped_lock lock {stats->log_mutex};
      if (!force && now - stats->last_log < capture_stats_log_interval) {
        return;
      }

      auto elapsed = std::chrono::duration<double>(now - stats->last_log).count();
      if (elapsed <= 0.0) {
        elapsed = 1.0;
      }

      auto real_frames = stats->real_frames.load(std::memory_order_relaxed);
      auto no_frame_ticks = stats->no_frame_ticks.load(std::memory_order_relaxed);
      auto pull_interrupts = stats->pull_interrupts.load(std::memory_order_relaxed);
      auto push_interrupts = stats->push_interrupts.load(std::memory_order_relaxed);

      auto real_delta = real_frames - stats->last_real_frames;
      auto no_frame_delta = no_frame_ticks - stats->last_no_frame_ticks;
      auto pull_delta = pull_interrupts - stats->last_pull_interrupts;
      auto push_delta = push_interrupts - stats->last_push_interrupts;

      if (force && real_delta == 0 && no_frame_delta == 0 && pull_delta == 0 && push_delta == 0) {
        return;
      }

      BOOST_LOG(info) << "macOS capture stats: real_frames="sv << real_delta
                      << " ("sv << (real_delta / elapsed) << " fps), no_frame_ticks="sv << no_frame_delta
                      << ", pull_interrupts="sv << pull_delta
                      << ", push_interrupts="sv << push_delta;

      stats->last_log = now;
      stats->last_real_frames = real_frames;
      stats->last_no_frame_ticks = no_frame_ticks;
      stats->last_pull_interrupts = pull_interrupts;
      stats->last_push_interrupts = push_interrupts;
    }

    std::optional<std::vector<CGDirectDisplayID>> active_display_ids() {
      CGDirectDisplayID displays[kMaxDisplays];
      uint32_t count = 0;
      if (CGGetActiveDisplayList(kMaxDisplays, displays, &count) != kCGErrorSuccess) {
        return std::nullopt;
      }

      return std::vector<CGDirectDisplayID> {displays, displays + count};
    }
  }  // namespace

  struct av_display_t: public display_t {
    AVVideo *av_capture {};
    CGDirectDisplayID display_id {};

    ~av_display_t() override {
      [av_capture release];
    }

    capture_e capture(const push_captured_image_cb_t &push_captured_image_cb, const pull_free_image_cb_t &pull_free_image_cb, bool *cursor) override {
      auto capture_stats = std::make_shared<capture_stats_t>();
      auto push_callback_mutex = std::make_shared<std::mutex>();

      auto capture_session = [av_capture capture:^(CMSampleBufferRef sampleBuffer) {
        auto new_sample_buffer = std::make_shared<av_sample_buf_t>(sampleBuffer);
        auto new_pixel_buffer = std::make_shared<av_pixel_buf_t>(new_sample_buffer->buf);

        std::shared_ptr<img_t> img_out;
        if (!pull_free_image_cb(img_out)) {
          capture_stats->pull_interrupts.fetch_add(1, std::memory_order_relaxed);
          maybe_log_capture_stats(capture_stats, true);
          // got interrupt signal
          // returning false here stops capture backend
          return false;
        }
        auto av_img = std::static_pointer_cast<av_img_t>(img_out);

        auto old_data_retainer = std::make_shared<temp_retain_av_img_t>(
          av_img->sample_buffer,
          av_img->pixel_buffer,
          img_out->data
        );

        av_img->sample_buffer = new_sample_buffer;
        av_img->pixel_buffer = new_pixel_buffer;
        img_out->data = new_pixel_buffer->data();

        img_out->width = (int) CVPixelBufferGetWidth(new_pixel_buffer->buf);
        img_out->height = (int) CVPixelBufferGetHeight(new_pixel_buffer->buf);
        img_out->row_pitch = (int) CVPixelBufferGetBytesPerRow(new_pixel_buffer->buf);
        img_out->pixel_pitch = img_out->row_pitch / img_out->width;

        old_data_retainer = nullptr;

        {
          std::scoped_lock lock {*push_callback_mutex};
          if (!push_captured_image_cb(std::move(img_out), true)) {
            capture_stats->push_interrupts.fetch_add(1, std::memory_order_relaxed);
            maybe_log_capture_stats(capture_stats, true);
            // got interrupt signal
            // returning false here stops capture backend
            return false;
          }
        }

        capture_stats->real_frames.fetch_add(1, std::memory_order_relaxed);
        maybe_log_capture_stats(capture_stats);

        return true;
      }];
      if (!capture_session.signal) {
        return capture_e::error;
      }

      // Poll for shutdown/reinit so the capture thread can stop even if the
      // capture backend never delivers another frame after disconnect.
      auto last_polled_real_frames = capture_stats->real_frames.load(std::memory_order_relaxed);
      while (dispatch_semaphore_wait(capture_session.signal, dispatch_time(DISPATCH_TIME_NOW, std::chrono::duration_cast<std::chrono::nanoseconds>(capture_poll_timeout).count())) != 0) {
        auto real_frames = capture_stats->real_frames.load(std::memory_order_relaxed);
        if (real_frames == last_polled_real_frames) {
          capture_stats->no_frame_ticks.fetch_add(1, std::memory_order_relaxed);
        }
        last_polled_real_frames = real_frames;

        bool should_cancel = false;
        {
          std::scoped_lock lock {*push_callback_mutex};
          should_cancel = !push_captured_image_cb(nullptr, false);
        }

        if (should_cancel) {
          capture_stats->push_interrupts.fetch_add(1, std::memory_order_relaxed);
          maybe_log_capture_stats(capture_stats, true);
          [av_capture cancelCapture:capture_session];
        }

        maybe_log_capture_stats(capture_stats);
      }

      maybe_log_capture_stats(capture_stats, true);

      return capture_e::ok;
    }

    std::shared_ptr<img_t> alloc_img() override {
      return std::make_shared<av_img_t>();
    }

    std::unique_ptr<avcodec_encode_device_t> make_avcodec_encode_device(pix_fmt_e pix_fmt) override {
      if (pix_fmt == pix_fmt_e::yuv420p) {
        av_capture.pixelFormat = kCVPixelFormatType_32BGRA;

        return std::make_unique<avcodec_encode_device_t>();
      } else if (pix_fmt == pix_fmt_e::nv12 || pix_fmt == pix_fmt_e::p010) {
        auto device = std::make_unique<nv12_zero_device>();

        device->init(static_cast<void *>(av_capture), pix_fmt, setResolution, setPixelFormat);

        return device;
      } else {
        BOOST_LOG(error) << "Unsupported Pixel Format."sv;
        return nullptr;
      }
    }

    int dummy_img(img_t *img) override {
      if (!platf::is_screen_capture_allowed()) {
        // If we don't have the screen capture permission, this function will hang
        // indefinitely without doing anything useful. Exit instead to avoid this.
        // A non-zero return value indicates failure to the calling function.
        return 1;
      }

      auto capture_session = [av_capture capture:^(CMSampleBufferRef sampleBuffer) {
        auto new_sample_buffer = std::make_shared<av_sample_buf_t>(sampleBuffer);
        auto new_pixel_buffer = std::make_shared<av_pixel_buf_t>(new_sample_buffer->buf);

        auto av_img = (av_img_t *) img;

        auto old_data_retainer = std::make_shared<temp_retain_av_img_t>(
          av_img->sample_buffer,
          av_img->pixel_buffer,
          img->data
        );

        av_img->sample_buffer = new_sample_buffer;
        av_img->pixel_buffer = new_pixel_buffer;
        img->data = new_pixel_buffer->data();

        img->width = (int) CVPixelBufferGetWidth(new_pixel_buffer->buf);
        img->height = (int) CVPixelBufferGetHeight(new_pixel_buffer->buf);
        img->row_pitch = (int) CVPixelBufferGetBytesPerRow(new_pixel_buffer->buf);
        img->pixel_pitch = img->row_pitch / img->width;

        old_data_retainer = nullptr;

        // returning false here stops capture backend
        return false;
      }];
      if (!capture_session.signal) {
        return 1;
      }

      if (dispatch_semaphore_wait(capture_session.signal, dispatch_time(DISPATCH_TIME_NOW, std::chrono::duration_cast<std::chrono::nanoseconds>(dummy_capture_timeout).count())) != 0) {
        [av_capture cancelCapture:capture_session];
        return 1;
      }

      return 0;
    }

    /**
     * A bridge from the pure C++ code of the hwdevice_t class to the pure Objective C code.
     *
     * display --> an opaque pointer to an object of this class
     * width --> the intended capture width
     * height --> the intended capture height
     */
    static void setResolution(void *display, int width, int height) {
      [static_cast<AVVideo *>(display) setFrameWidth:width frameHeight:height];
    }

    static void setPixelFormat(void *display, OSType pixelFormat) {
      static_cast<AVVideo *>(display).pixelFormat = pixelFormat;
    }
  };

  std::shared_ptr<display_t> display(platf::mem_type_e hwdevice_type, const std::string &display_name, const video::config_t &config) {
    if (hwdevice_type != platf::mem_type_e::system && hwdevice_type != platf::mem_type_e::videotoolbox) {
      BOOST_LOG(error) << "Could not initialize display with the given hw device type."sv;
      return nullptr;
    }

    auto display = std::make_shared<av_display_t>();

    // Default to main display
    display->display_id = CGMainDisplayID();

    // Print all displays available with it's name and id
    auto display_array = [AVVideo displayNames];
    BOOST_LOG(info) << "Detecting displays"sv;
    for (NSDictionary *item in display_array) {
      NSNumber *display_id = item[@"id"];
      // We need show display's product name and corresponding display number given by user
      NSString *name = item[@"displayName"];
      // We are using CGGetActiveDisplayList that only returns active displays so hardcoded connected value in log to true
      BOOST_LOG(info) << "Detected display: "sv << name.UTF8String << " (id: "sv << [NSString stringWithFormat:@"%@", display_id].UTF8String << ") connected: true"sv;
      if (!display_name.empty() && std::atoi(display_name.c_str()) == [display_id unsignedIntValue]) {
        display->display_id = [display_id unsignedIntValue];
      }
    }
    BOOST_LOG(info) << "Configuring selected display ("sv << display->display_id << ") to stream"sv;

    display->av_capture = [[AVVideo alloc] initWithDisplay:display->display_id frameRate:config.framerate];

    if (!display->av_capture) {
      BOOST_LOG(error) << "Video setup failed."sv;
      return nullptr;
    }

    display->width = display->av_capture.frameWidth;
    display->height = display->av_capture.frameHeight;
    // We also need set env_width and env_height for absolute mouse coordinates
    display->env_width = display->width;
    display->env_height = display->height;

    return display;
  }

  std::vector<std::string> display_names(mem_type_e hwdevice_type) {
    __block std::vector<std::string> display_names;

    auto display_array = [AVVideo displayNames];

    display_names.reserve([display_array count]);
    [display_array enumerateObjectsUsingBlock:^(NSDictionary *_Nonnull obj, NSUInteger idx, BOOL *_Nonnull stop) {
      NSString *name = obj[@"name"];
      display_names.emplace_back(name.UTF8String);
    }];

    return display_names;
  }

  /**
   * @brief Returns if GPUs/drivers have changed since the last call to this function.
   * @return `true` if a change has occurred or if it is unknown whether a change occurred.
   */
  bool needs_encoder_reenumeration() {
    static std::mutex reenumeration_state_lock;
    auto lg = std::lock_guard(reenumeration_state_lock);

    auto current_display_ids = active_display_ids();
    if (!current_display_ids) {
      BOOST_LOG(error) << "Failed to enumerate displays for encoder reenumeration"sv;
      return true;
    }

    static auto last_display_ids = *current_display_ids;
    if (*current_display_ids != last_display_ids) {
      BOOST_LOG(info) << "Encoder reenumeration is required"sv;
      last_display_ids = *current_display_ids;
      return true;
    }

    return false;
  }
}  // namespace platf
