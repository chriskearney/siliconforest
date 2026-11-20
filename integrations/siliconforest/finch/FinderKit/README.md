# FinderKit icon view for Preview

The private provider exports FIIconView as an NSView subclass. It draws an
NSImage and optional text with AppKit. It computes the icon and title frames
from the view bounds and uses those frames for hit testing. This scope covers
ordinary icon rendering and does not include Finder integration or drag
services.

The M1 scratch probe decoded a PNG fixture, verified the icon frame and hit
test, drew the image and labels through NSGraphicsContext, and measured 160
red bitmap pixels from the fixture. It created no window and all packet file
hashes matched after execution.
