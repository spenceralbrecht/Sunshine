# Performance Tuning
In addition to the options available in the [Configuration](configuration.md) section, there are a few additional
system options that can be used to help improve the performance of Sunshine.

## AMD

In Windows, enabling *Enhanced Sync* in AMD's settings may help reduce the latency by an additional frame. This
applies to `amfenc` and `libx264`.

## NVIDIA

Enabling *Fast Sync* in Nvidia settings may help reduce latency.

## macOS Remote Streaming

For macOS hosts that are usually reached through Tailscale, see
[macOS Remote Streaming Notes](macos_remote_streaming.md).

For the longer-term macOS capture backend work, see
[macOS ScreenCaptureKit Capture Plan](macos_screencapturekit_capture_plan.md).

<div class="section_buttons">

| Previous            |          Next |
|:--------------------|--------------:|
| [Guides](guides.md) | [API](api.md) |

</div>

<details style="display: none;">
  <summary></summary>
  [TOC]
</details>
