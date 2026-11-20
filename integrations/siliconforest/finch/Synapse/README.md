# Synapse

This private Preview compatibility framework supplies its three imported
Synapse classes. It stores form-coaching preferences and document attributes
as bounded extended attributes in the SiliconForest namespace. It preserves
file contents and uses a default of enabled coaching for files without a
local preference. The async read returns on the main queue. The document
history callbacks report missing history for unlinked files and an explicit
unsupported error when a history operation needs the absent service.

The class and selector surface comes from the owner-provided Preview bundle
and Objective-C runtime signature observations on the M6. A plain reference
file had no document attributes and default form coaching. The M6 reference
writes failed at its history service, so Apple metadata interchange remains
unverified. The local provider uses its own attribute encoding and includes
no Apple implementation or resource data.

On the M1, the standalone probe passed local form and document metadata
round trips, observed main-queue callbacks, and checked the unsupported-history
error. The test file's content hash was unchanged. The framework and probe
ran from a private prefix. Preview has yet to reach this framework.
