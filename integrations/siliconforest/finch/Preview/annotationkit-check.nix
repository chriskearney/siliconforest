# SPDX-License-Identifier: MIT
let
  e = import ../environment.nix;
  a = import ../../cocoa/arm64.nix;
  candidate = import ./annotationkit.nix;
in e.pkgs.runCommand "siliconforest-preview-annotationkit-static-check" {
  nativeBuildInputs = [ e.pkgs.python3 ];
} ''
  mkdir -p $out
  python3 ${./check-recap.py} --root ${candidate} --macho ${../../homebrew} \
    --framework AnnotationKit --probe annotationkit-probe --current 1.0 \
    --class AKAnnotation --class AKStrokedAnnotation --class AKShapeAnnotation \
    --class AKArrowAnnotation --class AKArrowShapeAnnotation --class AKRectangularShapeAnnotation \
    --class AKThoughtBubbleAnnotation --class AKBorderMaskAnnotation --class AKImageAnnotation \
    --class AKNoteAnnotation --class AKPageModelController --class AKModelController \
    --class AKToolController --class AKController --class SFAnnotationReaderOverlay \
    --class SFAnnotationUnsupportedException \
    --symbol _AKAnnotationChangeObjectKey --symbol _AKAnnotationPropertiesChangedNotification \
    --symbol _AKAnnotationsAddedOrRemovedNotification --symbol _AKControllerSuggestedTouchBarItemChanged \
    --symbol _AKControllerWillTeardownNotification --symbol _AKSelectionChangedNotification \
    --symbol _AKStatisticsDocumentTypeImage --symbol _AKStatisticsDocumentTypePDF \
    --symbol _AKTouchBarItemIdentifierHighlights --symbol _AKTouchBarItemIdentifierMain \
    --under ${e.libsystem} --under ${a.base.libobjc} --under ${a.base.foundation} \
    --under ${a.base.corefoundation} --under ${a.appDeps.appkit} \
    --under ${a.appDeps.coregraphics} --under ${a.appDeps.onyx2d} \
    >$out/report.json || { cat $out/report.json; exit 1; }
  cat $out/report.json
''
