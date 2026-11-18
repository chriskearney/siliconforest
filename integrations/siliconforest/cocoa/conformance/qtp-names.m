// qtp-names.m - the names Cocoa patches 0340-0366 and the framework wrappers add (first user: Apple's
// QuickTime Player, docs/roadmap/issues/SF-AI-quicktime.md), checked without a window.
// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
//
// Builds here (../build-conformance.nix) and on macOS:
//   clang -fno-objc-arc -framework AppKit -framework QuartzCore -framework CoreAudio qtp-names.m -o qtp-names
// Every name is looked up when the program runs (NSClassFromString, dlsym), so a system without one says
// "QTPNAMES FAIL <what>" instead of not starting. Values are printed as "QTPNAMES value <name> <value>" for
// comparison with macOS (the text-style names are believed, not known). Exit status 0 when nothing failed.
#import <AppKit/AppKit.h>
#import <QuartzCore/CALayer.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <dlfcn.h>
#include <stdio.h>
#include <unistd.h>

static int failed;

static void check(BOOL ok, NSString *what)
{
    if (!ok)
        failed++;
    printf("QTPNAMES %s %s\n", ok ? "ok" : "FAIL", [what UTF8String]);
}

static void *symbol(const char *name)
{
    return dlsym(RTLD_DEFAULT, name);
}

static NSString *stringConstant(const char *name)
{
    NSString *const *p = symbol(name);
    printf("QTPNAMES value %s %s\n", name, p ? [*p UTF8String] : "(missing)");
    return p ? *p : nil;
}

#define SEND(type, ...) ((type (*)(id, SEL, ##__VA_ARGS__))objc_msgSend)

static void appKitNames(void)
{
    const char *bindings[] = { "NSEnabledBinding", "NSHiddenBinding", "NSTitleBinding", "NSToolTipBinding" };
    const char *expected[] = { "enabled", "hidden", "title", "toolTip" };
    for (int i = 0; i < 4; i++) {
        NSString *value = stringConstant(bindings[i]);
        check([value isEqualToString:[NSString stringWithUTF8String:expected[i]]], [NSString stringWithFormat:@"%s is \"%s\"", bindings[i], expected[i]]);
    }
    const char *styles[] = { "NSFontTextStyleLargeTitle", "NSFontTextStyleTitle1", "NSFontTextStyleTitle2", "NSFontTextStyleTitle3",
                             "NSFontTextStyleHeadline", "NSFontTextStyleSubheadline", "NSFontTextStyleBody", "NSFontTextStyleCallout",
                             "NSFontTextStyleFootnote", "NSFontTextStyleCaption1", "NSFontTextStyleCaption2" };
    const CGFloat sizes[] = { 26, 22, 17, 15, 13, 11, 13, 12, 10, 10, 10 };
    SEL preferred = sel_registerName("preferredFontForTextStyle:options:");
    for (int i = 0; i < 11; i++) {
        NSString *style = stringConstant(styles[i]);
        NSFont *font = style && [NSFont respondsToSelector:preferred] ? SEND(NSFont *, NSString *, NSDictionary *)((id)[NSFont class], preferred, style, nil) : nil;
        printf("QTPNAMES value %s.font %s %.1f\n", styles[i], font ? [[font fontName] UTF8String] : "(none)", font ? [font pointSize] : 0.0);
        check(font != nil && [font pointSize] == sizes[i], [NSString stringWithFormat:@"%s gives a %.0f point font", styles[i], sizes[i]]);
    }
    Class click = NSClassFromString(@"NSClickGestureRecognizer");
    id recognizer = click ? [[click alloc] initWithTarget:nil action:NULL] : nil;
    check(recognizer && SEND(NSInteger)(recognizer, sel_registerName("numberOfClicksRequired")) == 1 &&
          SEND(NSUInteger)(recognizer, sel_registerName("buttonMask")) == 1, @"NSClickGestureRecognizer: one click of the primary button");
    [recognizer release];
}

