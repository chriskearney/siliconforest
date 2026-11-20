# Image Capture browser for Preview

This build uses Finch's ICDeviceBrowser implementation from the existing
pinned source. Its device list and lifecycle are real, and a local-enumeration
callback runs on the caller's run loop. SiliconForest supplies no Image Capture
transport in this configuration, so the device list stays empty and capture
authorization is restricted. This port cannot scan or import from a camera.

Preview's arm64e startup calls `_ICInitialize` with no observed inputs or
return use. The device lookup passes one Objective-C value and explicitly
handles a nil result. The private entry points realize ICDeviceBrowser and
return an empty lookup when there is no transport.

The M1 scratch test checked both exports, browser start and stop, one
local-enumeration callback, empty device lookup and restricted authorization.
