// SPDX-License-Identifier: MIT
// sf-metal-smoke: the Metal API (metal2vulkan-runtime) on the system's Vulkan device.
//
//   sf-metal-smoke <runtime_examples.bc> [out.ppm]
//
// 1. lists Vulkan devices and the runtime's floor verdict for each;
// 2. compute: `scale_and_offset` (output[i] = input[i] * scale + i) over N floats, checked exactly
//    against the CPU;
// 3. render: `colored_vertex` + `colored_fragment`, one triangle into a 256x256 RGBA8Unorm
//    target, read back and compared pixel by pixel with a CPU rasteriser (pixel centres,
//    top-left rule); writes the frame as PPM when a path is given.
// Exit 0 only when both checks hold.
use metal2vulkan_runtime::*;
use std::time::Instant;

const SIDE: u32 = 256;
const N: usize = 1 << 20;

fn die<T, E: std::fmt::Display>(what: &str, r: Result<T, E>) -> T {
    r.unwrap_or_else(|e| {
        eprintln!("FAIL {what}: {e}");
        std::process::exit(1)
    })
}

fn floats(v: &[f32]) -> Vec<u8> {
    v.iter().flat_map(|x| x.to_le_bytes()).collect()
}

fn fnv(bytes: &[u8]) -> u32 {
    bytes.iter().fold(0x811c9dc5u32, |h, b| (h ^ *b as u32).wrapping_mul(0x01000193))
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let bc_path = args.get(1).expect("usage: sf-metal-smoke <runtime_examples.bc> [out.ppm]");
    let bitcode = die("read bitcode", std::fs::read(bc_path));
    let library = die("Library::from_air", Library::from_air(&bitcode));

    let t0 = Instant::now();
    let instance = die("Instance::new", Instance::new(&[]));
    let physicals = die("physical_devices", instance.physical_devices());
    let mut chosen = None;
    for (i, p) in physicals.iter().enumerate() {
        match p.check() {
            Ok(_) => {
                println!("device {i}: meets the runtime's floor");
                if chosen.is_none() {
                    chosen = Some(p);
                }
            }
            Err(below) => println!("device {i}: BELOW FLOOR: {below:?}"),
        }
    }
    let Some(physical) = chosen else {
        eprintln!("FAIL no device meets the floor");
        std::process::exit(2)
    };
    let device = die("Device::new", Device::new(physical, DeviceOptions::default()));
    println!("device up in {:.1} ms", t0.elapsed().as_secs_f64() * 1e3);
    let queue = die("queue", device.new_command_queue(4));
    let block = die("block", device.take_block(MemoryClass::Shared, 16 << 20));
    let mut next = 0u64;
    let mut buffer = |bytes: &[u8]| {
        let b = die("buffer", device.new_buffer(block.id, next, bytes.len() as u64, Some(0)));
        next += (bytes.len() as u64).next_multiple_of(256);
        let p = b.contents().expect("a Shared buffer");
        // SAFETY: the range lies in the live buffer; no GPU work uses it yet.
        unsafe { std::ptr::copy_nonoverlapping(bytes.as_ptr(), p.as_ptr(), bytes.len()) };
        b
    };

    // ---- compute ----
    let input: Vec<f32> = (0..N).map(|i| (i % 1000) as f32 * 0.25 - 7.0).collect();
    let scale = 1.5f32;
    let inb = buffer(&floats(&input));
    let outb = buffer(&vec![0u8; N * 4]);
    let sb = buffer(&scale.to_le_bytes());
    let kernel = library.function("scale_and_offset").expect("scale_and_offset");
    let cd = ComputePipelineDescriptor::new(StageSource::Function(FunctionDescriptor::new(kernel)));
    let t = Instant::now();
    let cps = die("compute state", device.new_compute_pipeline_state(&cd, |_| Ok(vec![])));
    die("compute finish", cps.finish_pipeline());
    let made = t.elapsed();
    let cb = die("command buffer", queue.command_buffer());
    {
        let mut e = die("compute encoder", cb.compute_command_encoder(DispatchType::Serial));
        die("set_compute_pipeline_state", e.set_compute_pipeline_state(&cps));
        die("set_buffer 0", e.set_buffer(Some(&inb), 0, 0));
        die("set_buffer 1", e.set_buffer(Some(&outb), 0, 1));
        die("set_buffer 2", e.set_buffer(Some(&sb), 0, 2));
        die("dispatch", e.dispatch_threads([N as u32, 1, 1], [256, 1, 1]));
        e.end_encoding();
    }
    let t = Instant::now();
    die("commit", cb.commit());
    die("wait", cb.wait_until_completed());
    let ran = t.elapsed();
    if let Some(err) = cb.error() {
        eprintln!("FAIL compute command buffer error: {err:?}");
        std::process::exit(1)
    }
    let out = outb.contents().expect("shared");
    // SAFETY: the command buffer completed; N floats live in the buffer.
    let got = unsafe { std::slice::from_raw_parts(out.as_ptr() as *const f32, N) };
    let bad = (0..N).filter(|&i| got[i].to_bits() != (input[i] * scale + i as f32).to_bits()).count();
    println!(
        "compute scale_and_offset: {N} elements, {bad} differ from the CPU; pipeline {:.1} ms, dispatch+wait {:.2} ms",
        made.as_secs_f64() * 1e3,
        ran.as_secs_f64() * 1e3
    );

    // ---- render ----
    let tri = [-0.8f32, -0.7, 0.85, -0.55, -0.1, 0.9];
    let colour = [0.2f32, 0.8, 0.4, 1.0];
    let pos = buffer(&floats(&tri));
    let col = buffer(&floats(&[colour; 3].concat()));
    let f = |n: &str| StageSource::Function(FunctionDescriptor::new(library.function(n).expect(n)));
    let mut rd = RenderPipelineDescriptor::new(f("colored_vertex"));
    rd.fragment = Some(f("colored_fragment"));
    rd.color_attachments[0] = Some(ColorAttachmentDescriptor::new(PixelFormat::RGBA8Unorm));
    let rps = die("render state", device.new_render_pipeline_state(&rd, |_| Ok(vec![])));
    die("render finish", rps.finish_pipeline());
    let mut td = TextureDescriptor::new(TextureType::Type2D, PixelFormat::RGBA8Unorm, SIDE, SIDE);
    td.usage = TextureUsage::RENDER_TARGET;
    td.storage_mode = StorageMode::Shared;
    let target = die("target", device.new_texture_for_views(&td));
    let mut pass = RenderPassDescriptor::default();
    {
        let c = &mut pass.color_attachments[0];
        c.texture = Some(target.clone());
        c.load_action = LoadAction::Clear;
    }
    let cb = die("command buffer", queue.command_buffer());
    {
        let mut e = die("render encoder", cb.render_command_encoder(&pass));
        die("set_render_pipeline_state", e.set_render_pipeline_state(&rps));
        die("vb0", e.set_vertex_buffer(Some(&pos), 0, 0));
        die("vb1", e.set_vertex_buffer(Some(&col), 0, 1));
        e.set_cull_mode(CullMode::None);
        die("draw", e.draw_primitives(PrimitiveType::Triangle, 0, 3, 1, 0));
        e.end_encoding();
    }
    die("commit", cb.commit());
    die("wait", cb.wait_until_completed());
    if let Some(err) = cb.error() {
        eprintln!("FAIL render command buffer error: {err:?}");
        std::process::exit(1)
    }
    let row = SIDE as usize * 4;
    let mut px = vec![0u8; row * SIDE as usize];
    die(
        "get_bytes",
        target.get_bytes(
            &mut px,
            row as u64,
            (row * SIDE as usize) as u64,
            Region { origin: [0; 3], size: [SIDE, SIDE, 1] },
            0,
            0,
        ),
    );
    // CPU reference: Metal's framebuffer has y down, clip y up; the default clear colour is opaque black (0,0,0,1).
    let v: Vec<(f64, f64)> = tri
        .chunks(2)
        .map(|p| ((p[0] as f64 + 1.0) * 0.5 * SIDE as f64, (1.0 - p[1] as f64) * 0.5 * SIDE as f64))
        .collect();
    let edge = |a: (f64, f64), b: (f64, f64), x: f64, y: f64| (b.0 - a.0) * (y - a.1) - (b.1 - a.1) * (x - a.0);
    let area = edge(v[0], v[1], v[2].0, v[2].1);
    let fill: [u8; 4] = colour.map(|c| (c * 255.0).round() as u8);
    let (mut inside, mut differ, mut edge_only) = (0, 0, 0);
    for y in 0..SIDE as usize {
        for x in 0..SIDE as usize {
            let (cx, cy) = (x as f64 + 0.5, y as f64 + 0.5);
            let w = [edge(v[1], v[2], cx, cy), edge(v[2], v[0], cx, cy), edge(v[0], v[1], cx, cy)];
            let w: Vec<f64> = w.iter().map(|e| e * area.signum()).collect();
            let near = w.iter().any(|e| e.abs() < 1e-6 * area.abs());
            let want = if w.iter().all(|e| *e > 0.0) { fill } else { [0, 0, 0, 255] };
            if want == fill { inside += 1; }
            let got = &px[y * row + x * 4..y * row + x * 4 + 4];
            if got != want {
                if near { edge_only += 1 } else { differ += 1 }
            }
        }
    }
    println!(
        "render triangle {SIDE}x{SIDE}: {inside} pixels inside, {differ} differ from the CPU (+{edge_only} exactly on an edge), fnv 0x{:08x}",
        fnv(&px)
    );
    if let Some(path) = args.get(2) {
        let mut ppm = format!("P6\n{SIDE} {SIDE}\n255\n").into_bytes();
        for p in px.chunks(4) { ppm.extend_from_slice(&p[..3]); }
        die("write ppm", std::fs::write(path, ppm));
        println!("wrote {path}");
    }
    drop((cps, rps, target));
    let ok = bad == 0 && differ == 0;
    println!("{}", if ok { "SMOKE PASS" } else { "SMOKE FAIL" });
    std::process::exit(if ok { 0 } else { 1 })
}
