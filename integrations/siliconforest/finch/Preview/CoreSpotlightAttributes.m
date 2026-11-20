/* SPDX-License-Identifier: MIT OR Apache-2.0 */
/* Copyright (c) 2026 The Finch Project contributors.
 * Taken in part from Finch 2d9b1bb1af57e14462e4621d194929188a8845b0,
 * userland/CoreSpotlight/CSSearchableItem.m. Attribute/key storage only.
 * SiliconForest: typed common fields, bounded KVC, no forwarding/index/search,
 * explicit unavailable archive operations, synchronized field-name table. */
#import "CoreSpotlightAttributes.h"
static void rejectArchive(void) {
    [NSException raise:@"SFCoreSpotlightUnsupportedOperation"
                format:@"This attribute-only provider does not implement archive encoding or decoding."];
}
static NSArray<NSString *> *
attributeNames(void)
{
    static NSArray *names;
    @synchronized ([CSSearchableItemAttributeSet class]) {
      if (!names) {
      names = @[ @"accountIdentifier", @"accountHandles", @"HTMLContentData", @"textContent", @"authors", @"primaryRecipients",
        @"additionalRecipients", @"hiddenAdditionalRecipients", @"emailHeaders", @"mailboxIdentifiers", @"authorNames",
        @"recipientNames", @"authorEmailAddresses", @"recipientEmailAddresses", @"authorAddresses", @"recipientAddresses",
        @"phoneNumbers", @"emailAddresses", @"instantMessageAddresses", @"likelyJunk", @"isPriority", @"displayName", @"alternateNames",
        @"path", @"contentURL", @"thumbnailURL", @"thumbnailData", @"darkThumbnailURL", @"relatedUniqueIdentifier",
        @"metadataModificationDate", @"contentType", @"contentTypeTree", @"sharedItemContentType", @"actionIdentifiers", @"keywords", @"title", @"version",
        @"userCreated", @"userOwned", @"userCurated", @"rankingHint", @"domainIdentifier", @"textContentSummary",
        @"transcribedTextContent", @"supportsPhoneCall", @"supportsNavigation", @"containerTitle", @"containerDisplayName",
        @"containerIdentifier", @"containerOrder", @"providerDataTypeIdentifiers", @"providerFileTypeIdentifiers",
        @"providerInPlaceFileTypeIdentifiers", @"pixelHeight", @"pixelWidth", @"pixelCount", @"colorSpace", @"bitsPerSample",
        @"flashOn", @"focalLength", @"focalLength35mm", @"acquisitionMake", @"acquisitionModel", @"cameraOwner", @"lensModel",
        @"ISOSpeed", @"orientation", @"layerNames", @"whiteBalance", @"aperture", @"profileName", @"resolutionWidthDPI",
        @"resolutionHeightDPI", @"exposureMode", @"exposureTime", @"EXIFVersion", @"EXIFGPSVersion", @"hasAlphaChannel",
        @"redEyeOn", @"meteringMode", @"maxAperture", @"fNumber", @"exposureProgram", @"exposureTimeString", @"subject",
        @"theme", @"contentDescription", @"identifier", @"audiences", @"fileSize", @"pageCount", @"pageWidth", @"pageHeight",
        @"securityMethod", @"creator", @"encodingApplications", @"kind", @"fontNames", @"editors", @"participants", @"projects",
        @"contentSources", @"comment", @"copyright", @"lastUsedDate", @"contentCreationDate", @"contentModificationDate",
        @"addedDate", @"downloadedDate", @"duration", @"contactKeywords", @"codecs", @"mediaTypes", @"streamable",
        @"totalBitRate", @"videoBitRate", @"audioBitRate", @"deliveryType", @"organizations", @"role", @"languages", @"rights",
        @"publishers", @"contributors", @"coverage", @"rating", @"ratingDescription", @"playCount", @"information", @"director",
        @"producer", @"genre", @"performers", @"originalFormat", @"originalSource", @"local", @"contentRating", @"URL",
        @"audioSampleRate", @"audioChannelCount", @"tempo", @"keySignature", @"timeSignature", @"audioEncodingApplication",
        @"composer", @"lyricist", @"album", @"artist", @"audioTrackNumber", @"recordingDate", @"musicalGenre",
        @"generalMIDISequence", @"musicalInstrumentCategory", @"musicalInstrumentName", @"headline", @"instructions",
        @"thoroughfare", @"subThoroughfare", @"postalCode", @"city", @"stateOrProvince", @"country", @"fullyFormattedAddress",
        @"altitude", @"latitude", @"longitude", @"speed", @"timestamp", @"imageDirection", @"namedLocation", @"GPSTrack",
        @"GPSStatus", @"GPSMeasureMode", @"GPSDOP", @"GPSMapDatum", @"GPSDestLatitude", @"GPSDestLongitude", @"GPSDestBearing",
        @"GPSDestDistance", @"GPSProcessingMethod", @"GPSAreaInformation", @"GPSDateStamp", @"GPSDifferental", @"dueDate",
        @"completionDate", @"startDate", @"endDate", @"importantDates", @"allDay" ];
      }
    }
    return names;
}

