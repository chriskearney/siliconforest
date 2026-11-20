#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Own declarations for Finch PDF model and view implementations."""
from pathlib import Path
import re,subprocess,sys
here=Path(__file__).resolve().parent
classes={'PDFAction':'NSObject','PDFActionURL':'PDFAction','PDFActionGoTo':'PDFAction','PDFDestination':'NSObject','PDFBorder':'NSObject','PDFAnnotation':'NSObject','PDFOutline':'NSObject','PDFPage':'NSObject','PDFSelection':'NSObject','PDFDocument':'NSObject','PDFView':'NSView','PDFThumbnailView':'NSView'}
out=here/'include/PDFKit/PDFKit.h'
subprocess.run([sys.executable,str(here.parent/'tools/declarations.py'),sys.argv[1],str(here/'types.h'),str(out),'--class-map',','.join(n+':'+b for n,b in classes.items()),'--categories'],check=True)
s=out.read_text();s=re.sub(r'^[-+] \([^)]*\)\s*_\w+[^;]*;\n','',s,flags=re.M)
for n in classes:
 a=s.index('@interface '+n+' :');b=s.index('@end',a);body=s[a:b]
 for method in re.findall(r'- \(BOOL\)(is[A-Z]\w*)\s*;',body):
  prop=method[2].lower()+method[3:];body+='@property(readonly,getter='+method+') BOOL '+prop+';\n'
 s=s[:a]+body+s[b:]
text=(Path(sys.argv[1])/'PDFKit.m').read_text()
for typ,n in re.findall(r'^(PDF\w+) const (\w+)\s*=',text,re.M):s+='extern '+typ+' const '+n+';\n'
s+='extern const CGFloat kPDFDestinationUnspecifiedValue;\n'
out.write_text(s)
for n in classes:(out.parent/(n+'.h')).write_text('/* SPDX-License-Identifier: MIT */\n#pragma once\n#import <PDFKit/PDFKit.h>\n')
(out.parent/'PDFAnnotationUtilities.h').write_text('/* SPDX-License-Identifier: MIT */\n#pragma once\n#import <PDFKit/PDFKit.h>\n')
