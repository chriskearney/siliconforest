// SPDX-License-Identifier: MIT
// Status 0 only with a Foundation whose key-value observing follows a key path and hears a
// setter that is called directly (../patches/foundation-macos-applications.patch): the
// installer's proof that a process gets the new library (../tools/sf_terminal.sh). Since 14
// November also: key-value coding reaches a scalar instance variable and the accessors named
// -_key and -_setKey:, a subclass of NSAttributedString keeps its own object, and a bundle's
// resource paths are whole paths (the second build of that patch; the first passes only the
// observing part, so the installer replaces it). The third build also: -valueForKey: keeps where
// it found a key of a class (it says so with the symbol SFFoundationKeyValueCodingCache), and the
// values read through it stay right. The fourth: +[NSURL fileURLWithPath:] of a directory ends in
// "/", as on macOS (Terminal opens a folder's parent otherwise), and of a file does not. The fifth:
// +keyPathsForValuesAffectingValueForKey: is remembered per class and key (the symbol
// SFFoundationKVOAffectingKeysCache). The sixth (the Finch-frameworks requests,
// runs/m1-coord/requests-for-CLAUDE.md): NSDecimalNumber, NSHashTable's and NSMapTable's object API
// with weak entries, NSPointerArray, NSPersonNameComponents and its formatter, -[NSData
// rangeOfData:options:range:], +[NSCalendar calendarWithIdentifier:], -[NSSet setByAddingObject:],
// NSIndexPath in this library (it was in the Foundation wrapper);
// the C map table API keeps working beside them. The eighth (TERM6, 15 November): the indexed and unordered
// accessors of a to-many key called directly are heard (-insertObject:in<Key>AtIndex: and the others). The ninth
// (TERM6): -[NSFileHandle setReadabilityHandler:] calls its handler when a pipe has data, and -availableData gives
// what one read gives (Activity Monitor reads `sample`'s report so). The twelfth (VLC): a main-thread perform that does
// not wait is queued for the run loop.
#include <dlfcn.h>
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdlib.h>
#import <objc/runtime.h>

@interface SFLeaf : NSObject { NSString *_name; }
- (NSString *)name;
- (void)setName:(NSString *)name;
@end
@implementation SFLeaf
- (NSString *)name { return _name; }
- (void)setName:(NSString *)name { [name retain]; [_name release]; _name = name; }
@end
@interface SFRoot : NSObject { SFLeaf *_leaf; @public int heard; }
- (SFLeaf *)leaf;
- (void)setLeaf:(SFLeaf *)leaf;
@end
@implementation SFRoot
- (SFLeaf *)leaf { return _leaf; }
- (void)setLeaf:(SFLeaf *)leaf { [leaf retain]; [_leaf release]; _leaf = leaf; }
- (void)observeValueForKeyPath:(NSString *)path ofObject:(id)object change:(NSDictionary *)change context:(void *)context { heard++; }
@end

@interface SFScalar : NSObject { int _count; BOOL _flag; int hidden; }
- (int)_hidden;
- (void)_setHidden:(int)value;
@end
@implementation SFScalar
- (int)_hidden { return hidden; }
- (void)_setHidden:(int)value { hidden = value; }
@end
@interface SFText : NSAttributedString { NSString *_mine; }
@end
@implementation SFText
- (id)init { if ((self = [super init]) != nil) _mine = @"own"; return self; }
- (NSString *)string { return _mine; }
- (NSDictionary *)attributesAtIndex:(NSUInteger)index effectiveRange:(NSRangePointer)range { if (range) *range = NSMakeRange(0, 3); return [NSDictionary dictionary]; }
@end

// the second build's additions; 0 when all hold
static int second_build(void)
{
    int bad = 0;
    SFScalar *o = [[SFScalar alloc] init];
    @try {
        [o setValue:[NSNumber numberWithInt:7] forKey:@"count"];
        [o setValue:[NSNumber numberWithBool:YES] forKey:@"flag"];
        [o setValue:[NSNumber numberWithInt:9] forKey:@"hidden"];
        if ([[o valueForKey:@"count"] intValue] != 7 || ![[o valueForKey:@"flag"] boolValue] || [[o valueForKey:@"hidden"] intValue] != 9) bad |= 1;
    } @catch (id e) { bad |= 1; }
    SFText *t = [[SFText alloc] init];
    if (object_getClass(t) != [SFText class] || [t length] != 3) bad |= 2;
    [t retain]; [t release]; [t release];
    return bad;
}