static void fileWrapper(NSString *dir)
{
    NSURL *folder = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"bundle"] isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtPath:[folder path] withIntermediateDirectories:YES attributes:nil error:NULL];
    [@"hello" writeToFile:[[folder path] stringByAppendingPathComponent:@"a.txt"] atomically:NO encoding:NSUTF8StringEncoding error:NULL];
    SEL initURL = sel_registerName("initWithURL:options:error:");
    if (![NSFileWrapper instancesRespondToSelector:initURL]) {
        check(NO, @"NSFileWrapper has initWithURL:options:error:");
        return;
    }
    NSError *error = nil;
    NSFileWrapper *wrapper = SEND(id, NSURL *, NSUInteger, NSError **)([NSFileWrapper alloc], initURL, folder, 1 /* immediate */, &error);
    NSFileWrapper *child = [[wrapper fileWrappers] objectForKey:@"a.txt"];
    NSString *text = child ? [[[NSString alloc] initWithData:[child regularFileContents] encoding:NSUTF8StringEncoding] autorelease] : nil;
    check(wrapper && [wrapper isDirectory] && [[wrapper fileWrappers] count] == 1 && [text isEqualToString:@"hello"],
          @"NSFileWrapper reads a folder and its file from a URL");
    NSURL *copy = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"copy"] isDirectory:YES];
    BOOL wrote = SEND(BOOL, NSURL *, NSUInteger, NSURL *, NSError **)(wrapper, sel_registerName("writeToURL:options:originalContentsURL:error:"), copy, 0, nil, &error);
    NSString *back = [NSString stringWithContentsOfFile:[[copy path] stringByAppendingPathComponent:@"a.txt"] encoding:NSUTF8StringEncoding error:NULL];
    check(wrote && [back isEqualToString:@"hello"], @"NSFileWrapper writes itself to a URL");
    check(SEND(BOOL, NSURL *)(wrapper, sel_registerName("matchesContentsOfURL:"), folder), @"NSFileWrapper matches what it was read from");
    check(SEND(BOOL, NSURL *, NSUInteger, NSError **)(wrapper, sel_registerName("readFromURL:options:error:"), folder, 0, &error),
          @"NSFileWrapper reads the same folder again");
    error = nil;
    id missing = SEND(id, NSURL *, NSUInteger, NSError **)([NSFileWrapper alloc], initURL, [NSURL fileURLWithPath:@"/nonexistent/qtp"], 0, &error);
    check(missing == nil && [error code] == 260, @"NSFileWrapper: a missing file is error 260 (no such file)");
    [wrapper release];
}

static void displays(void)
{
    typedef int32_t (*Lookup)(CGRect, uint32_t, uint32_t *, uint32_t *);
    typedef int32_t (*PointLookup)(CGPoint, uint32_t, uint32_t *, uint32_t *);
    Lookup withRect = (Lookup)symbol("CGGetDisplaysWithRect");
    PointLookup withPoint = (PointLookup)symbol("CGGetDisplaysWithPoint");
    uint32_t list[8], count = 0;
    CGRect main = CGDisplayBounds(CGMainDisplayID());
    check(withRect && withRect(CGRectInset(main, 10, 10), 8, list, &count) == 0 && count >= 1 && list[0] == CGMainDisplayID(),
          @"CGGetDisplaysWithRect finds the main display in its own bounds");
    check(withRect && withRect(CGRectMake(main.origin.x - 1e6, 0, 10, 10), 8, list, &count) == 0 && count == 0,
          @"CGGetDisplaysWithRect finds none far outside");
    check(withPoint && withPoint(CGPointMake(CGRectGetMidX(main), CGRectGetMidY(main)), 0, NULL, &count) == 0 && count >= 1,
          @"CGGetDisplaysWithPoint counts the display under the main display's centre");
}

