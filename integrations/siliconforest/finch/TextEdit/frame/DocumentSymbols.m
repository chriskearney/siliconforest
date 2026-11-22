/* SPDX-License-Identifier: MIT
   Document-attribute and document-type constants TextEdit binds in AppKit.
   The string values are the ones AppKit has shipped: attribute keys are the
   constant's name, and the document types are the short type names. */
#import <Foundation/Foundation.h>

#define SF_STR(name, value) NSString *const name = @value

SF_STR(NSAuthorDocumentAttribute, "NSAuthorDocumentAttribute");
SF_STR(NSBackgroundColorDocumentAttribute, "NSBackgroundColorDocumentAttribute");
SF_STR(NSBottomMarginDocumentAttribute, "NSBottomMarginDocumentAttribute");
SF_STR(NSCharacterEncodingDocumentAttribute, "NSCharacterEncodingDocumentAttribute");
SF_STR(NSCocoaVersionDocumentAttribute, "NSCocoaVersionDocumentAttribute");
SF_STR(NSCommentDocumentAttribute, "NSCommentDocumentAttribute");
SF_STR(NSCompanyDocumentAttribute, "NSCompanyDocumentAttribute");
SF_STR(NSConvertedDocumentAttribute, "NSConvertedDocumentAttribute");
SF_STR(NSCopyrightDocumentAttribute, "NSCopyrightDocumentAttribute");
SF_STR(NSDocumentTypeDocumentAttribute, "NSDocumentTypeDocumentAttribute");
SF_STR(NSExcludedElementsDocumentAttribute, "NSExcludedElementsDocumentAttribute");
SF_STR(NSHyphenationFactorDocumentAttribute, "NSHyphenationFactorDocumentAttribute");
SF_STR(NSKeywordsDocumentAttribute, "NSKeywordsDocumentAttribute");
SF_STR(NSLeftMarginDocumentAttribute, "NSLeftMarginDocumentAttribute");
SF_STR(NSPaperSizeDocumentAttribute, "NSPaperSizeDocumentAttribute");
SF_STR(NSPrefixSpacesDocumentAttribute, "NSPrefixSpacesDocumentAttribute");
SF_STR(NSReadOnlyDocumentAttribute, "NSReadOnlyDocumentAttribute");
SF_STR(NSRightMarginDocumentAttribute, "NSRightMarginDocumentAttribute");
SF_STR(NSSubjectDocumentAttribute, "NSSubjectDocumentAttribute");
SF_STR(NSTitleDocumentAttribute, "NSTitleDocumentAttribute");
SF_STR(NSTopMarginDocumentAttribute, "NSTopMarginDocumentAttribute");
SF_STR(NSUsesScreenFontsDocumentAttribute, "NSUsesScreenFontsDocumentAttribute");
SF_STR(NSViewModeDocumentAttribute, "NSViewModeDocumentAttribute");
SF_STR(NSViewSizeDocumentAttribute, "NSViewSizeDocumentAttribute");
SF_STR(NSViewZoomDocumentAttribute, "NSViewZoomDocumentAttribute");

SF_STR(NSPlainTextDocumentType, "NSPlainText");
SF_STR(NSRTFTextDocumentType, "NSRTF");
SF_STR(NSRTFDTextDocumentType, "NSRTFD");
SF_STR(NSMacSimpleTextDocumentType, "NSMacSimpleText");
SF_STR(NSHTMLTextDocumentType, "NSHTML");
SF_STR(NSDocFormatTextDocumentType, "NSDocFormat");
SF_STR(NSWordMLTextDocumentType, "NSWordML");
SF_STR(NSWebArchiveTextDocumentType, "NSWebArchive");
SF_STR(NSOfficeOpenXMLTextDocumentType, "NSOfficeOpenXML");
SF_STR(NSOpenDocumentTextDocumentType, "NSOpenDocument");

SF_STR(NSBaseURLDocumentOption, "NSBaseURL");
SF_STR(NSDocumentTypeDocumentOption, "NSDocumentType");
SF_STR(NSTextKit1ListMarkerFormatDocumentOption, "NSTextKit1ListMarkerFormat");
SF_STR(NSTextLayoutSectionsAttribute, "NSTextLayoutSections");
SF_STR(NSTextLayoutSectionOrientation, "NSTextLayoutSectionOrientation");
SF_STR(NSTextLayoutSectionRange, "NSTextLayoutSectionRange");
SF_STR(NSWritingDirectionAttributeName, "NSWritingDirection");
SF_STR(NSTextContentStorageUnsupportedAttributeAddedNotification,
       "NSTextContentStorageUnsupportedAttributeAddedNotification");
