# Finch AppIntents ABI work for Preview

The open Finch baseline built against the M6 reference SDK exports 313 of the
320 AppIntents symbols imported by Preview 11.0 build 1113.5.3. This patch adds
the missing source declarations and implementations for the numeric parameter
configuration, optional-value summary condition, negative phrase default and
async input request. A reference arm64e build exports all 320 required names.

An arm64 reference CLI verified that a Double parameter preserves its default,
control style and bounds, that a provider's default negative phrase list is
empty, and that requesting input throws an error because the intent input
service is unavailable. The code uses Finch's existing unavailable-service
recording. Preview itself was not run with this provider.

The reference builds use the M6 SDK modules. A SiliconForest build still needs
compatible CoreGraphics, CoreSpotlight and UniformTypeIdentifiers compiler
modules and equivalent Foundation value types. This patch is an input to that
port and does not install a framework or claim a runnable AppIntents provider.