// the third build's addition; 0 when it holds
static int third_build(void)
{
    SFScalar *o = [[SFScalar alloc] init];
    SFLeaf *leaf = [[SFLeaf alloc] init];
    int bad = 0;

    if (dlsym(RTLD_DEFAULT, "SFFoundationKeyValueCodingCache") == NULL) bad |= 2;
    [o setValue:[NSNumber numberWithInt:5] forKey:@"count"];
    [leaf setName:@"x"];
    for (int i = 0; i < 1000; i++) {
        NSAutoreleasePool *pool = [NSAutoreleasePool new];
        if ([[o valueForKey:@"count"] intValue] != 5 || [leaf valueForKey:@"name"] != [leaf name]) bad |= 1;
        [pool release];
    }
    [o setValue:[NSNumber numberWithInt:6] forKey:@"count"];
    if ([[o valueForKey:@"count"] intValue] != 6) bad |= 1;
    @try { [o valueForKey:@"nothing"]; bad |= 4; } @catch (id e) { }
    @try { [o valueForKey:@"nothing"]; bad |= 4; } @catch (id e) { }
    return bad;
}

static int fourth_build(void)
{
    int bad = 0;

    if (![[[NSURL fileURLWithPath:@"/usr"] absoluteString] hasSuffix:@"/"]) bad |= 1;
    if ([[[NSURL fileURLWithPath:@"/usr/lib/dyld"] absoluteString] hasSuffix:@"/"]) bad |= 2;
    if (![[[NSURL fileURLWithPath:@"/no/such/dir/"] absoluteString] hasSuffix:@"/"]) bad |= 4;
    return bad;
}

// the fifth build's addition; 0 when it holds. (A dependent key declared with
// +keyPathsForValuesAffecting<Key> is not heard when its affecting key changes through a plain
// setter, with this build and the one of before alike: not checked here.)
static int fifth_build(void)
{
    return dlsym(RTLD_DEFAULT, "SFFoundationKVOAffectingKeysCache") == NULL ? 2 : 0;
}

// the sixth build's additions; 0 when they hold, else the bits of the checks that failed
static int sixth_checks(void);
static int sixth_build(void)
{
    @try { return sixth_checks(); }
    @catch (id e) { return 256; }          // a build without them raises (unrecognized selectors)
}
static int sixth_checks(void)
{
    int bad = 0;
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    Class dn = NSClassFromString(@"NSDecimalNumber");
    if (!dn) bad |= 1;
    else {
        NSDecimalNumber *a = [dn decimalNumberWithString:@"1.25"], *b = [dn decimalNumberWithString:@"2.5"];
        NSDecimalNumber *sum = [a decimalNumberByAdding:b], *quot = [[dn one] decimalNumberByDividingBy:[dn decimalNumberWithString:@"8"]];
        if (![[sum stringValue] isEqual:@"3.75"] || ![[quot stringValue] isEqual:@"0.125"] || [[dn zero] doubleValue] != 0.0
            || [sum compare:b] != NSOrderedDescending)
            bad |= 1;
    }
    NSHashTable *weak = [NSHashTable weakObjectsHashTable];
    NSObject *o1 = [NSObject new], *o2 = [NSObject new];
    NSAutoreleasePool *inner = [NSAutoreleasePool new];  // (reading a weak entry autoreleases its object)
    [weak addObject:o1]; [weak addObject:o2]; [weak addObject:o1];
    NSUInteger before = [[weak allObjects] count];
    [inner release];
    [o2 release];                          // a weak entry goes with its object
    NSUInteger after = [[weak allObjects] count];
    [weak removeObject:o1];
    if (before != 2 || after != 1 || [[weak allObjects] count] != 0) bad |= 2;
    if (getenv("SF_PROBE_VERBOSE")) fprintf(stderr, "weak: %lu %lu %lu (%s)\n", (unsigned long)before, (unsigned long)after, (unsigned long)[[weak allObjects] count], object_getClassName(weak));
    [o1 release];
    NSMapTable *map = [NSMapTable strongToStrongObjectsMapTable];
    [map setObject:@"v" forKey:@"k"];
    NSMapTable *legacy = NSCreateMapTable(NSObjectMapKeyCallBacks, NSObjectMapValueCallBacks, 4);
    NSMapInsert(legacy, @"k", @"w");
    if (![[map objectForKey:@"k"] isEqual:@"v"] || [map count] != 1 || ![(id)NSMapGet(legacy, @"k") isEqual:@"w"] || NSCountMapTable(legacy) != 1)
        bad |= 4;
    NSFreeMapTable(legacy);
    NSPointerArray *pa = [NSClassFromString(@"NSPointerArray") strongObjectsPointerArray];
    [pa addPointer:@"x"]; [pa addPointer:NULL]; [pa compact];
    if ([pa count] != 1) bad |= 8;
    NSPersonNameComponents *n = [[[NSClassFromString(@"NSPersonNameComponents") alloc] init] autorelease];
    n.givenName = @"Ada"; n.familyName = @"Lovelace";
    NSString *full = [NSClassFromString(@"NSPersonNameComponentsFormatter") localizedStringFromPersonNameComponents:n style:NSPersonNameComponentsFormatterStyleDefault options:0];
    if (![full isEqual:@"Ada Lovelace"]) bad |= 16;
    NSData *hay = [NSData dataWithBytes:"abcabc" length:6], *needle = [NSData dataWithBytes:"bc" length:2];
    NSRange f = [hay rangeOfData:needle options:0 range:NSMakeRange(0, 6)];
    NSRange r = [hay rangeOfData:needle options:NSDataSearchBackwards range:NSMakeRange(0, 6)];
    NSRange e = [hay rangeOfData:[NSData data] options:0 range:NSMakeRange(0, 6)];
    if (f.location != 1 || r.location != 4 || e.location != NSNotFound) bad |= 32;
    if (![[[NSCalendar calendarWithIdentifier:@"iso8601"] calendarIdentifier] isEqual:@"iso8601"]) bad |= 64;
    if ([[[NSSet setWithObject:@"a"] setByAddingObject:@"b"] count] != 2) bad |= 128;
    NSIndexPath *ip = [NSClassFromString(@"NSIndexPath") indexPathForItem:2 inSection:1];
    if ([ip item] != 2 || [ip section] != 1 || [ip length] != 2) bad |= 512;
    [pool release];
    return bad;
}