static void textLayer(void)
{
    Class text = NSClassFromString(@"CATextLayer");
    if (!text) {
        check(NO, @"CATextLayer exists");
        return;
    }
    CALayer *layer = [[text alloc] init];
    check(SEND(CGFloat)(layer, sel_registerName("fontSize")) == 36, @"CATextLayer's default font size is 36");
    stringConstant("kCATruncationMiddle");
    stringConstant("kCAAlignmentCenter");
    SEND(void, id)(layer, sel_registerName("setString:"), @"QuickTime");
    [layer setBounds:CGRectMake(0, 0, 200, 50)];
    size_t w = 200, h = 50;
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, w, h, 8, w * 4, space, kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(space);
    [layer drawInContext:context];
    const uint8_t *pixels = CGBitmapContextGetData(context);
    size_t drawn = 0;
    for (size_t i = 0; i < w * h; i++)
        drawn += pixels[i * 4 + 3] != 0;
    printf("QTPNAMES value CATextLayer.drawnPixels %zu\n", drawn);
    check(drawn > 100, @"CATextLayer draws its string");
    CGContextRelease(context);
    [layer release];
}

static void keyframes(void)
{
    Class keyframe = NSClassFromString(@"CAKeyframeAnimation");
    if (!keyframe) {
        check(NO, @"CAKeyframeAnimation exists");
        return;
    }
    id animation = SEND(id, NSString *)((id)keyframe, sel_registerName("animationWithKeyPath:"), @"opacity");
    NSArray *values = [NSArray arrayWithObjects:[NSNumber numberWithFloat:0], [NSNumber numberWithFloat:1], [NSNumber numberWithFloat:0.5], nil];
    SEND(void, NSArray *)(animation, sel_registerName("setValues:"), values);
    SEND(void, NSArray *)(animation, sel_registerName("setKeyTimes:"), [NSArray arrayWithObjects:@0, @0.25, @1, nil]);
    NSString *mode = SEND(NSString *)(animation, sel_registerName("calculationMode"));
    printf("QTPNAMES value CAKeyframeAnimation.calculationMode %s\n", mode ? [mode UTF8String] : "(nil)");
    check([SEND(NSArray *)(animation, sel_registerName("values")) isEqual:values] && [mode isEqualToString:@"linear"] &&
          [[SEND(NSArray *)(animation, sel_registerName("keyTimes")) objectAtIndex:1] doubleValue] == 0.25,
          @"CAKeyframeAnimation keeps values and key times, linear by default");
    printf("QTPNAMES info keyframe interpolation happens in the renderer and is not reached from here\n");
}

static void constraints(void)
{
    Class constraintClass = NSClassFromString(@"CAConstraint"), manager = NSClassFromString(@"CAConstraintLayoutManager");
    if (!constraintClass || !manager || ![CALayer instancesRespondToSelector:sel_registerName("setLayoutManager:")]) {
        check(NO, @"CAConstraint, CAConstraintLayoutManager and CALayer's layoutManager exist");
        return;
    }
    SEL make = sel_registerName("constraintWithAttribute:relativeTo:attribute:scale:offset:");
    CALayer *parent = [CALayer layer], *a = [CALayer layer], *b = [CALayer layer];
    [parent setBounds:CGRectMake(0, 0, 400, 100)];
    [a setName:@"a"];
    [a setFrame:CGRectMake(20, 0, 80, 30)];
    [b setFrame:CGRectMake(0, 5, 10, 30)];
    id minX = SEND(id, int, NSString *, int, CGFloat, CGFloat)((id)constraintClass, make, 0 /* min x */, @"a", 2 /* max x */, 1, 10);
    id width = SEND(id, int, NSString *, int, CGFloat, CGFloat)((id)constraintClass, make, 3 /* width */, @"superlayer", 3, 0.5, 0);
    SEND(void, NSArray *)(b, sel_registerName("setConstraints:"), [NSArray arrayWithObjects:minX, width, nil]);
    [parent addSublayer:a];
    [parent addSublayer:b];
    SEND(void, id)(parent, sel_registerName("setLayoutManager:"), SEND(id)((id)manager, sel_registerName("layoutManager")));
    [parent setNeedsLayout];
    [parent layoutIfNeeded];
    CGRect frame = [b frame];
    printf("QTPNAMES value CAConstraintLayoutManager.frame %.0f %.0f %.0f %.0f\n", frame.origin.x, frame.origin.y, frame.size.width, frame.size.height);
    check(frame.origin.x == 110 && frame.size.width == 200 && frame.origin.y == 5 && frame.size.height == 30,
          @"CAConstraintLayoutManager places a sublayer by its constraints");
}

