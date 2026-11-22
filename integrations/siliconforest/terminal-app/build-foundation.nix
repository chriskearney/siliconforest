# SPDX-License-Identifier: MIT
# libFoundation for macOS applications (GitHub issue 52, docs/roadmap/issues/SF-Y-terminal-app.md):
# upstream PureDarwin's Foundation for arm64 at the revision of ../rebase/pd.nix (the build the
# disk root has as /usr/lib/libFoundation.dylib) with ./patches/foundation-macos-applications.patch:
#   NSKeyedUnarchiver reads archives made by Apple's NSKeyedArchiver ($archiver/$top/$objects with
#     UID references: compiled nibs, archived fonts and colours); -replaceObject:withObject:
#   a message nothing answers raises NSInvalidArgumentException (objc4's own method ends the
#     process); the forwarding trampoline has unwind information, so the exception reaches handlers
#   key-value coding: collection operators (@count ...), -mutableArrayValueForKey:
#   -[NSAttributedString init], -[NSString cStringUsingEncoding:] that converts, and the
#     methods Terminal.app sends that were missing (strings, index sets, URLs, coders ...)
#   NSUnrecognizedSelectorBacktrace=1 / NSExceptionRaiseBacktrace=1: where a failure comes from
#   key-value observing remembers +keyPathsForValuesAffectingValueForKey: per class and key (it was
#     asked for each observation at every change; Apple's Activity Monitor, GitHub issue 53)
#   (14 November, evening) CFAutorelease reaches the autorelease pool (Runtime.subproj/SFAutoreleaseCF.h,
#     put in front of every source: SiliconForest's CoreFoundation returned its own objects without
#     autoreleasing them, so every convenience constructor here leaked); from Finch (MIT OR
#     Apache-2.0, notices in the files): NSHashTable's and NSMapTable's object API, NSPointerArray and
#     NSPointerFunctions (Collections.subproj/NSPointerCollections.m), NSDecimalNumber and the NSDecimal
#     functions (Numeric.subproj/NSDecimal.m), NSPersonNameComponents and its formatter
#     (Formatters.subproj/NSPersonNameComponents.m); -[NSData rangeOfData:options:range:], NSCalendar's
#     identifier, NSDateComponents' calendar and time zone, -[NSSet setByAddingObject:] (the Finch
#     frameworks' requests, runs/m1-coord/requests-for-CLAUDE.md); NSIndexPath (Collections.subproj/
#     NSIndexPath.m, from the Foundation wrapper: AppKit's collection view needs it). The four new sources
#     are compiled after NSHashTable.m (upstream's recipe names its sources).
#   (14 November, night; COCOA4, found with probe/sf-heap.c) +alloc of NSArray/NSMutableArray, NSDictionary/
#     NSMutableDictionary and NSSet/NSMutableSet gives one placeholder per class (each +alloc made an instance
#     nothing could free: every [[NSMutableArray alloc] init...] leaked one); NSStringFromClass/Selector,
#     -stringByAppendingPathComponent:/-PathExtension:, -stringByDeletingPathExtension, -[NSBundle resourcePath]
#     autoreleased (+0, as Cocoa; each leaked at every call); -[NSURL initWithScheme:host:path:];
#     NSDateInterval's secure coding (Finch's, NSFoundationExtras.m) and -[NSUserActivity targetContentIdentifier]
#     (Codex's Intents requests)
#   (18 November; QTP) ../cocoa/patches/0347: -[NSURL getResourceValue:forKey:error:] answers the parent directory,
#     volume, read-only, hidden-extension and file-identity keys (first user: Apple's QuickTime Player)
#   ../cocoa/patches/0348: -[NSBundle initWithPath:] with no path is nil, as on macOS (QuickTime Player crashed at
#     launch asking for a bundle it does not ship), and a failed initialisation releases the receiver
#   ../cocoa/patches/0349: +[NSString pathWithComponents:] (missing; QuickTime Player got an exception at launch)
#   ../cocoa/patches/0352: -[NSURL fileReferenceURL] answered by the file's path URL (no reference URLs here),
#     -filePathURL, -isFileReferenceURL (QuickTime Player asks when it reads a movie)
#   ../cocoa/patches/0354: change notifications of to-many keys (at indexes; by set mutation), as on macOS
#   ../cocoa/patches/0355: NSFileManager's URL forms of remove, copy and directory contents, -[NSSet
#     setByAddingObjectsFromSet:], security-scoped access (none here), -setResourceValue:forKey:error: (refused),
#     NSLocale's display names for language, country and locale codes
#   ../cocoa/patches/0359: -[NSError recoveryAttempter] and -helpAnchor (AppKit asks when it presents an error)
#   ../cocoa/patches/0361: NSIntersectionRect is zero only when the rectangles provably do not overlap, as on macOS
#     (an unbounded rectangle met a finite one as zero: QuickTime Player opened every movie at its smallest size)
#   ../cocoa/patches/0365: NSURL bookmark data as macOS's API has it (made for a file, resolved by its path, stale when
#     another file is there now, resource values kept, bookmark files read and written); it was refused (QuickTime
#     Player keeps its recent documents as bookmarks: its Open Recent menu stayed empty)
# A file every Objective-C program loads: QEMU pass and the guarded procedure before it replaces
# the disk root's; until then it is tried from a scratch prefix (DYLD_LIBRARY_PATH).
#
#   nix-build --extra-experimental-features 'nix-command flakes' --no-out-link build-foundation.nix
let
  pd = (import ../rebase/pd.nix).pd;
in pd.packages.x86_64-linux."foundation-arm64".overrideAttrs (old: {
  pname = "siliconforest-foundation-macos-apps";
  patches = (old.patches or []) ++ [
    ./patches/foundation-macos-applications.patch
    # -performSelectorOnMainThread:withObject:waitUntilDone:NO is queued on the main thread too
    # (VLC media player: docs/roadmap/issues/SF-AH-vlc.md)
    ./patches/foundation-main-thread-perform-is-queued.patch
    ../cocoa/patches/0347-foundation-url-resource-values.patch
    ../cocoa/patches/0348-foundation-bundle-without-a-path-is-nil.patch
    ../cocoa/patches/0349-foundation-path-with-components.patch
    ../cocoa/patches/0352-foundation-file-reference-urls-by-path.patch
    ../cocoa/patches/0354-foundation-to-many-change-notifications.patch
    ../cocoa/patches/0355-foundation-file-set-locale-names.patch
    ../cocoa/patches/0359-foundation-error-recovery-attempter.patch
    ../cocoa/patches/0361-foundation-intersection-of-unbounded-rects.patch
    # NSURL bookmark data (QuickTime Player's Open Recent; QTP2, branch media-quicktime: cocoa 0365)
    ../cocoa/patches/0365-foundation-url-bookmarks.patch
  ];
  patchFlags = [ "-p4" ];
  buildPhase = let
    r = builtins.replaceStrings
      [ "Collections.subproj/NSHashTable " ''CFLAGS="-x objective-c '' ]
      [ "Collections.subproj/NSHashTable Collections.subproj/NSPointerCollections Collections.subproj/NSIndexPath Numeric.subproj/NSDecimal Formatters.subproj/NSPersonNameComponents "
        ''CFLAGS="-include Runtime.subproj/SFAutoreleaseCF.h -x objective-c '' ]
      old.buildPhase;
    has = n: builtins.length (builtins.split n r) > 1;
  in assert has "NSPointerCollections" && has "SFAutoreleaseCF"; r;
})