// the seventh build's additions (COCOA4): NSDateInterval's secure coding, -[NSUserActivity
// targetContentIdentifier]; 0 when they hold, else the bits of the checks that failed
static int seventh_checks(void)
{
    int bad = 0;
    NSDate *start = [NSDate dateWithTimeIntervalSinceReferenceDate:1000];
    NSDateInterval *interval = [[[NSDateInterval alloc] initWithStartDate:start duration:60] autorelease];
    if (![[NSDateInterval class] respondsToSelector:@selector(supportsSecureCoding)] || ![interval respondsToSelector:@selector(encodeWithCoder:)])
        bad |= 1;
    else {
        NSData *data = [NSKeyedArchiver archivedDataWithRootObject:interval];
        NSDateInterval *back = data ? [NSKeyedUnarchiver unarchiveObjectWithData:data] : nil;
        if (![back isKindOfClass:[NSDateInterval class]] || [back duration] != 60 || ![[back startDate] isEqualToDate:start])
            bad |= 2;
    }
    Class activity = NSClassFromString(@"NSUserActivity");
    id a = [[activity alloc] initWithActivityType:@"org.siliconforest.probe"];
    if (![a respondsToSelector:@selector(setTargetContentIdentifier:)])
        bad |= 4;
    else {
        [a setTargetContentIdentifier:@"target"];
        if (![[a targetContentIdentifier] isEqual:@"target"])
            bad |= 4;
    }
    [a release];
    return bad;
}
static int seventh_build(void)
{
    @try { return seventh_checks(); }
    @catch (id e) { return 7; }
}

// the eighth build: a to-many key's accessors called directly are heard (Terminal's profiles)
@interface SFList : NSObject { NSMutableArray *_items; NSMutableSet *_tags; @public int heard; }
@end
@implementation SFList
- (id)init { if ((self = [super init]) != nil) { _items = [[NSMutableArray alloc] init]; _tags = [[NSMutableSet alloc] init]; } return self; }
- (NSArray *)items { return _items; }
- (NSUInteger)countOfItems { return [_items count]; }
- (id)objectInItemsAtIndex:(NSUInteger)i { return [_items objectAtIndex:i]; }
- (void)insertObject:(id)o inItemsAtIndex:(NSUInteger)i { [_items insertObject:o atIndex:i]; }
- (void)removeObjectFromItemsAtIndex:(NSUInteger)i { [_items removeObjectAtIndex:i]; }
- (void)replaceObjectInItemsAtIndex:(NSUInteger)i withObject:(id)o { [_items replaceObjectAtIndex:i withObject:o]; }
- (NSSet *)tags { return _tags; }
- (void)addTagsObject:(id)o { [_tags addObject:o]; }
- (void)removeTagsObject:(id)o { [_tags removeObject:o]; }
- (void)observeValueForKeyPath:(NSString *)path ofObject:(id)object change:(NSDictionary *)change context:(void *)context { heard++; }
@end

