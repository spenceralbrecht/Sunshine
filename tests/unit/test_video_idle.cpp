#include "src/video_idle.h"
#include <gtest/gtest.h>

using namespace std::chrono_literals;

TEST(CellularIdle, RequiresVersionedPingAndExpires) {
  std::string ping(8, '\0');
  EXPECT_FALSE(video::cellular_ping(ping));
  ping += "MSI1";
  ping += '\1';
  ASSERT_TRUE(video::cellular_ping(ping));
  EXPECT_TRUE(*video::cellular_ping(ping));
  ping[12] = 0;
  ASSERT_TRUE(video::cellular_ping(ping));
  EXPECT_FALSE(*video::cellular_ping(ping));
  ping[12] = 2;
  EXPECT_FALSE(video::cellular_ping(ping));

  video::cellular_idle_t policy;
  auto now = video::cellular_idle_t::clock::time_point(10s);
  EXPECT_FALSE(policy.enabled(now));
  policy.renew(true, now);
  EXPECT_TRUE(policy.enabled(now + 1999ms));
  EXPECT_FALSE(policy.enabled(now + 2s));
  policy.renew(false, now + 1s);
  EXPECT_FALSE(policy.enabled(now + 1s));
}

TEST(CellularIdle, WifiAndMotionKeepEveryFrameWhileIdleIsBounded) {
  video::cellular_idle_t policy;
  auto start = video::cellular_idle_t::clock::time_point(10s);
  for (int i = 0; i < 300; ++i) {
    EXPECT_TRUE(policy.should_encode(false, false, start + i * 33ms));
  }
  policy.renew(true, start + 10s);
  for (int i = 0; i < 30; ++i) {
    EXPECT_TRUE(policy.should_encode(false, false, start + 10s + i * 33ms));
  }
  EXPECT_TRUE(policy.should_encode(false, false, start + 11190ms));
  EXPECT_FALSE(policy.should_encode(false, false, start + 11223ms));
  // A pixel change or explicit IDR cannot wait for the idle refresh deadline.
  EXPECT_TRUE(policy.should_encode(true, false, start + 11224ms));
  EXPECT_TRUE(policy.should_encode(false, true, start + 11225ms));
  EXPECT_TRUE(policy.should_encode(false, false, start + 11400ms));
  EXPECT_FALSE(policy.should_encode(false, false, start + 11480ms));
  EXPECT_TRUE(policy.should_encode(false, false, start + 11600ms));
  for (int i = 0; i < 10; ++i) {
    EXPECT_TRUE(policy.should_encode(true, false, start + 11633ms + i * 33ms));
  }
  policy.renew(false, start + 12s);
  EXPECT_TRUE(policy.should_encode(false, false, start + 12s));
  EXPECT_TRUE(policy.should_encode(false, false, start + 12033ms));
}

TEST(CellularIdle, ComparesLastPixelAndIgnoresRowPadding) {
  uint8_t a[] = {1, 2, 9, 9, 3, 4, 9, 9};
  uint8_t b[] = {1, 2, 0, 3, 4, 0};
  EXPECT_TRUE(video::same_plane({a, 4, 2, 2}, {b, 3, 2, 2}));
  b[4] = 5;
  EXPECT_FALSE(video::same_plane({a, 4, 2, 2}, {b, 3, 2, 2}));
  EXPECT_FALSE(video::same_plane({nullptr, 4, 2, 2}, {b, 3, 2, 2}));
  EXPECT_FALSE(video::same_plane({a, 1, 2, 2}, {b, 3, 2, 2}));
  EXPECT_FALSE(video::same_plane({a, 4, 2, 1}, {b, 3, 2, 2}));
}
