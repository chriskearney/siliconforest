// SPDX-License-Identifier: MIT
// Foundation.framework as macOS applications link it: this file plus re-exports of
// /usr/lib/libFoundation.dylib and /usr/lib/swift/libswiftFoundation.dylib. Added here: what
// Terminal.app imports from Foundation and neither has.
#import <Foundation/Foundation.h>
#include <stdarg.h>

NSString *NSFileTypeForHFSTypeCode(OSType code)
{
    char c[7] = { '\'', (char)(code >> 24), (char)(code >> 16), (char)(code >> 8), (char)code, '\'', 0 };
    return [[[NSString alloc] initWithBytes:c length:6 encoding:NSMacOSRomanStringEncoding] autorelease];
}

// NSDictionaryOfVariableBindings(a, b): "a, b" and the values, nil-terminated by count of names
NSDictionary *_NSDictionaryOfVariableBindings(NSString *commaSeparatedKeys, id firstValue, ...)
{
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    NSArray *keys = [commaSeparatedKeys componentsSeparatedByString:@","];
    va_list args;
    va_start(args, firstValue);
    id value = firstValue;
    for (NSUInteger i = 0; i < [keys count]; i++) {
        NSString *key = [[keys objectAtIndex:i] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (value != nil) [result setObject:value forKey:key];
        if (i + 1 < [keys count]) value = va_arg(args, id);
    }
    va_end(args);
    return result;
}

// ---- Cocoa scripting. There is no Apple Event transport on this system, so nothing ever
// creates a command or evaluates a specifier from outside. The classes are complete as data
// objects: an application can build specifiers for its objects and describe its classes.
// (this Foundation has no NSClassDescription: the class stands on NSObject)
@interface NSScriptClassDescription : NSObject { NSString *_suite, *_className; NSDictionary *_dict; }
@end
@implementation NSScriptClassDescription
+ (NSScriptClassDescription *)classDescriptionForClass:(Class)aClass
{
    return nil;      // no scripting definitions are loaded: no class has a description
}
- (id)initWithSuiteName:(NSString *)suite className:(NSString *)name dictionary:(NSDictionary *)dict
{
    if ((self = [super init])) { _suite = [suite copy]; _className = [name copy]; _dict = [dict copy]; }
    return self;
}
- (void)dealloc { [_suite release]; [_className release]; [_dict release]; [super dealloc]; }
- (NSString *)suiteName { return _suite; }
- (NSString *)className { return _className; }
- (NSString *)implementationClassName { return _className; }
- (NSScriptClassDescription *)superclassDescription { return nil; }
- (FourCharCode)appleEventCode { return 0; }
- (BOOL)matchesAppleEventCode:(FourCharCode)code { return NO; }
- (BOOL)supportsCommand:(id)command { return NO; }
- (SEL)selectorForCommand:(id)command { return NULL; }
- (NSString *)typeForKey:(NSString *)key { return nil; }
- (NSScriptClassDescription *)classDescriptionForKey:(NSString *)key { return nil; }
- (FourCharCode)appleEventCodeForKey:(NSString *)key { return 0; }
- (NSString *)keyWithAppleEventCode:(FourCharCode)code { return nil; }
- (NSString *)defaultSubcontainerAttributeKey { return nil; }
- (BOOL)isLocationRequiredToCreateForKey:(NSString *)key { return NO; }
- (BOOL)hasPropertyForKey:(NSString *)key { return NO; }
- (BOOL)hasOrderedToManyRelationshipForKey:(NSString *)key { return NO; }
- (BOOL)hasReadablePropertyForKey:(NSString *)key { return NO; }
- (BOOL)hasWritablePropertyForKey:(NSString *)key { return NO; }
@end

@interface NSScriptObjectSpecifier : NSObject <NSCoding> {
    NSScriptObjectSpecifier *_container, *_child; NSScriptClassDescription *_containerClass; NSString *_key;
    BOOL _containerIsObjectBeingTested, _containerIsRangeContainerObject; NSInteger _error;
}
@end
@implementation NSScriptObjectSpecifier
- (id)initWithContainerSpecifier:(NSScriptObjectSpecifier *)container key:(NSString *)property
{
    return [self initWithContainerClassDescription:nil containerSpecifier:container key:property];
}
- (id)initWithContainerClassDescription:(NSScriptClassDescription *)classDesc containerSpecifier:(NSScriptObjectSpecifier *)container key:(NSString *)property
{
    if ((self = [super init])) { _containerClass = [classDesc retain]; _container = [container retain]; _key = [property copy]; [container setChildSpecifier:self]; }
    return self;
}
- (id)initWithCoder:(NSCoder *)coder { return [self initWithContainerClassDescription:nil containerSpecifier:nil key:nil]; }
- (void)encodeWithCoder:(NSCoder *)coder { }
- (void)dealloc { [_container release]; [_containerClass release]; [_key release]; [super dealloc]; }
- (NSScriptObjectSpecifier *)childSpecifier { return _child; }
- (void)setChildSpecifier:(NSScriptObjectSpecifier *)child { _child = child; }
- (NSScriptObjectSpecifier *)containerSpecifier { return _container; }
- (void)setContainerSpecifier:(NSScriptObjectSpecifier *)c { [c retain]; [_container release]; _container = c; }
- (BOOL)containerIsObjectBeingTested { return _containerIsObjectBeingTested; }
- (void)setContainerIsObjectBeingTested:(BOOL)flag { _containerIsObjectBeingTested = flag; }
- (BOOL)containerIsRangeContainerObject { return _containerIsRangeContainerObject; }
- (void)setContainerIsRangeContainerObject:(BOOL)flag { _containerIsRangeContainerObject = flag; }
- (NSString *)key { return _key; }
- (void)setKey:(NSString *)key { [key retain]; [_key release]; _key = key; }
- (NSScriptClassDescription *)containerClassDescription { return _containerClass; }
- (void)setContainerClassDescription:(NSScriptClassDescription *)d { [d retain]; [_containerClass release]; _containerClass = d; }
- (NSScriptClassDescription *)keyClassDescription { return nil; }
- (NSInteger *)indicesOfObjectsByEvaluatingWithContainer:(id)container count:(NSInteger *)count { if (count) *count = -1; return NULL; }
- (id)objectsByEvaluatingWithContainers:(id)containers
{
    if (_key == nil || containers == nil) return nil;
    @try { return [containers valueForKey:_key]; } @catch (id e) { _error = 1; return nil; }
}
- (id)objectsByEvaluatingSpecifier
{
    id container = _container ? [_container objectsByEvaluatingSpecifier] : [NSClassFromString(@"NSApplication") performSelector:@selector(sharedApplication)];
    return [self objectsByEvaluatingWithContainers:container];
}
- (NSInteger)evaluationErrorNumber { return _error; }
- (void)setEvaluationErrorNumber:(NSInteger)error { _error = error; }
- (NSScriptObjectSpecifier *)evaluationErrorSpecifier { return _error ? self : nil; }
- (id)descriptor { return nil; }
@end

@interface NSIndexSpecifier : NSScriptObjectSpecifier { NSInteger _index; }
@end
@implementation NSIndexSpecifier
- (id)initWithContainerClassDescription:(NSScriptClassDescription *)classDesc containerSpecifier:(NSScriptObjectSpecifier *)container key:(NSString *)property index:(NSInteger)index
{
    if ((self = [super initWithContainerClassDescription:classDesc containerSpecifier:container key:property])) _index = index;
    return self;
}
- (NSInteger)index { return _index; }
- (void)setIndex:(NSInteger)index { _index = index; }
- (id)objectsByEvaluatingWithContainers:(id)containers
{
    id all = [super objectsByEvaluatingWithContainers:containers];
    if (![all isKindOfClass:[NSArray class]]) return nil;
    NSInteger i = _index < 0 ? (NSInteger)[all count] + _index : _index;
    return (i >= 0 && i < (NSInteger)[all count]) ? [all objectAtIndex:i] : nil;
}
@end

@interface NSPropertySpecifier : NSScriptObjectSpecifier
@end
@implementation NSPropertySpecifier
@end

@interface NSUniqueIDSpecifier : NSScriptObjectSpecifier { id _uniqueID; }
@end
@implementation NSUniqueIDSpecifier
- (id)initWithContainerClassDescription:(NSScriptClassDescription *)classDesc containerSpecifier:(NSScriptObjectSpecifier *)container key:(NSString *)property uniqueID:(id)uniqueID
{
    if ((self = [super initWithContainerClassDescription:classDesc containerSpecifier:container key:property])) _uniqueID = [uniqueID copy];
    return self;
}
- (void)dealloc { [_uniqueID release]; [super dealloc]; }
- (id)uniqueID { return _uniqueID; }
- (void)setUniqueID:(id)uniqueID { [uniqueID retain]; [_uniqueID release]; _uniqueID = uniqueID; }
- (id)objectsByEvaluatingWithContainers:(id)containers
{
    id all = [super objectsByEvaluatingWithContainers:containers];
    if (![all isKindOfClass:[NSArray class]]) return nil;
    for (id object in all) {
        @try { if ([[object valueForKey:@"uniqueID"] isEqual:_uniqueID]) return object; } @catch (id e) { }
    }
    return nil;
}
@end

@interface NSScriptCommand : NSObject <NSCoding> {
    id _commandDescription, _directParameter, _receivers, _evaluatedReceivers, _scriptErrorString; NSDictionary *_arguments;
    NSInteger _scriptErrorNumber;
}
@end
@implementation NSScriptCommand
+ (NSScriptCommand *)currentCommand { return nil; }
- (id)initWithCommandDescription:(id)commandDef { if ((self = [super init])) _commandDescription = [commandDef retain]; return self; }
- (id)initWithCoder:(NSCoder *)coder { return [self initWithCommandDescription:nil]; }
- (void)encodeWithCoder:(NSCoder *)coder { }
- (void)dealloc
{
    [_commandDescription release]; [_directParameter release]; [_receivers release]; [_arguments release]; [_scriptErrorString release];
    [super dealloc];
}
- (id)commandDescription { return _commandDescription; }
- (id)directParameter { return _directParameter; }
- (void)setDirectParameter:(id)p { [p retain]; [_directParameter release]; _directParameter = p; }
- (id)receiversSpecifier { return _receivers; }
- (void)setReceiversSpecifier:(id)r { [r retain]; [_receivers release]; _receivers = r; }
- (id)evaluatedReceivers { return [_receivers respondsToSelector:@selector(objectsByEvaluatingSpecifier)] ? [_receivers objectsByEvaluatingSpecifier] : nil; }
- (NSDictionary *)arguments { return _arguments; }
- (void)setArguments:(NSDictionary *)a { [a retain]; [_arguments release]; _arguments = a; }
- (NSDictionary *)evaluatedArguments { return _arguments; }
- (BOOL)isWellFormed { return YES; }
- (id)performDefaultImplementation { return nil; }
- (id)executeCommand { return [self performDefaultImplementation]; }
- (NSInteger)scriptErrorNumber { return _scriptErrorNumber; }
- (void)setScriptErrorNumber:(NSInteger)n { _scriptErrorNumber = n; }
- (NSString *)scriptErrorString { return _scriptErrorString; }
- (void)setScriptErrorString:(NSString *)s { [s retain]; [_scriptErrorString release]; _scriptErrorString = s; }
- (id)appleEvent { return nil; }
- (void)suspendExecution { }
- (void)resumeExecutionWithResult:(id)result { }
@end

// ---- (QTP) NSFileCoordinator, for applications that coordinate their file access (first: Apple's QuickTime Player)
/* File coordination. With no other process presenting files and no coordination service,
 * coordinating an access is running it: the accessor is called at once with the same URL.
 * Presenters are kept so that adding and removing them balances. */
@interface NSFileCoordinator : NSObject {
    id _sfPresenter;
    NSString *_sfPurpose;
}
@end
@implementation NSFileCoordinator
static NSMutableArray *sfPresenters;
+ (void)addFilePresenter:(id)presenter {
    @synchronized([NSFileCoordinator class]) {
        if (!sfPresenters) sfPresenters = [[NSMutableArray alloc] init];
        if (presenter && [sfPresenters indexOfObjectIdenticalTo:presenter] == NSNotFound) [sfPresenters addObject:presenter];
    }
}
+ (void)removeFilePresenter:(id)presenter {
    @synchronized([NSFileCoordinator class]) {
        if (presenter) [sfPresenters removeObjectIdenticalTo:presenter];
    }
}
+ (NSArray *)filePresenters {
    @synchronized([NSFileCoordinator class]) {
        return sfPresenters ? [NSArray arrayWithArray:sfPresenters] : [NSArray array];
    }
}
- (id)initWithFilePresenter:(id)presenter {
    if ((self = [super init])) _sfPresenter = [presenter retain];
    return self;
}
- (NSString *)purposeIdentifier {
    if (!_sfPurpose) _sfPurpose = [[[NSProcessInfo processInfo] globallyUniqueString] copy];
    return _sfPurpose;
}
- (void)setPurposeIdentifier:(NSString *)purpose {
    [_sfPurpose release];
    _sfPurpose = [purpose copy];
}
- (void)coordinateReadingItemAtURL:(NSURL *)url options:(NSUInteger)options error:(NSError **)error byAccessor:(void (^)(NSURL *))reader {
    (void)options;
    if (error) *error = nil;
    if (reader) reader(url);
}
- (void)coordinateWritingItemAtURL:(NSURL *)url options:(NSUInteger)options error:(NSError **)error byAccessor:(void (^)(NSURL *))writer {
    (void)options;
    if (error) *error = nil;
    if (writer) writer(url);
}
- (void)coordinateReadingItemAtURL:(NSURL *)readURL options:(NSUInteger)readOptions writingItemAtURL:(NSURL *)writeURL options:(NSUInteger)writeOptions
                             error:(NSError **)error byAccessor:(void (^)(NSURL *, NSURL *))accessor {
    (void)readOptions; (void)writeOptions;
    if (error) *error = nil;
    if (accessor) accessor(readURL, writeURL);
}
- (void)cancel {
}
- (void)dealloc {
    [_sfPresenter release];
    [_sfPurpose release];
    [super dealloc];
}
@end

// ---- NSAppleScript (VLC media player 3.0's interface links the class; docs/roadmap/issues/SF-AH-vlc.md).
// This system has no AppleScript interpreter and no Apple Events between programs. The class keeps
// its source text and says so when asked to compile or run: the error dictionary carries
// number -1753 (errOSAScriptError) and a message; nothing is executed
// and nothing is reported as done.
NSString * const NSAppleScriptErrorMessage = @"NSAppleScriptErrorMessage";
NSString * const NSAppleScriptErrorNumber = @"NSAppleScriptErrorNumber";
NSString * const NSAppleScriptErrorAppName = @"NSAppleScriptErrorAppName";
NSString * const NSAppleScriptErrorBriefMessage = @"NSAppleScriptErrorBriefMessage";
NSString * const NSAppleScriptErrorRange = @"NSAppleScriptErrorRange";
@interface NSAppleScript : NSObject { NSString *_source; }
@end
@implementation NSAppleScript
static void SFAppleScriptUnavailable(NSDictionary **info)
{
    if (info) *info = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:-1753], NSAppleScriptErrorNumber,
        @"AppleScript is not available on SiliconForest", NSAppleScriptErrorMessage,
        @"AppleScript is not available", NSAppleScriptErrorBriefMessage, nil];
}
- (id)initWithSource:(NSString *)source { if ((self = [super init])) _source = [source copy]; return self; }
- (id)initWithContentsOfURL:(NSURL *)url error:(NSDictionary **)info { SFAppleScriptUnavailable(info); [self release]; return nil; }
- (void)dealloc { [_source release]; [super dealloc]; }
- (NSString *)source { return _source; }
- (BOOL)isCompiled { return NO; }
- (BOOL)compileAndReturnError:(NSDictionary **)info { SFAppleScriptUnavailable(info); return NO; }
- (id)executeAndReturnError:(NSDictionary **)info { SFAppleScriptUnavailable(info); return nil; }
- (id)executeAppleEvent:(id)event error:(NSDictionary **)info { SFAppleScriptUnavailable(info); return nil; }
@end
