/* SPDX-License-Identifier: MIT OR Apache-2.0 */
#import "CoreSpotlightAttributes.h"
#import <stdio.h>
#import <stdlib.h>
static void need(BOOL condition, const char *message) {
    if (!condition) { fprintf(stderr,"FAIL %s\n",message); exit(1); }
}
int main(void) { @autoreleasepool {
    CSSearchableItemAttributeSet *attributes=[[CSSearchableItemAttributeSet alloc] initWithItemContentType:@"public.item"];
    need([attributes.contentType isEqualToString:@"public.item"] && [attributes.contentTypeTree isEqual:@[@"public.item"]],"actual content type fields");
    attributes.displayName=@"Field notes"; attributes.title=@"A distinct title";
    need([attributes.displayName isEqualToString:@"Field notes"] && [attributes.title isEqualToString:@"A distinct title"],"distinct title/displayName storage");
    [attributes setValue:@3 forKey:@"pageCount"];
    [attributes setValue:@[@"forest",@"survey"] forKey:@"keywords"];
    NSURL *url=[NSURL fileURLWithPath:@"/private/sf-owned-fixture.pdf"];
    [attributes setValue:url forKey:@"contentURL"];
    need([[attributes valueForKey:@"pageCount"] isEqual:@3] && [[attributes valueForKey:@"keywords"] count]==2 && [[attributes valueForKey:@"contentURL"] isEqual:url],"retained Finch fields");
    CSCustomAttributeKey *key=[[CSCustomAttributeKey alloc] initWithKeyName:@"sf_note" searchable:NO searchableByDefault:NO unique:YES multiValued:NO];
    need(key && !key.searchable && key.unique && !key.multiValued,"custom key metadata");
    [attributes setValue:@"original" forCustomKey:key];
    need([[attributes valueForCustomKey:key] isEqual:@"original"],"custom field");
    need([[CSCustomAttributeKey alloc] initWithKeyName:@"kMD_reserved"]==nil && [[CSCustomAttributeKey alloc] initWithKeyName:@"invalid name"]==nil,"invalid custom key rejection");
    CSSearchableItemAttributeSet *copy=[attributes copy];
    copy.title=@"New title"; [copy setValue:@5 forKey:@"pageCount"]; [copy setValue:@"changed" forCustomKey:key];
    need([attributes.title isEqual:@"A distinct title"] && [[attributes valueForKey:@"pageCount"] isEqual:@3] && [[attributes valueForCustomKey:key] isEqual:@"original"],"copy has independent dictionaries");
    need([copy.contentType isEqual:attributes.contentType] && [copy.displayName isEqual:attributes.displayName],"copy retains all ordinary fields");
    attributes.displayName=nil; [attributes setValue:nil forCustomKey:key];
    need(attributes.displayName==nil && [attributes valueForCustomKey:key]==nil && [copy.displayName isEqual:@"Field notes"],"nil removes field without damaging copy");
    NSUInteger errors=0;
    @try { [attributes setValue:@1 forKey:@"sf_unknown_field"]; } @catch(NSException *e) { errors++; }
    @try { [attributes setValue:@1 forCustomKey:nil]; } @catch(NSException *e) { if([e.name isEqual:NSInvalidArgumentException]) errors++; }
    need(errors==2,"unknown/invalid fields fail explicitly");
    need(![CSSearchableItemAttributeSet supportsSecureCoding],"no unproved secure-coding capability");
    id coder=[NSObject new];
    @try { [attributes encodeWithCoder:coder]; } @catch(NSException *e) { if([e.name isEqual:@"SFCoreSpotlightUnsupportedOperation"]) errors++; }
    @try { (void)[[CSSearchableItemAttributeSet alloc] initWithCoder:coder]; } @catch(NSException *e) { if([e.name isEqual:@"SFCoreSpotlightUnsupportedOperation"]) errors++; }
    need(errors==4,"archive operations explicitly unsupported");
    [coder release]; [copy release]; [attributes release]; [key release];
    puts("CORESPOTLIGHT ATTRIBUTES PASS type/title/displayName KVC custom-fields independent-copy removal errors=4 index/search=not-provided");
} return 0; }