static int eighth_checks(void)
{
    int bad = 0;
    SFList *list = [[SFList alloc] init];
    [list addObserver:list forKeyPath:@"items" options:NSKeyValueObservingOptionNew context:NULL];
    [list addObserver:list forKeyPath:@"tags" options:NSKeyValueObservingOptionNew context:NULL];
    [list insertObject:@"a" inItemsAtIndex:0];
    if (list->heard != 1 || [[list items] count] != 1) bad |= 1;
    [list replaceObjectInItemsAtIndex:0 withObject:@"b"];
    if (list->heard != 2 || ![[[list items] objectAtIndex:0] isEqual:@"b"]) bad |= 2;
    [list removeObjectFromItemsAtIndex:0];
    if (list->heard != 3 || [[list items] count] != 0) bad |= 4;
    [list addTagsObject:@"t"];
    [list removeTagsObject:@"t"];
    if (list->heard != 5) bad |= 8;
    [list removeObserver:list forKeyPath:@"items"];
    [list removeObserver:list forKeyPath:@"tags"];
    [list insertObject:@"c" inItemsAtIndex:0];
    if (list->heard != 5) bad |= 16;
    return bad;
}
static int eighth_build(void)
{
    @try { return eighth_checks(); }
    @catch (id e) { return 31; }
}

// the ninth build: a pipe's readability handler hears the data written and the end of the stream
static int ninth_checks(void)
{
    NSPipe *pipe = [NSPipe pipe];
    NSFileHandle *reader = [pipe fileHandleForReading];
    __block NSMutableData *got = [[NSMutableData alloc] init];
    __block int ended = 0;

    if (![reader respondsToSelector:@selector(setReadabilityHandler:)])
        return 1;
    [reader setReadabilityHandler:^(NSFileHandle *h) {
        NSData *d = [h availableData];
        @synchronized(got) {
            if ([d length] == 0) { ended = 1; [h setReadabilityHandler:nil]; }
            else [got appendData:d];
        }
    }];
    [[pipe fileHandleForWriting] writeData:[@"sample report" dataUsingEncoding:NSUTF8StringEncoding]];
    [[pipe fileHandleForWriting] closeFile];
    for (int i = 0; i < 200 && !ended; i++)
        usleep(10000);
    int bad = 0;
    @synchronized(got) {
        if (!ended) bad |= 2;
        if (![[[[NSString alloc] initWithData:got encoding:NSUTF8StringEncoding] autorelease] isEqualToString:@"sample report"]) bad |= 4;
    }
    return bad;
}

static int ninth_build(void)
{
    @try { return ninth_checks(); }
    @catch (id e) { return 8; }
}

// the tenth build (TERM7): Foundation's networking is in the library: the cookie, cache and WebSocket classes,
// a cookie made from its properties (no network is used)
static int tenth_checks(void)
{
    int bad = 0;
    Class cookie = NSClassFromString(@"NSHTTPCookie"), cache = NSClassFromString(@"NSURLCache");

    if (cookie == Nil || NSClassFromString(@"NSHTTPCookieStorage") == Nil) bad |= 1;
    if (cache == Nil || NSClassFromString(@"NSURLSessionWebSocketTask") == Nil) bad |= 2;
    if (bad)
        return bad;
    id c = [cookie cookieWithProperties:[NSDictionary dictionaryWithObjectsAndKeys:@"probe", @"Name", @"1", @"Value",
                                         @"example.com", @"Domain", @"/", @"Path", nil]];
    if (![[c name] isEqualToString:@"probe"] || ![[c value] isEqualToString:@"1"]) bad |= 4;
    if ([cache sharedURLCache] == nil) bad |= 8;
    return bad;
}

static int tenth_build(void)
{
    @try { return tenth_checks(); }
    @catch (id e) { return 16; }
}

// the eleventh build (TERM8, what VLC 3's interface needed): NSProxy allows zeroing weak references (an observer that
// is a proxy), -[NSArray initWithArray:copyItems:], +[NSThread sleepForTimeInterval:], NSUserDefaults suites,
// -[NSCalendar ordinalityOfUnit:inUnit:forDate:], +[NSLocale characterDirectionForLanguage:], NSFileManager's display name
@interface SFProbeProxy : NSProxy
@end
@implementation SFProbeProxy
- (instancetype)init { return self; }
- (NSMethodSignature *)methodSignatureForSelector:(SEL)s { return [NSObject instanceMethodSignatureForSelector:@selector(self)]; }
- (void)forwardInvocation:(NSInvocation *)i { [i setReturnValue:&self]; }
@end