static void audioListenerBlock(void)
{
    typedef struct { uint32_t selector, scope, element; } Address;
    typedef int32_t (*Listen)(uint32_t, const Address *, dispatch_queue_t, void (^)(uint32_t, const Address *));
    void *coreAudio = dlopen("/System/Library/Frameworks/CoreAudio.framework/CoreAudio", RTLD_NOW);
    Listen add = coreAudio ? (Listen)dlsym(coreAudio, "AudioObjectAddPropertyListenerBlock") : NULL;
    Listen remove = coreAudio ? (Listen)dlsym(coreAudio, "AudioObjectRemovePropertyListenerBlock") : NULL;
    Address defaultOutput = { 'dOut', 'glob', 0 };
    void (^block)(uint32_t, const Address *) = ^(uint32_t count, const Address *addresses) { (void)count; (void)addresses; };
    int32_t added = add ? add(1 /* the system object */, &defaultOutput, dispatch_get_main_queue(), block) : -1;
    int32_t removed = remove ? remove(1, &defaultOutput, dispatch_get_main_queue(), block) : -1;
    printf("QTPNAMES value AudioObjectPropertyListenerBlock add %d remove %d\n", (int)added, (int)removed);
    check(added == 0 && removed == 0, @"CoreAudio adds and removes a block listener for the default output device");
}

static void urlKeys(NSString *dir)
{
    NSString *file = [dir stringByAppendingPathComponent:@"key.txt"];
    [@"x" writeToFile:file atomically:NO encoding:NSUTF8StringEncoding error:NULL];
    NSURL *url = [NSURL fileURLWithPath:file], *root = [NSURL fileURLWithPath:@"/"];
    const char *keys[] = { "NSURLNameKey", "NSURLFileSizeKey", "NSURLContentModificationDateKey", "NSURLParentDirectoryURLKey",
                           "NSURLIsVolumeKey", "NSURLVolumeNameKey", "NSURLVolumeIsReadOnlyKey", "NSURLHasHiddenExtensionKey",
                           "NSURLEffectiveIconKey", "NSURLFileResourceIdentifierKey" };
    NSString *names[10];
    for (int i = 0; i < 10; i++) {
        names[i] = stringConstant(keys[i]);
        check(names[i] != nil, [NSString stringWithFormat:@"%s exists", keys[i]]);
    }
    if (!names[3] || !names[4] || !names[9])
        return;
    id parent = nil, isVolume = nil, rootIsVolume = nil, first = nil, second = nil, readOnly = nil;
    [url getResourceValue:&parent forKey:names[3] error:NULL];
    [url getResourceValue:&isVolume forKey:names[4] error:NULL];
    [root getResourceValue:&rootIsVolume forKey:names[4] error:NULL];
    [url getResourceValue:&first forKey:names[9] error:NULL];
    [[NSURL fileURLWithPath:file] getResourceValue:&second forKey:names[9] error:NULL];
    [root getResourceValue:&readOnly forKey:names[6] error:NULL];
    check([[[parent path] stringByStandardizingPath] isEqualToString:[dir stringByStandardizingPath]], @"NSURLParentDirectoryURLKey is the file's folder");
    check(isVolume && ![isVolume boolValue] && [rootIsVolume boolValue], @"NSURLIsVolumeKey: a file is not a volume, / is");
    check(first != nil && [first isEqual:second], @"NSURLFileResourceIdentifierKey is equal for the same file");
    check([readOnly isKindOfClass:[NSNumber class]], @"NSURLVolumeIsReadOnlyKey answers for /");
}

