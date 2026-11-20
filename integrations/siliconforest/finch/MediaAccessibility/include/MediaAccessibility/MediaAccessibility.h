/* SPDX-License-Identifier: MIT */
/* Own declarations from Finch source signatures; no Apple SDK input.
 * Enum numeric facts checked against objc2-media-accessibility 0.3.2. */
#pragma once
#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <CoreText/CoreText.h>
#include <ImageIO/ImageIO.h>
#include <stdbool.h>
typedef CFIndex MACaptionAppearanceDomain, MACaptionAppearanceBehavior;
typedef CFIndex MACaptionAppearanceDisplayType, MACaptionAppearanceFontStyle;
typedef CFIndex MACaptionAppearanceTextEdgeStyle;
enum { kMACaptionAppearanceDomainDefault = 0, kMACaptionAppearanceDomainUser = 1,
       kMACaptionAppearanceBehaviorUseValue = 0, kMACaptionAppearanceBehaviorUseContentIfAvailable = 1,
       kMACaptionAppearanceDisplayTypeForcedOnly = 0, kMACaptionAppearanceDisplayTypeAutomatic = 1,
       kMACaptionAppearanceDisplayTypeAlwaysOn = 2, kMACaptionAppearanceTextEdgeStyleNone = 1,
       kMACaptionAppearanceTextEdgeStyleUniform = 4 };
extern const CFStringRef kMACaptionAppearanceSettingsChangedNotification;
extern const CFStringRef kMAAudibleMediaSettingsChangedNotification;
extern const CFStringRef MAMediaCharacteristicDescribesMusicAndSoundForAccessibility;
extern const CFStringRef MAMediaCharacteristicTranscribesSpokenDialogForAccessibility;
extern const CFStringRef MAMediaCharacteristicDescribesVideoForAccessibility;
CFArrayRef MACaptionAppearanceCopySelectedLanguages(MACaptionAppearanceDomain domain);
bool MACaptionAppearanceAddSelectedLanguage(MACaptionAppearanceDomain domain, CFStringRef language);
MACaptionAppearanceDisplayType MACaptionAppearanceGetDisplayType(MACaptionAppearanceDomain domain);
void MACaptionAppearanceSetDisplayType(MACaptionAppearanceDomain domain, MACaptionAppearanceDisplayType displayType);
CFArrayRef MACaptionAppearanceCopyPreferredCaptioningMediaCharacteristics(MACaptionAppearanceDomain domain);
bool MACaptionAppearanceIsCustomized(MACaptionAppearanceDomain domain);
CGColorRef MACaptionAppearanceCopyForegroundColor(MACaptionAppearanceDomain d, MACaptionAppearanceBehavior *b);
CGColorRef MACaptionAppearanceCopyBackgroundColor(MACaptionAppearanceDomain d, MACaptionAppearanceBehavior *b);
CGColorRef MACaptionAppearanceCopyWindowColor(MACaptionAppearanceDomain d, MACaptionAppearanceBehavior *b);
CGFloat MACaptionAppearanceGetForegroundOpacity(MACaptionAppearanceDomain d, MACaptionAppearanceBehavior *b);
CGFloat MACaptionAppearanceGetBackgroundOpacity(MACaptionAppearanceDomain d, MACaptionAppearanceBehavior *b);
CGFloat MACaptionAppearanceGetWindowOpacity(MACaptionAppearanceDomain d, MACaptionAppearanceBehavior *b);
CGFloat MACaptionAppearanceGetWindowRoundedCornerRadius(MACaptionAppearanceDomain d, MACaptionAppearanceBehavior *b);
CTFontDescriptorRef MACaptionAppearanceCopyFontDescriptorForStyle(MACaptionAppearanceDomain domain, MACaptionAppearanceBehavior *behavior, MACaptionAppearanceFontStyle style);
CGFloat MACaptionAppearanceGetRelativeCharacterSize(MACaptionAppearanceDomain d, MACaptionAppearanceBehavior *b);
MACaptionAppearanceTextEdgeStyle MACaptionAppearanceGetTextEdgeStyle(MACaptionAppearanceDomain d, MACaptionAppearanceBehavior *b);
CFArrayRef MACaptionAppearanceCopyProfileIDs(void);
void MACaptionAppearanceSetActiveProfileID(CFStringRef profileID);
CFStringRef MACaptionAppearanceCopyActiveProfileID(void);
CFStringRef MACaptionAppearanceCopyProfileName(CFStringRef profileID);
void MACaptionAppearanceExecuteBlockForProfileID(CFStringRef profileID, void (^block)(void));
CFArrayRef MAAudibleMediaCopyPreferredCharacteristics(void);
void MACaptionAppearanceDidDisplayCaptions(CFArrayRef strings);
CFStringRef MAImageCaptioningCopyMetadataTagPath(void);
CFStringRef MAImageCaptioningCopyCaption(CFURLRef url, CFErrorRef *error);
CFStringRef MAImageCaptioningCopyCaptionWithSource(CGImageSourceRef source, CFErrorRef *error);
bool MAImageCaptioningSetCaption(CFURLRef url, CFStringRef caption, CFErrorRef *error);
bool MAImageCaptioningSetCaptionIntoMetadata(CGMutableImageMetadataRef metadata, CFStringRef caption,
    CFErrorRef *error);
