# MetalKit view for Preview

This rebuilds Finch's pinned MTKView against the retained AppKit and
QuartzCore. It supplies the class and its metaclass, which Preview imports.
The view uses a CAMetalLayer for sizing and delegates explicit draws to the
caller. This recipe builds the view source only.

A private M1 probe verified the NSView superclass, CAMetalLayer backing,
size updates, and draw delegate. It found no drawable with no device attached.
The headless run reported that the EGL backend was unavailable. It did not
exercise GPU rendering, texture loading, or mesh support.
