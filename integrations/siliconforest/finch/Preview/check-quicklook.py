#!/usr/bin/env python3
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Check required imports, preserved QTP API and new reader metadata; no execution."""
import argparse
import hashlib
import json
from pathlib import Path
import sys

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--root',required=True)
p.add_argument('--macho',required=True)
p.add_argument('--under',action='append',default=[])
a=p.parse_args()
sys.path.insert(0,a.macho)
import hb_macho
from sf_gapscan import Root
r=Root(a.root,under=a.under);r.prefer='arm64'
keys=['_QLSeamlessOpeningDisplayState'+s+'Key' for s in ['ContentsEDRStrength','Page','Password']]
classes={'QLPreviewDocument','QLPreviewView','QLSeamlessDocumentOpener','QLSeamlessDocumentCloser','SFQuickLookReaderException'}
expected={
 '/System/Library/Frameworks/QuickLook.framework/Versions/A/QuickLook':set(keys+['_QLThumbnailImageCreate','_kQLThumbnailOptionIconModeKey','_kQLThumbnailOptionScaleFactorKey','_QLSeamlessOpeningDisplayStateTimeKey']),
 '/System/Library/Frameworks/QuickLookUI.framework/Versions/A/QuickLookUI':{f'_OBJC_{kind}_$_{name}'for name in classes for kind in ['CLASS','METACLASS']},
 '/bin/quicklook-reader-probe':set(),
}
problems=[];images=[]
for logical,symbols in expected.items():
 path=r.resolve(logical)
 if path is None:problems.append('absent '+logical);continue
 m=r.macho(path);exports,_=m.exported();defined,_=m.objc_defined()
 if m.cputype!=hb_macho.CPU_ARM64:problems.append('not arm64 '+logical)
 if not symbols.issubset(exports):problems.append({'missing_exports':sorted(symbols-set(exports)),'image':logical})
 if logical.endswith('/QuickLookUI') and set(defined)!=classes:problems.append('unexpected reader classes')
 if logical.endswith('/QuickLook') and defined:problems.append('unexpected class in data provider')
 if logical.startswith('/System/') and (not m.id or m.id['name']!=logical or m.id['compat']!='1.0' or m.id['current']!='1.0'):problems.append('install/version differs '+logical)
 count=0
 for name,ordinal,weak in m.imports():
  if not 0<ordinal<=len(m.dylibs):problems.append('unhandled ordinal '+name);continue
  dep=m.dylibs[ordinal-1];got=r.find(dep['name'],logical,logical,m.rpaths)
  if got is None or name not in r.exports(*got):
   if not weak and dep['kind']!='weak':problems.append('unresolved '+logical+': '+name)
  count+=1
 bad=hb_macho.verify(path.read_bytes()) if m.signature() else None
 if bad!=0:problems.append('signature missing/invalid '+logical)
 images.append({'logical':logical,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'classes':sorted(defined),'direct_imports_checked':count,'signature_page_mismatches':bad})
print(json.dumps({'pass':not problems,'scope':'Static required/preserved API and direct import/signature checks only.','images':images,'problems':problems},indent=2))
raise SystemExit(bool(problems))
