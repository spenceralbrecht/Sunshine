# macOS Remote Streaming Notes

These notes are for macOS hosts that are usually reached through Tailscale from
remote networks.

## Safe Baseline

Keep this baseline unless the host is firewall-isolated to Tailscale only:

```text
upnp = disabled
origin_web_ui_allowed = pc
address_family = ipv4
lan_encryption_mode = 2
wan_encryption_mode = 2
encoder = videotoolbox
vt_software = disabled
vt_realtime = enabled
```

`lan_encryption_mode = 0` is not a Tailscale-only setting. Sunshine classifies
`100.64.0.0/10` as LAN, so Tailscale peers use the LAN encryption mode, but so
do ordinary private LAN peers such as `192.168.0.0/16` and `10.0.0.0/8`.

Do not disable LAN stream encryption on a remotely reachable Mac unless the
Sunshine ports are blocked on every non-Tailscale interface.

## Health Check

Run the local health check before changing remote streaming settings:

```bash
scripts/macos_remote_stream_health.sh <tailscale-peer>
```

The script reports:

- whether each supplied Tailscale peer is direct or using a DERP relay
- the active Sunshine encryption, UPnP, Web UI, encoder, and VideoToolbox modes
- the host network interface and Tailscale IP
- CPU from Sunshine, Tailscale, WindowServer, and VideoToolbox

For performance triage, a direct Tailscale path plus high Sunshine or
WindowServer CPU points at capture/compositing/encode work. A DERP relay points
at network path setup first.
