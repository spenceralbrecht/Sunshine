#include <gtest/gtest.h>

#include <src/rtsp.h>

namespace {
  std::shared_ptr<rtsp_stream::launch_session_t> make_launch_session(uint32_t id, const char *unique_id) {
    auto session = std::make_shared<rtsp_stream::launch_session_t>();
    session->id = id;
    session->unique_id = unique_id;
    return session;
  }
}  // namespace

TEST(RtspLaunchSessionTests, NewPendingResumeReplacesStalePendingSession) {
  rtsp_stream::test_clear_pending_launch_session();

  rtsp_stream::launch_session_raise(make_launch_session(1U, "first"));
  ASSERT_TRUE(rtsp_stream::test_pending_launch_session_id().has_value());
  EXPECT_EQ(*rtsp_stream::test_pending_launch_session_id(), 1U);

  rtsp_stream::launch_session_raise(make_launch_session(2U, "second"));
  ASSERT_TRUE(rtsp_stream::test_pending_launch_session_id().has_value());
  EXPECT_EQ(*rtsp_stream::test_pending_launch_session_id(), 2U);

  rtsp_stream::test_clear_pending_launch_session();
}

TEST(RtspStreamSessionTests, SameClientIdentityReplacesExistingSession) {
  EXPECT_TRUE(rtsp_stream::should_replace_stream_session("tablet", "tablet"));
}

TEST(RtspStreamSessionTests, DifferentClientIdentityDoesNotReplaceExistingSession) {
  EXPECT_FALSE(rtsp_stream::should_replace_stream_session("phone", "tablet"));
}

TEST(RtspStreamSessionTests, EmptyIncomingIdentityDoesNotReplaceExistingSession) {
  EXPECT_FALSE(rtsp_stream::should_replace_stream_session("tablet", ""));
}
