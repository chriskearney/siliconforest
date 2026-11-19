# SceneKit

SPDX-License-Identifier: MIT OR Apache-2.0

Load subset for the SceneKit symbols Preview imports. The install name is
`/System/Library/Frameworks/SceneKit.framework/Versions/A/SceneKit`,
compatibility 1.0.0, current 608.255.0. `build.nix` is not a shared install.

`SCNView` is an `NSView` subclass. `SCNOffscreenRenderer` is an `SCNRenderer`.
`SCNCamera`, `SCNSceneSource`, and `SCNTransaction` are `NSObject` subclasses.
Those superclasses and the eight constant strings are the measurements in
`runs/preview/retained/scenekit/m6-constants.log`.

`SCNSceneSource` keeps the URL and options it was given.
`sceneWithOptions:statusHandler:` reports an error and returns nil.
`SCNOffscreenRenderer` returns nil. `SCNTransaction` records begin/commit
nesting and an animation duration. `SCNView` stores a scene pointer, a point
of view, a scene time, and the camera-control flag. None of this parses a
scene file or draws geometry.

`build.nix` takes `appkit` and `coregraphics`. The defaults are the cached
retained PDFKit outputs, not the package AppKit attribute:

```
appkit = /nix/store/cx4yvkwbcm6xdicdj43d5srxkwvcjajs-puredarwin-appkit-0.1
coregraphics = /nix/store/jrcb39irvzmh95cd8wwiabsvsjxy5k58-puredarwin-coregraphics-0.1
```

The other link and header paths are the same cached toolchain recorded in
`runs/preview/retained/scenekit/scratch/build.sh`. That scratch command
produced the dylib whose sha256 is
`7162ac608c4f1b1aad1c4d98fc1c28adc742ea1b9af58216930d261eb923a3a3`
and the probe whose sha256 is
`1b7b5131c96975e11c69b05fdaaa487d36d98676c6685cad82730d6721cd7d69`.

The headless M1 run of that pair is `runs/preview/retained/scenekit/m1-scratch.log`.
It loaded one SceneKit from the scratch prefix and exited 0:

```
super SCNView=NSView SCNOffscreenRenderer=SCNRenderer SCNCamera=NSObject SCNSceneSource=NSObject SCNTransaction=NSObject
strings kExportPointOfViewAttribute kSceneEndTimeAttributeKey author authoring_tool contributors up_axis kSceneSourceSceneIndexKey kSceneStartTimeAttributeKey
scene_nil=1 renderer_nil=1 duration=1.5 camera=SCNCamera
failures=0
```

P11 mapped those dylib bytes. This is not a 3D scene load or a Preview UI pass.
The pinned Nix derivation records that command and has not been substituted
for the scratch binary.
