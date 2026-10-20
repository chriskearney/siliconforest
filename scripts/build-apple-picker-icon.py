#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Reproduce the Apple startup-volume icon from the shared SVG emblem."""
import argparse
from pathlib import Path
import struct
import subprocess
import tempfile

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--source',type=Path,default=Path(__file__).resolve().parents[1]/'branding/apple-picker/emblem.svg')
p.add_argument('--output',type=Path,required=True)
a=p.parse_args()
if a.output.exists():p.error('output already exists')
version=subprocess.check_output(['resvg','--version'],text=True).strip()
if version.split()[-1]!='0.48.1':p.error('require resvg 0.48.1')
slots=[(16,b'icp4'),(32,b'icp5'),(64,b'icp6'),(128,b'ic07'),(256,b'ic08'),(512,b'ic09'),(1024,b'ic10')]
blocks=[]
with tempfile.TemporaryDirectory(prefix='sf-picker-icon-') as tmp:
 for size,tag in slots:
  png=Path(tmp)/(str(size)+'.png')
  subprocess.run(['resvg','--width',str(size),'--height',str(size),str(a.source),str(png)],check=True)
  blob=png.read_bytes()
  if blob[:16]!=b'\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR' or struct.unpack('>II',blob[16:24])!=(size,size) or blob[24:26]!=bytes([8,6]):
   raise SystemExit('renderer did not produce the required RGBA PNG')
  blocks.append(tag+struct.pack('>I',len(blob)+8)+blob)
 body=b''.join(blocks)
 with a.output.open('xb') as out:out.write(b'icns'+struct.pack('>I',len(body)+8)+body)
