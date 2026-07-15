# macOS ScreenCaptureKit Capture Plan

Sunshine's current macOS capture backend is `AVCaptureScreenInput` in
`src/platform/macos/av_video.m`, bridged into the video pipeline by
`src/platform/macos/display.mm`.

ScreenCaptureKit is the likely replacement path for lower capture overhead and
change-aware frame handling. Apple exposes `SCStreamFrameInfoDirtyRects`, which
identifies the areas of a frame that changed. Sunshine still has to feed a
normal video stream to Moonlight, so dirty rects are not a wire-protocol
replacement for H.264/HEVC inter-frame compression. They are useful before the
encoder: skip empty frames, bound CPU copies/conversions, and add evidence about
how much of each frame actually changes.

Reference: Apple's
[`SCStreamFrameInfo.dirtyRects`](https://developer.apple.com/documentation/screencapturekit/scstreamframeinfo/dirtyrects)
documentation describes it as metadata for retrieving the areas of a video
frame that contain changes.

## Proposed Shape

1. Add a new macOS capture wrapper beside `av_video.*`, for example
   `sc_video.h` and `sc_video.mm`.
2. Keep `AVCaptureScreenInput` as the fallback for older macOS versions, older
   SDKs, and first-run failures.
3. Use `SCShareableContent` to map `CGDirectDisplayID` to an `SCDisplay`.
4. Create an `SCContentFilter` for the selected display and an `SCStream` with
   the requested frame interval, pixel format, width, and height.
5. In the `SCStreamOutput` callback, inspect the sample buffer attachments:
   `SCStreamFrameInfoStatus`, `SCStreamFrameInfoDisplayTime`, and
   `SCStreamFrameInfoDirtyRects`.
6. Pass the sample buffer through the existing `av_img_t` / `CVPixelBuffer`
   path first, so the initial change is backend-isolated.
7. Add counters for dirty-rect coverage, empty dirty-rect frames, dropped frames,
   and full-frame fallbacks.
8. Only after those counters prove value, add partial-frame optimization in the
   conversion/copy path. VideoToolbox still controls final inter-frame encoding.

## Build Considerations

- ScreenCaptureKit requires macOS 12.3+ at runtime.
- The code needs SDK availability guards and a runtime fallback, because this
  repository still contains compatibility code for older macOS SDK behavior.
- `cmake/dependencies/macos.cmake` must find `ScreenCaptureKit`, and
  `cmake/compile_definitions/macos.cmake` must link it only when available.
- The Objective-C++ bridge should be `.mm`, not `.m`, if it needs C++ helpers.

## First Milestone

The first milestone should not try to be clever. It should produce the same
frames as the current backend, log rate-limited dirty-rect coverage stats, and
fall back automatically to `AVCaptureScreenInput` if ScreenCaptureKit is missing
or fails to start.

Only after that should we decide whether to use dirty rects to suppress more
work. Otherwise there is too much risk of changing stream behavior without a CPU
win.