static void fileCoordinator(NSString *dir)
{
    Class coordinatorClass = NSClassFromString(@"NSFileCoordinator");
    if (!coordinatorClass) {
        check(NO, @"NSFileCoordinator exists");
        return;
    }
    id coordinator = [[coordinatorClass alloc] init];
    NSURL *url = [NSURL fileURLWithPath:dir];
    __block int calls = 0;
    NSError *error = (id)1;
    SEND(void, NSURL *, NSUInteger, NSError **, void (^)(NSURL *))(coordinator, sel_registerName("coordinateReadingItemAtURL:options:error:byAccessor:"),
                                                                   url, 0, &error, ^(NSURL *u) { calls += [[u path] isEqualToString:[url path]]; });
    check(calls == 1 && error == nil, @"NSFileCoordinator runs a reader once, at once, with the same URL");
    [coordinator release];
}

static void paths(void)
{
    struct { NSArray *components; NSString *path; } cases[] = {
        { @[ @"/", @"usr", @"lib" ], @"/usr/lib" },
        { @[ @"a", @"b" ], @"a/b" },
        { @[ @"a/", @"", @"/b/" ], @"a/b" },
        { @[ @"/" ], @"/" },
        { @[], @"" },
    };
    SEL selector = sel_registerName("pathWithComponents:");
    if (![NSString respondsToSelector:selector]) {
        check(NO, @"+[NSString pathWithComponents:] exists");
        return;
    }
    for (unsigned i = 0; i < sizeof cases / sizeof cases[0]; i++) {
        NSString *path = SEND(NSString *, NSArray *)([NSString class], selector, cases[i].components);
        check([path isEqualToString:cases[i].path],
              [NSString stringWithFormat:@"pathWithComponents: %@ is \"%@\" (got \"%@\")",
                  [cases[i].components componentsJoinedByString:@","], cases[i].path, path]);
    }
}

static void bundles(void)
{
    NSString *none = nil;   // (a variable: the macOS SDK declares the argument nonnull)
    check([NSBundle bundleWithPath:none] == nil, @"+[NSBundle bundleWithPath:nil] is nil");
    check([NSBundle bundleWithPath:@""] == nil, @"+[NSBundle bundleWithPath:@\"\"] is nil");
}

static void fullScreenStrip(void)
{
    /* SiliconForest's menu strip in full screen (AppKit 0362); macOS has no such method: reported, not failed */
    SEL selector = sel_registerName("_sfMenuStripFullScreenModeForOptions:");
    if (![NSWindow respondsToSelector:selector]) {
        printf("QTPNAMES value full-screen-strip (no strip here)\n");
        return;
    }
    int (*mode)(id, SEL, NSUInteger) = (int (*)(id, SEL, NSUInteger))objc_msgSend;
    check(mode([NSWindow class], selector, (1 << 10) | (1 << 2) | (1 << 0)) == 1, @"full screen with macOS's default options: the strip auto-hides");
    check(mode([NSWindow class], selector, (1 << 10) | (1 << 3)) == 2, @"NSApplicationPresentationHideMenuBar: the strip is hidden");
    check(mode([NSWindow class], selector, (1 << 10)) == 0, @"options without a menu-bar bit keep the strip");
}

/* NSURL bookmark data (libFoundation 0365) as macOS's API behaves: made for an existing file URL and resolved to it
   again, not stale while the same file is there, stale when another file has taken its path, an error when nothing
   is there; relative to a folder that moved; resource values kept; a bookmark file written and read back */
