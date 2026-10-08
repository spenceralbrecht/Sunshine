/** Session-local idle encoding for clients that explicitly report cellular data. */
#pragma once

#include <algorithm>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <optional>
#include <string_view>

namespace video {
  struct pixel_plane_t {
    const std::uint8_t *data;
    std::size_t stride;
    std::size_t row_bytes;
    std::size_t rows;
  };

  // Compare active pixels, not allocator padding. Invalid views fail open.
  inline bool same_plane(const pixel_plane_t &a, const pixel_plane_t &b) {
    if (!a.data || !b.data || !a.rows || !a.row_bytes || a.rows != b.rows ||
        a.row_bytes != b.row_bytes || a.stride < a.row_bytes || b.stride < b.row_bytes) {
      return false;
    }
    for (std::size_t row = 0; row < a.rows; ++row) {
      if (std::memcmp(a.data + row * a.stride, b.data + row * b.stride, a.row_bytes)) {
        return false;
      }
    }
    return true;
  }

  // Legacy ping bytes stay intact. Only this versioned extension opts in.
  inline std::optional<bool> cellular_ping(std::string_view payload) {
    if (payload.size() != 13 || payload.substr(8, 4) != "MSI1" ||
        static_cast<unsigned char>(payload[12]) > 1) {
      return std::nullopt;
    }
    return payload[12] == 1;
  }

  class cellular_idle_t {
  public:
    using clock = std::chrono::steady_clock;

    void renew(bool cellular, clock::time_point now) {
      if (cellular && !enabled(now)) {
        refine_until = now + std::chrono::seconds(1);
      }
      cellular_until = cellular ? now + std::chrono::seconds(2) : clock::time_point {};
    }

    bool enabled(clock::time_point now) const {
      return now < cellular_until;
    }

    bool should_encode(bool changed, bool idr, clock::time_point now) {
      if (changed) {
        refine_until = std::max(refine_until, now + std::chrono::milliseconds(250));
      }
      if (!enabled(now) || changed || idr || !last_encoded || now < refine_until ||
          now - *last_encoded >= std::chrono::milliseconds(200)) {
        last_encoded = now;
        return true;
      }
      return false;
    }

  private:
    clock::time_point cellular_until {};
    clock::time_point refine_until {};
    std::optional<clock::time_point> last_encoded;
  };
}  // namespace video