@implementation CSSearchableItemAttributeSet {
    NSMutableDictionary<NSString *, id> *_finchValues;
    NSMutableDictionary<NSString *, id> *_customValues;
}

+ (BOOL)supportsSecureCoding { return NO; }

- (instancetype)init
{
    if ((self = [super init])) {
        _finchValues = [NSMutableDictionary dictionary];
        _customValues = [NSMutableDictionary dictionary];
    }
    return self;
}

- (instancetype)initWithItemContentType:(NSString *)identifier
{
    if ((self = [self init])) {
        self.contentType = identifier;
        self.contentTypeTree = identifier.length ? @[ identifier ] : @[];
    }
    return self;
}

/* Direct typed accessors avoid advertising unavailable dynamic forwarding.
 * The remaining retained Finch fields are available through its bounded KVC. */
#define SF_CS_FIELD(n,N) \
- (id)n { return [_finchValues objectForKey:@#n]; } \
- (void)set##N:(id)value { if (value) [_finchValues setObject:value forKey:@#n]; else [_finchValues removeObjectForKey:@#n]; }
SF_CS_FIELD(contentType,ContentType)
SF_CS_FIELD(contentTypeTree,ContentTypeTree)
SF_CS_FIELD(displayName,DisplayName)
SF_CS_FIELD(title,Title)
#undef SF_CS_FIELD

- (void)setValue:(id)value forKey:(NSString *)key
{
    if ([attributeNames() containsObject:key]) {
        if (value)
            [_finchValues setObject:value forKey:key];
        else
            [_finchValues removeObjectForKey:key];
        return;
    }
    [super setValue:value forKey:key];
}

- (id)valueForKey:(NSString *)key
{
    if ([attributeNames() containsObject:key])
        return [_finchValues objectForKey:key];
    return [super valueForKey:key];
}

- (void)setValue:(id)value forCustomKey:(CSCustomAttributeKey *)key
{
    if (!key.keyName.length)
        [NSException raise:NSInvalidArgumentException format:@"A valid custom attribute key is required."];
    if (value)
        [_customValues setObject:value forKey:key.keyName];
    else
        [_customValues removeObjectForKey:key.keyName];
}

- (id)valueForCustomKey:(CSCustomAttributeKey *)key { return [_customValues objectForKey:key.keyName]; }
- (id)copyWithZone:(NSZone *)zone
{
    CSSearchableItemAttributeSet *copy = [[[self class] allocWithZone:zone] init];
    copy->_finchValues = [_finchValues mutableCopy];
    copy->_customValues = [_customValues mutableCopy];
    return copy;
}
- (void)encodeWithCoder:(NSCoder *)coder { rejectArchive(); }
- (instancetype)initWithCoder:(NSCoder *)coder { rejectArchive(); return nil; }
@end
@implementation CSCustomAttributeKey {
    NSString *_keyName;
    BOOL _searchable, _searchableByDefault, _unique, _multiValued;
}

- (instancetype)initWithKeyName:(NSString *)name
{
    return [self initWithKeyName:name searchable:YES searchableByDefault:NO unique:NO multiValued:NO];
}
- (instancetype)initWithKeyName:(NSString *)name searchable:(BOOL)searchable searchableByDefault:(BOOL)byDefault unique:(BOOL)unique multiValued:(BOOL)multi
{
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"];
    if (!name.length || [name rangeOfCharacterFromSet:allowed.invertedSet].location != NSNotFound || [name hasPrefix:@"kMD"])
        return nil;
    if ((self = [super init])) {
        _keyName = [name copy];
        _searchable = searchable;
        _searchableByDefault = byDefault;
        _unique = unique;
        _multiValued = multi;
    }
    return self;
}
- (NSString *)keyName { return _keyName; }
- (BOOL)isSearchable { return _searchable; }
- (BOOL)isSearchableByDefault { return _searchableByDefault; }
- (BOOL)isUnique { return _unique; }
- (BOOL)isMultiValued { return _multiValued; }
- (id)copyWithZone:(NSZone *)zone { return self; }
@end
