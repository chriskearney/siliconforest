# Attended hardware evidence

These MIT render probes are copied unchanged from the pinned public kernel tools;
PROVENANCE records their source and hashes. They compare all 4,096 pixels after a
clear and shader draw on the actual Apple GPU. Software rendering is rejected.
They are diagnostic tools, not installed runtime dependencies.

Build on a provisioned ARM64 builder with GLVND and Vulkan development headers:

```sh
glslangValidator -V --target-env vulkan1.1 --vn render_check_vert -o render-check.vert.h render-check.vert
glslangValidator -V --target-env vulkan1.1 --vn render_check_frag -o render-check.frag.h render-check.frag
cc -O2 gl-render-check.c -lEGL -lGLESv2 -o gl-render-check-aarch64
cc -O2 vk-render-check.c -lvulkan -o vk-render-check-aarch64
```

On the attended Mac, collect baseline evidence with the real GUI username:

```sh
sudo python3 collect.py --user GUI_USER --probes /path/to/probes --output /var/tmp/UNIQUE_REPORT
```

After installing and rebooting, add
`--manifest /var/lib/siliconforest/active.json`. That also checks the actual
running kernel and stage 2 identity, installed package/source identities, exact
UKI and stage 2 bytes, and compositor-loaded libraries owned by mesa-siliconforest.
It never repairs a mismatch. Use a fresh output directory for every boot.

The collector supports Hyprland and the existing chonkstep session, uses only
selected environment variables, confirms active monitors and captures one frame.
The desktop screenshot is private and must stay local. Only selected model,
firmware, version, hash, display-mode and test results appear in report.json.
This evidence does not include suspend, a complete API conformance suite or
qualification of another machine. Repeat after coordinated rollback and again
on the final installed default before recording release qualification.