static int eleventh_checks(void)
{
    int bad = 0;
    id proxy = [[SFProbeProxy alloc] init];
    id weakSlot = nil;

    objc_storeWeak(&weakSlot, proxy);
    if (objc_loadWeak(&weakSlot) != proxy) bad |= 1;
    objc_storeWeak(&weakSlot, nil);
    [proxy release];
    NSMutableString *m = [NSMutableString stringWithString:@"x"];
    NSArray *copied = [[[NSArray alloc] initWithArray:[NSArray arrayWithObject:m] copyItems:YES] autorelease];
    if ([copied count] != 1 || [copied objectAtIndex:0] == m || ![[copied objectAtIndex:0] isEqual:@"x"]) bad |= 2;
    if (![NSThread respondsToSelector:@selector(sleepForTimeInterval:)]) bad |= 4;
    else [NSThread sleepForTimeInterval:0.001];
    if (![[NSUserDefaults standardUserDefaults] respondsToSelector:@selector(addSuiteNamed:)]) bad |= 8;
    if (![[NSCalendar currentCalendar] respondsToSelector:@selector(ordinalityOfUnit:inUnit:forDate:)]) bad |= 16;
    if (![NSLocale respondsToSelector:@selector(characterDirectionForLanguage:)]) bad |= 32;
    if (![[[NSFileManager defaultManager] displayNameAtPath:@"/Applications/X.app"] isEqual:@"X"]) bad |= 64;
    return bad;
}

static int eleventh_build(void)
{
    @try { return eleventh_checks(); }
    @catch (id e) { return 128; }
}

// the twelfth build (VLC, patches/foundation-main-thread-perform-is-queued.patch): on the main thread,
// -performSelectorOnMainThread:withObject:waitUntilDone:NO is queued for the run loop, as on macOS, not run
// before the call returns; with waitUntilDone:YES it still runs at once
@interface SFProbePerform : NSObject { @public int ran; }
- (void)mark;
@end
@implementation SFProbePerform
- (void)mark { ran++; }
@end

static int twelfth_checks(void)
{
    int bad = 0;
    SFProbePerform *p = [[SFProbePerform alloc] init];
    [p performSelectorOnMainThread:@selector(mark) withObject:nil waitUntilDone:NO];
    if (p->ran != 0) bad |= 1;                       // ran before the call returned
    for (int i = 0; i < 50 && p->ran == 0; i++) [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    if (p->ran != 1) bad |= 2;                       // the run loop did not run it (once)
    [p performSelectorOnMainThread:@selector(mark) withObject:nil waitUntilDone:YES];
    if (p->ran != 2) bad |= 4;                       // waitUntilDone:YES on the main thread runs at once
    [p release];
    return bad;
}

static int twelfth_build(void)
{
    @try { return twelfth_checks(); }
    @catch (id e) { return 8; }
}

int main(void)
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    SFRoot *root = [[SFRoot alloc] init];
    SFLeaf *first = [[SFLeaf alloc] init], *second = [[SFLeaf alloc] init];
    [root setLeaf:first];
    [root addObserver:root forKeyPath:@"leaf.name" options:NSKeyValueObservingOptionNew context:NULL];
    [first setName:@"a"];                 // a setter called directly, one component down the path
    int afterLeaf = root->heard;
    [root setLeaf:second];                // the first component replaced
    int afterSwap = root->heard;
    [second setName:@"b"];                // the new value is observed
    [first setName:@"c"];                 // the old one no longer is
    int end = root->heard;
    [root removeObserver:root forKeyPath:@"leaf.name"];
    [second setName:@"d"];
    int more = second_build() | (third_build() << 4) | (fourth_build() << 8) | (fifth_build() << 12) | (sixth_build() << 16) | (seventh_build() << 25);
    int eighth = eighth_build(), ninth = ninth_build(), tenth = tenth_build(), eleventh = eleventh_build(), twelfth = twelfth_build();
    BOOL ok = afterLeaf == 1 && afterSwap == 2 && end == 3 && root->heard == 3 && more == 0 && eighth == 0 && ninth == 0 && tenth == 0 && eleventh == 0 && twelfth == 0;
    printf("sf-kvo-probe: notifications %d, %d, %d, %d (wanted 1, 2, 3, 3), key-value coding and subclasses %d (wanted 0), to-many accessors %d (wanted 0), readability handler %d (wanted 0), networking classes %d (wanted 0), VLC additions %d (wanted 0), main-thread perform queued %d (wanted 0): %s\n", afterLeaf, afterSwap, end, root->heard, more, eighth, ninth, tenth, eleventh, twelfth, ok ? "ok" : "FAIL");
    [pool release];
    return ok ? 0 : 1;
}