static void bookmarks(NSString *dir)
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *folder = [dir stringByAppendingPathComponent:@"bookmarks"], *path = [folder stringByAppendingPathComponent:@"film.mov"];
    [fm createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:NULL];
    [[@"one" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:path atomically:NO];
    NSURL *url = [NSURL fileURLWithPath:path];
    NSError *error = nil;
    BOOL stale = YES;
    SEL make = @selector(bookmarkDataWithOptions:includingResourceValuesForKeys:relativeToURL:error:);
    if (![url respondsToSelector:make]) {
        check(NO, @"-[NSURL bookmarkDataWithOptions:includingResourceValuesForKeys:relativeToURL:error:] exists");
        return;
    }
    NSData *data = [url bookmarkDataWithOptions:0 includingResourceValuesForKeys:[NSArray arrayWithObject:@"NSURLNameKey"] relativeToURL:nil error:&error];
    check(data != nil && [data length] > 0, [NSString stringWithFormat:@"a file URL gives bookmark data (error %@)", error]);
    NSURL *again = [NSURL URLByResolvingBookmarkData:data options:0 relativeToURL:nil bookmarkDataIsStale:&stale error:&error];
    check([[again path] isEqual:path] && !stale, [NSString stringWithFormat:@"the bookmark resolves to the file, not stale (%@, stale %d)", [again path], stale]);
    NSDictionary *values = [NSURL resourceValuesForKeys:[NSArray arrayWithObject:@"NSURLNameKey"] fromBookmarkData:data];
    printf("QTPNAMES value bookmark-resource-values %s\n", [[values description] UTF8String]);
    NSString *bookmarkFile = [dir stringByAppendingPathComponent:@"film.bookmark"];
    check([NSURL writeBookmarkData:data toURL:[NSURL fileURLWithPath:bookmarkFile] options:0 error:&error] &&
          [[NSURL bookmarkDataWithContentsOfURL:[NSURL fileURLWithPath:bookmarkFile] error:&error] isEqual:data], @"a bookmark file is written and read back");
    // another file takes the path: found, stale
    NSString *other = [folder stringByAppendingPathComponent:@"other.mov"];
    [[@"two" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:other atomically:NO];
    rename([other fileSystemRepresentation], [path fileSystemRepresentation]);
    again = [NSURL URLByResolvingBookmarkData:data options:0 relativeToURL:nil bookmarkDataIsStale:&stale error:&error];
    check([[again path] isEqual:path] && stale, @"another file at the path: resolved, stale");
    // relative to a folder that moved
    NSURL *folderURL = [NSURL fileURLWithPath:folder isDirectory:YES];
    NSData *relative = [url bookmarkDataWithOptions:0 includingResourceValuesForKeys:nil relativeToURL:folderURL error:&error];
    NSString *moved = [dir stringByAppendingPathComponent:@"bookmarks-moved"];
    rename([folder fileSystemRepresentation], [moved fileSystemRepresentation]);
    again = [NSURL URLByResolvingBookmarkData:relative options:0 relativeToURL:[NSURL fileURLWithPath:moved isDirectory:YES] bookmarkDataIsStale:&stale error:&error];
    check([[again path] isEqual:[moved stringByAppendingPathComponent:@"film.mov"]], [NSString stringWithFormat:@"relative to a folder that moved: found in the new folder (%@)", [again path]]);
    // nothing there any more
    error = nil;
    again = [NSURL URLByResolvingBookmarkData:data options:0 relativeToURL:nil bookmarkDataIsStale:&stale error:&error];
    check(again == nil && [[error domain] isEqual:NSCocoaErrorDomain] && [error code] == NSFileNoSuchFileError, [NSString stringWithFormat:@"no file at the path: nil and NSFileNoSuchFileError (%@)", error]);
    error = nil;
    check([[NSURL URLWithString:@"https://example.com/"] bookmarkDataWithOptions:0 includingResourceValuesForKeys:nil relativeToURL:nil error:&error] == nil && error != nil, @"a URL that is not a file's gives no bookmark and an error");
    check([NSURL URLByResolvingBookmarkData:[NSData dataWithBytes:"junk" length:4] options:0 relativeToURL:nil bookmarkDataIsStale:&stale error:&error] == nil && error != nil, @"data that is not a bookmark resolves to nil with an error");
}

int main(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    setvbuf(stdout, NULL, _IOLBF, 0);
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"qtp-names-%d", (int)getpid()]];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    appKitNames();
    fileWrapper(dir);
    displays();
    textLayer();
    keyframes();
    constraints();
    audioListenerBlock();
    urlKeys(dir);
    fileCoordinator(dir);
    paths();
    bundles();
    fullScreenStrip();
    bookmarks(dir);
    [[NSFileManager defaultManager] removeItemAtPath:dir error:NULL];
    printf("QTPNAMES result failed=%d\n", failed);
    [pool release];
    return failed ? 1 : 0;
}
