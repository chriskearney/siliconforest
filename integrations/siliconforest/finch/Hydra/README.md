# Hydra

This private compatibility framework serves Preview's PDF and image bring-up.
It exports the four Objective-C classes imported from Hydra, at the
`Versions/C/Hydra` install name. It supplies export options, transform values
and a local scene-node tree. The options, defaults, selector signatures and
32-byte vector arguments were checked against the reference runtime's public
Objective-C metadata and small runtime probes.

The renderer has no 3D backend. It reports an empty hierarchy, completes
asynchronous requests without a loaded scene and returns
`SFHydraRendererUnavailable` for exports. It never creates an export file.
The private build includes a probe for the metadata and these failure paths.
