// SPDX-License-Identifier: MIT
// sf-metallib-census: every function of a .metallib through metal2vulkan's translator, alone
// (Device::compile_function, no pipeline partner), for one device description.
//   sf-metallib-census <lib.metallib> <khronos-profile.json> [--quiet]
// Prints one line per function (stage, result, refusal) and totals; exit 0 always.
use metal2vulkan::device::{Device, DeviceDescription, DevicePolicy};
use metal2vulkan::library::Library;
use metal2vulkan::pipeline::{FunctionDescriptor, LoweringInputs};
use metal2vulkan::Budget;
use std::collections::BTreeMap;
fn main() {
    let a: Vec<String> = std::env::args().collect();
    let lib = Library::parse(&std::fs::read(&a[1]).expect("metallib")).expect("parse");
    let json = std::fs::read_to_string(&a[2]).expect("profile");
    let dev = Device::from_queries(DeviceDescription::from_khronos_json(&json, None).expect("desc"), DevicePolicy::default())
        .expect("device");
    let quiet = a.iter().any(|x| x == "--quiet");
    let (mut ok, mut bad) = (BTreeMap::<String, u32>::new(), BTreeMap::<String, u32>::new());
    let mut why = BTreeMap::<String, u32>::new();
    let infos: Vec<(String, String, usize)> =
        lib.functions().map(|f| (f.name.to_string(), format!("{:?}", f.stage), f.constants.len())).collect();
    for (name, stage, nconst) in &infos {
        let f = lib.function(name).expect("function");
        match dev.compile_function(&FunctionDescriptor::new(f.clone()), &LoweringInputs::new(), &Budget::standard()) {
            Ok(_) => {
                *ok.entry(stage.clone()).or_default() += 1;
                if !quiet { println!("OK      {stage:10} consts={nconst:2} {name}"); }
            }
            Err(e) => {
                *bad.entry(stage.clone()).or_default() += 1;
                let s = format!("{e}");
                let key: String = s.chars().take(110).collect();
                *why.entry(key).or_default() += 1;
                println!("REFUSED {stage:10} consts={nconst:2} {name}: {}", s.chars().take(300).collect::<String>());
            }
        }
    }
    println!("functions: {}", infos.len());
    for (s, n) in &ok { println!("compiled  {s}: {n}"); }
    for (s, n) in &bad { println!("refused   {s}: {n}"); }
    let mut w: Vec<_> = why.into_iter().collect();
    w.sort_by(|x, y| y.1.cmp(&x.1));
    for (k, n) in w.iter().take(15) { println!("  {n:5}  {k}"); }
}
