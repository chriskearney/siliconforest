/* SPDX-License-Identifier: MIT OR Apache-2.0 */
/* Headless check of the CorePDF layout subset against reading.pdf. */
#include <CoreGraphics/CoreGraphics.h>
#include "SFCorePDF.h"

#include <stdio.h>
#include <stdlib.h>

static int near(double value, double expect)
{
    double delta = value - expect;
    if (delta < 0)
        delta = -delta;
    return delta < 0.51;
}

static int rect_near(CGRect rect, double x, double y, double w, double h)
{
    return near(rect.origin.x, x) && near(rect.origin.y, y) && near(rect.size.width, w) && near(rect.size.height, h);
}

static CGPDFNodeRef text_child(CGPDFNodeRef root)
{
    int i, count = CGPDFNodeGetChildCount(root);
    for (i = 0; i < count; i++) {
        CGPDFNodeRef child = CGPDFNodeGetChild(root, i);
        CFRange range = CGPDFNodeGetTextRange(child);
        if (CGPDFNodeGetType(child) == 1 && range.length > 0)
            return child;
    }
    return NULL;
}

static CGPDFNodeRef path_child(CGPDFNodeRef root)
{
    int i, count = CGPDFNodeGetChildCount(root);
    for (i = 0; i < count; i++) {
        CGPDFNodeRef child = CGPDFNodeGetChild(root, i);
        if (CGPDFNodeGetType(child) == 1 && CGPDFNodeGetTextRange(child).length == 0 &&
            rect_near(CGPDFNodeGetBounds(child), 48, 60, 144, 60))
            return child;
    }
    return NULL;
}

int main(int argc, char **argv)
{
    FILE *file;
    unsigned char *bytes;
    long size;
    CGDataProviderRef provider;
    CGPDFDocumentRef document;
    size_t pages;
    int failures = 0;
    static const long expect_chars[3] = {11, 13, 14};
    size_t page_index;
    setvbuf(stdout, NULL, _IONBF, 0);
    if (argc != 2)
        return 2;
    file = fopen(argv[1], "rb");
    if (!file)
        return 3;
    if (fseek(file, 0, SEEK_END) != 0)
        return 3;
    size = ftell(file);
    if (size < 0)
        return 3;
    if (fseek(file, 0, SEEK_SET) != 0)
        return 3;
    bytes = malloc((size_t)size);
    if (!bytes || fread(bytes, 1, (size_t)size, file) != (size_t)size) {
        fclose(file);
        free(bytes);
        return 3;
    }
    fclose(file);
    provider = CGDataProviderCreateWithData(NULL, bytes, (size_t)size, NULL);
    document = CGPDFDocumentCreateWithProvider(provider);
    CGDataProviderRelease(provider);
    if (!document) {
        printf("document=null\n");
        return 4;
    }
    pages = CGPDFDocumentGetNumberOfPages(document);
    printf("pages=%zu\n", pages);
    if (pages != 3)
        failures++;
    if (CGPDFPageGetLayout(NULL) != NULL)
        failures++;
    if (CGPDFSelectionCreateInRect(NULL, CGRectMake(0, 0, 10, 10)) != NULL)
        failures++;
    if (CGPDFNodeGetChild(NULL, 0) != NULL)
        failures++;
    if (CGPDFNodeGetType(NULL) != 0)
        failures++;
    CGPDFPageRemoveLayout(NULL);
    CGPDFNodeRelease(NULL);
    if (CGPDFNodeRetain(NULL) != NULL)
        failures++;
    for (page_index = 1; page_index <= pages && page_index <= 3; page_index++) {
        CGPDFPageRef page = CGPDFDocumentGetPage(document, page_index);
        CGPDFLayoutRef layout = CGPDFPageGetLayout(page);
        CGPDFNodeRef root = CGPDFLayoutGetRootNode(layout);
        CGPDFNodeRef text = text_child(root);
        CGPDFNodeRef path = path_child(root);
        CFRange text_range = CGPDFNodeGetTextRange(text);
        CGRect first = CGPDFLayoutGetCharacterBounds(layout, text ? text_range.location : 0);
        CGRect root_bounds = CGPDFNodeGetBounds(root);
        CGPDFSelectionRef selection;
        long ranges;
        CFRange selected;
        CGPDFNodeRef retained;
        printf(
            "page=%zu root_type=%d children=%d chars=%ld text=%ld,%ld path=%d "
            "char0=%.1f,%.1f,%.1f,%.1f root=%.1f,%.1f,%.1f,%.1f rot=%.1f z=%ld\n",
            page_index, CGPDFNodeGetType(root), CGPDFNodeGetChildCount(root),
            text ? text_range.location + text_range.length : 0, (long)text_range.location, (long)text_range.length,
            path != NULL, first.origin.x, first.origin.y, first.size.width, first.size.height, root_bounds.origin.x,
            root_bounds.origin.y, root_bounds.size.width, root_bounds.size.height, CGPDFNodeGetRotation(root),
            CGPDFNodeGetZ(path ? path : text));
        if (!layout || CGPDFNodeGetType(root) != 0x601)
            failures++;
        if (!text || text_range.length != expect_chars[page_index - 1] || text_range.location != 0)
            failures++;
        if (!near(first.origin.x, 32) || !near(first.origin.y, 148) || !near(first.size.height, 20))
            failures++;
        if (!path)
            failures++;
        if (CGPDFNodeGetRotation(text) != 0)
            failures++;
        if (!CGRectEqualToRect(CGPDFLayoutGetCharacterBounds(layout, text_range.location + text_range.length), CGRectZero))
            failures++;
        selection = CGPDFSelectionCreateInRect(page, CGRectMake(30, 145, 180, 30));
        ranges = CGPDFSelectionGetNumberOfTextRanges(selection);
        selected = CGPDFSelectionGetTextRange(selection, 0);
        printf("page=%zu sel_ranges=%ld first=%ld,%ld\n", page_index, ranges, (long)selected.location, (long)selected.length);
        if (!selection || ranges < 1 || selected.location != 0 || selected.length < 1)
            failures++;
        if (CGPDFSelectionCreateInRect(page, CGRectMake(0, 0, 1, 1)) != NULL)
            failures++;
        retained = CGPDFNodeRetain(root);
        if (retained != root)
            failures++;
        CGPDFNodeRelease(retained);
        CGPDFSelectionRelease(selection);
        CGPDFPageRemoveLayout(page);
        if (CGPDFPageGetLayout(page) == NULL)
            failures++;
        CGPDFPageRemoveLayout(page);
    }
    CGPDFDocumentRelease(document);
    free(bytes);
    printf("failures=%d\n", failures);
    return failures ? 1 : 0;
}
