/* SPDX-License-Identifier: MIT OR Apache-2.0 */
/* Read/layout subset for the 17 CorePDF calls Preview imports.
   Page refs stay O2PDFPage objects from CoreGraphics. Text positions come
   from Onyx text operators and O2ContextShowText advances. Rectangle
   operands are popped as O2PDFReal and widened. No success is invented for
   a missing page, a missing font advance, or an unknown node type. */
#import <CoreGraphics/CoreGraphics.h>
#import <Onyx2D/O2BitmapContext.h>
#import <Onyx2D/O2ColorSpace.h>
#import <Onyx2D/O2Context.h>
#import <Onyx2D/O2GraphicsState.h>
#import <Onyx2D/O2Image.h>
#import <Onyx2D/O2PDFArray.h>
#import <Onyx2D/O2PDFContentStream.h>
#import <Onyx2D/O2PDFDictionary.h>
#import <Onyx2D/O2PDFObject.h>
#import <Onyx2D/O2PDFOperatorTable.h>
#import <Onyx2D/O2PDFOperators.h>
#import <Onyx2D/O2PDFPage.h>
#import <Onyx2D/O2PDFScanner.h>
#import <Onyx2D/O2PDFStream.h>
#import <Onyx2D/O2PDFString.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSAutoreleasePool.h>
#import <Foundation/NSData.h>
#import <Foundation/NSException.h>
#import <objc/runtime.h>
#import "SFCorePDF.h"

#import <math.h>
#import <stdlib.h>
#import <string.h>

BOOL O2PDFGetPageObjectForKey(O2PDFPage *page, const char *key, O2PDFObject **object);

@interface O2PDFContentStream (SfInherited)
- (id)initWithStreams:(NSArray *)streams resources:(O2PDFDictionary *)resources parent:(O2PDFContentStream *)parent;
@end

enum {
    kSfNodeText = 1,
    kSfNodeContainer = 0x601
};

@interface SfChar : NSObject {
@public
    CGRect rect;
}
@end

@implementation SfChar
@end

@interface SfNode : NSObject {
@public
    int type;
    long z;
    double rotation;
    CFRange range;
    CGRect bounds;
    int hasBounds;
    NSMutableArray *children;
}
@end

@implementation SfNode
- (void)dealloc
{
    [children release];
    [super dealloc];
}
@end

@interface SfLayout : NSObject {
@public
    SfNode *root;
    NSMutableArray *chars;
    long paint;
}
@end

@implementation SfLayout
- (void)dealloc
{
    [root release];
    [chars release];
    [super dealloc];
}
@end

@interface SfRangeBox : NSObject {
@public
    CFRange range;
}
@end

@implementation SfRangeBox
@end

@interface SfSelection : NSObject {
@public
    NSMutableArray *ranges;
}
@end

@implementation SfSelection
- (void)dealloc
{
    [ranges release];
    [super dealloc];
}
@end

static char kLayoutKey;
static char kRecordKey;

static CGRect sf_zero(void)
{
    return CGRectMake(0, 0, 0, 0);
}

static CFRange sf_range(long location, long length)
{
    CFRange range;
    range.location = (CFIndex)location;
    range.length = (CFIndex)length;
    return range;
}

static CGRect sf_norm(double x, double y, double w, double h)
{
    if (w < 0) {
        x += w;
        w = -w;
    }
    if (h < 0) {
        y += h;
        h = -h;
    }
    return CGRectMake(x, y, w, h);
}

static void sf_include(SfNode *node, CGRect rect)
{
    if (!node->hasBounds) {
        node->bounds = rect;
        node->hasBounds = 1;
        return;
    }
    {
        double x0 = MIN(CGRectGetMinX(node->bounds), CGRectGetMinX(rect));
        double y0 = MIN(CGRectGetMinY(node->bounds), CGRectGetMinY(rect));
        double x1 = MAX(CGRectGetMaxX(node->bounds), CGRectGetMaxX(rect));
        double y1 = MAX(CGRectGetMaxY(node->bounds), CGRectGetMaxY(rect));
        node->bounds = CGRectMake(x0, y0, x1 - x0, y1 - y0);
    }
}

static int sf_overlap(CGRect a, CGRect b)
{
    double ax0 = CGRectGetMinX(a), ay0 = CGRectGetMinY(a);
    double ax1 = CGRectGetMaxX(a), ay1 = CGRectGetMaxY(a);
    double bx0 = CGRectGetMinX(b), by0 = CGRectGetMinY(b);
    double bx1 = CGRectGetMaxX(b), by1 = CGRectGetMaxY(b);
    if (ax1 < ax0) {
        double t = ax0;
        ax0 = ax1;
        ax1 = t;
    }
    if (ay1 < ay0) {
        double t = ay0;
        ay0 = ay1;
        ay1 = t;
    }
    if (bx1 < bx0) {
        double t = bx0;
        bx0 = bx1;
        bx1 = t;
    }
    if (by1 < by0) {
        double t = by0;
        by0 = by1;
        by1 = t;
    }
    return ax1 >= bx0 && bx1 >= ax0 && ay1 >= by0 && by1 >= ay0;
}

static SfLayout *sf_layout_of(id context)
{
    return (SfLayout *)objc_getAssociatedObject(context, &kRecordKey);
}

static double sf_font_size(O2Context *context)
{
    O2GState *state;
    O2Float size;
    if (!context)
        return 0;
    state = O2ContextCurrentGState(context);
    if (!state)
        return 0;
    size = O2GStatePointSize(state);
    if (size < 0)
        size = -size;
    return (double)size;
}

static void sf_record_show(O2Context *context, const unsigned char *bytes, int length)
{
    SfLayout *layout;
    SfNode *node;
    long location;
    int i;
    if (!context || !bytes || length <= 0)
        return;
    layout = sf_layout_of((id)context);
    if (!layout || !layout->root)
        return;
    location = (long)[layout->chars count];
    node = [[SfNode alloc] init];
    node->type = kSfNodeText;
    node->z = layout->paint++;
    node->rotation = 0;
    node->range = sf_range(location, 0);
    node->children = [[NSMutableArray alloc] init];
    for (i = 0; i < length; i++) {
        O2AffineTransform before = O2ContextGetTextMatrix(context);
        O2AffineTransform after;
        char one = (char)bytes[i];
        double size, x0, y0, x1, y1, w, h;
        SfChar *box = [[SfChar alloc] init];
        O2ContextShowText(context, &one, 1);
        after = O2ContextGetTextMatrix(context);
        size = sf_font_size(context);
        x0 = (double)before.tx;
        y0 = (double)before.ty;
        x1 = (double)after.tx;
        y1 = (double)after.ty;
        w = x1 - x0;
        h = y1 - y0;
        if (h < 0)
            h = -h;
        if (w < 0)
            w = -w;
        /* Horizontal runs keep the baseline as the origin and the Tf size
           as the height. The width is only the advance ShowText applied. */
        if (h < 0.01)
            box->rect = sf_norm(x0 < x1 ? x0 : x1, y0, w, size);
        else if (w < 0.01)
            box->rect = sf_norm(x0, y0 < y1 ? y0 : y1, size, h);
        else
            box->rect = sf_norm(x0 < x1 ? x0 : x1, y0 < y1 ? y0 : y1, w, h > size ? h : size);
        [layout->chars addObject:box];
        sf_include(node, box->rect);
        sf_include(layout->root, box->rect);
        [box release];
    }
    node->range = sf_range(location, (long)[layout->chars count] - location);
    [layout->root->children addObject:node];
    [node release];
}

static void sf_Tj(O2PDFScanner *scanner, void *info)
{
    O2PDFString *string = nil;
    if (!O2PDFScannerPopString(scanner, &string) || !string)
        return;
    sf_record_show((O2Context *)info, O2PDFStringGetBytePtr(string), (int)O2PDFStringGetLength(string));
}

static void sf_adjust(O2Context *context, O2PDFReal amount)
{
    O2AffineTransform Tm;
    O2Size advance;
    if (!context)
        return;
    Tm = O2ContextGetTextMatrix(context);
    advance = O2SizeApplyAffineTransform(O2SizeMake(amount / 1000.0f, 0), Tm);
    Tm.tx -= advance.width;
    Tm.ty -= advance.height;
    O2ContextSetTextMatrix(context, Tm);
}

static void sf_TJ(O2PDFScanner *scanner, void *info)
{
    O2PDFArray *array = nil;
    unsigned i, count;
    if (!O2PDFScannerPopArray(scanner, &array) || !array)
        return;
    count = [array count];
    for (i = 0; i < count; i++) {
        O2PDFObject *object = nil;
        O2PDFReal real = 0;
        O2PDFInteger integer = 0;
        O2PDFString *string = nil;
        if (![array getObjectAtIndex:i value:&object] || !object)
            continue;
        if ([object checkForType:kO2PDFObjectTypeReal value:&real])
            sf_adjust((O2Context *)info, real);
        else if ([object checkForType:kO2PDFObjectTypeInteger value:&integer])
            sf_adjust((O2Context *)info, (O2PDFReal)integer);
        else if ([object checkForType:kO2PDFObjectTypeString value:&string] && string)
            sf_record_show((O2Context *)info, O2PDFStringGetBytePtr(string), (int)O2PDFStringGetLength(string));
    }
}

static void sf_quote(O2PDFScanner *scanner, void *info)
{
    O2PDF_render_T_star(scanner, info);
    sf_Tj(scanner, info);
}

static void sf_dquote(O2PDFScanner *scanner, void *info)
{
    O2PDFString *string = nil;
    O2PDFReal cspacing = 0, wspacing = 0;
    O2Context *context = (O2Context *)info;
    if (!O2PDFScannerPopString(scanner, &string))
        return;
    if (!O2PDFScannerPopNumber(scanner, &cspacing))
        return;
    if (!O2PDFScannerPopNumber(scanner, &wspacing))
        return;
    O2ContextSetWordSpacing(context, wspacing);
    O2ContextSetCharacterSpacing(context, cspacing);
    O2PDF_render_T_star(scanner, info);
    if (string)
        sf_record_show(context, O2PDFStringGetBytePtr(string), (int)O2PDFStringGetLength(string));
}

static void sf_re(O2PDFScanner *scanner, void *info)
{
    O2PDFReal x = 0, y = 0, w = 0, h = 0;
    SfLayout *layout;
    SfNode *node;
    CGRect rect;
    if (!O2PDFScannerPopNumber(scanner, &h) || !O2PDFScannerPopNumber(scanner, &w) ||
        !O2PDFScannerPopNumber(scanner, &y) || !O2PDFScannerPopNumber(scanner, &x))
        return;
    rect = sf_norm((double)x, (double)y, (double)w, (double)h);
    layout = sf_layout_of((id)info);
    if (layout && layout->root) {
        node = [[SfNode alloc] init];
        node->type = kSfNodeText;
        node->z = layout->paint++;
        node->rotation = 0;
        node->range = sf_range(0, 0);
        node->bounds = rect;
        node->hasBounds = 1;
        node->children = [[NSMutableArray alloc] init];
        [layout->root->children addObject:node];
        sf_include(layout->root, rect);
        [node release];
    }
    if (info)
        O2ContextAddRect((O2Context *)info, O2RectMake(x, y, w, h));
}

static int sf_regular(unsigned char c)
{
    return c > 32 && c < 127 && c != '(' && c != ')' && c != '<' && c != '>' && c != '[' && c != ']' &&
           c != '{' && c != '}' && c != '/' && c != '%';
}

static int sf_op_name(const char *name, size_t n)
{
    size_t i;
    int mark = 0;
    if (n < 1 || n > 16)
        return 0;
    for (i = 0; i < n; i++) {
        unsigned char c = (unsigned char)name[i];
        if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c == '*' || c == '\'' || c == '"')
            mark = 1;
        else if (c < '0' || c > '9')
            return 0;
    }
    return mark;
}

static void sf_ignore(O2PDFScanner *scanner, void *info)
{
    O2PDFObject *value = nil;
    (void)info;
    while (O2PDFScannerPopObject(scanner, &value))
        ;
}

static void sf_note_operators(O2PDFOperatorTable *table, const unsigned char *bytes, size_t n)
{
    size_t i = 0;
    while (i < n) {
        unsigned char c = bytes[i];
        if (c == '%') {
            while (i < n && bytes[i] != '\n' && bytes[i] != '\r')
                i++;
        } else if (c == '(') {
            int depth = 1;
            i++;
            while (i < n && depth) {
                if (bytes[i] == '\\' && i + 1 < n)
                    i += 2;
                else {
                    if (bytes[i] == '(')
                        depth++;
                    else if (bytes[i] == ')')
                        depth--;
                    i++;
                }
            }
        } else if (c == '<' && i + 1 < n && bytes[i + 1] == '<') {
            i += 2;
        } else if (c == '<') {
            i++;
            while (i < n && bytes[i] != '>')
                i++;
            if (i < n)
                i++;
        } else if (c == '/') {
            i++;
            while (i < n && sf_regular(bytes[i]))
                i++;
        } else if (sf_regular(c)) {
            size_t start = i;
            char name[17];
            size_t len;
            while (i < n && sf_regular(bytes[i]))
                i++;
            len = i - start;
            if (sf_op_name((const char *)bytes + start, len)) {
                if (len > 16)
                    len = 16;
                memcpy(name, bytes + start, len);
                name[len] = 0;
                if (![table callbackForName:name])
                    [table setCallback:sf_ignore forName:name];
            }
        } else {
            i++;
        }
    }
}

static void sf_arm_unknown(O2PDFScanner *scanner)
{
    O2PDFContentStream *content;
    NSArray *streams;
    NSUInteger i, count;
    if (!scanner)
        return;
    content = [scanner contentStream];
    streams = content ? [content streams] : nil;
    count = streams ? [streams count] : 0;
    for (i = 0; i < count; i++) {
        id item = [streams objectAtIndex:i];
        O2PDFStream *stream = nil;
        NSData *data;
        if (![item checkForType:kO2PDFObjectTypeStream value:&stream] || !stream)
            continue;
        data = [stream data];
        if (data)
            sf_note_operators((O2PDFOperatorTable *)objc_getAssociatedObject((id)scanner, &kRecordKey), [data bytes],
                (size_t)[data length]);
    }
}

static void sf_add_contents(NSMutableArray *streams, O2PDFObject *contents)
{
    O2PDFArray *array = nil;
    O2PDFStream *stream = nil;
    unsigned i, count;
    if (!contents)
        return;
    if ([contents checkForType:kO2PDFObjectTypeArray value:&array] && array) {
        count = [array count];
        for (i = 0; i < count; i++) {
            O2PDFObject *item = nil;
            if ([array getObjectAtIndex:i value:&item])
                sf_add_contents(streams, item);
        }
    } else if ([contents checkForType:kO2PDFObjectTypeStream value:&stream] && stream) {
        [streams addObject:stream];
    }
}

static SfLayout *sf_build(O2PDFPage *page)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    SfLayout *layout = [[SfLayout alloc] init];
    O2Rect media = O2RectZero;
    size_t width = 1, height = 1, bytesPerRow;
    void *pixels = NULL;
    O2ColorSpaceRef colorSpace = NULL;
    O2ContextRef context = NULL;
    O2PDFObject *resourcesObject = nil;
    O2PDFObject *contentsObject = nil;
    O2PDFDictionary *resources = nil;
    NSMutableArray *streams = [[NSMutableArray alloc] init];
    O2PDFContentStream *content = nil;
    O2PDFOperatorTable *table = nil;
    O2PDFScanner *scanner = nil;
    layout->chars = [[NSMutableArray alloc] init];
    layout->root = [[SfNode alloc] init];
    layout->root->type = kSfNodeContainer;
    layout->root->rotation = 0;
    layout->root->range = sf_range(0, 0);
    layout->root->children = [[NSMutableArray alloc] init];
    layout->paint = 0;
    if ([page getRect:&media forBox:kO2PDFMediaBox]) {
        if (media.size.width >= 1 && media.size.width <= 4096)
            width = (size_t)media.size.width;
        if (media.size.height >= 1 && media.size.height <= 4096)
            height = (size_t)media.size.height;
    }
    bytesPerRow = width * 4;
    pixels = calloc(height, bytesPerRow);
    colorSpace = O2ColorSpaceCreateDeviceRGB();
    if (pixels && colorSpace)
        context = O2BitmapContextCreate(pixels, width, height, 8, bytesPerRow, colorSpace, kO2ImageAlphaPremultipliedLast);
    O2PDFGetPageObjectForKey(page, "Resources", &resourcesObject);
    O2PDFGetPageObjectForKey(page, "Contents", &contentsObject);
    if (resourcesObject)
        [resourcesObject checkForType:kO2PDFObjectTypeDictionary value:&resources];
    sf_add_contents(streams, contentsObject);
    content = [[O2PDFContentStream alloc] initWithStreams:streams resources:resources parent:nil];
    table = [O2PDFOperatorTable renderingOperatorTable];
    [table setCallback:sf_Tj forName:"Tj"];
    [table setCallback:sf_TJ forName:"TJ"];
    [table setCallback:sf_quote forName:"'"];
    [table setCallback:sf_dquote forName:"\""];
    [table setCallback:sf_re forName:"re"];
    scanner = [[O2PDFScanner alloc] initWithContentStream:content operatorTable:table info:context];
    objc_setAssociatedObject((id)context, &kRecordKey, layout, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject((id)scanner, &kRecordKey, table, OBJC_ASSOCIATION_ASSIGN);
    sf_arm_unknown(scanner);
    @try {
        [scanner scan];
    } @catch (id exception) {
        (void)exception;
    }
    [scanner release];
    [content release];
    [streams release];
    if (context)
        O2ContextRelease(context);
    if (colorSpace)
        O2ColorSpaceRelease(colorSpace);
    free(pixels);
    [pool release];
    return layout;
}

static O2PDFPage *sf_page(CGPDFPageRef page)
{
    if (!page)
        return nil;
    if (![(id)page isKindOfClass:[O2PDFPage class]])
        return nil;
    return (O2PDFPage *)page;
}

static SfLayout *sf_layout(CGPDFPageRef page, int create)
{
    O2PDFPage *object = sf_page(page);
    SfLayout *layout;
    if (!object)
        return nil;
    layout = (SfLayout *)objc_getAssociatedObject(object, &kLayoutKey);
    if (layout || !create)
        return layout;
    layout = sf_build(object);
    if (!layout)
        return nil;
    objc_setAssociatedObject(object, &kLayoutKey, layout, OBJC_ASSOCIATION_RETAIN);
    [layout release];
    return (SfLayout *)objc_getAssociatedObject(object, &kLayoutKey);
}

static SfNode *sf_node(CGPDFNodeRef node)
{
    if (!node)
        return nil;
    if (![(id)node isKindOfClass:[SfNode class]])
        return nil;
    return (SfNode *)node;
}

static SfSelection *sf_selection(CGPDFSelectionRef selection)
{
    if (!selection)
        return nil;
    if (![(id)selection isKindOfClass:[SfSelection class]])
        return nil;
    return (SfSelection *)selection;
}

CGPDFLayoutRef CGPDFPageGetLayout(CGPDFPageRef page)
{
    return (CGPDFLayoutRef)sf_layout(page, 1);
}

void CGPDFPageRemoveLayout(CGPDFPageRef page)
{
    O2PDFPage *object = sf_page(page);
    if (!object)
        return;
    objc_setAssociatedObject(object, &kLayoutKey, nil, OBJC_ASSOCIATION_ASSIGN);
}

CGPDFNodeRef CGPDFLayoutGetRootNode(CGPDFLayoutRef layout)
{
    if (!layout || ![(id)layout isKindOfClass:[SfLayout class]])
        return NULL;
    return (CGPDFNodeRef)((SfLayout *)layout)->root;
}

CGRect CGPDFNodeGetBounds(CGPDFNodeRef node)
{
    SfNode *object = sf_node(node);
    if (!object || !object->hasBounds)
        return sf_zero();
    return object->bounds;
}

int CGPDFNodeGetType(CGPDFNodeRef node)
{
    SfNode *object = sf_node(node);
    return object ? object->type : 0;
}

CGPDFNodeRef CGPDFNodeGetChild(CGPDFNodeRef node, long index)
{
    SfNode *object = sf_node(node);
    if (!object || index < 0 || (unsigned long)index >= [object->children count])
        return NULL;
    return (CGPDFNodeRef)[object->children objectAtIndex:(NSUInteger)index];
}

int CGPDFNodeGetChildCount(CGPDFNodeRef node)
{
    SfNode *object = sf_node(node);
    NSUInteger count;
    if (!object)
        return 0;
    count = [object->children count];
    if (count > 0x7fffffff)
        return 0x7fffffff;
    return (int)count;
}

double CGPDFNodeGetRotation(CGPDFNodeRef node)
{
    SfNode *object = sf_node(node);
    return object ? object->rotation : 0;
}

CFRange CGPDFNodeGetTextRange(CGPDFNodeRef node)
{
    SfNode *object = sf_node(node);
    if (!object)
        return sf_range(0, 0);
    return object->range;
}

long CGPDFNodeGetZ(CGPDFNodeRef node)
{
    SfNode *object = sf_node(node);
    return object ? object->z : 0;
}

CGPDFNodeRef CGPDFNodeRetain(CGPDFNodeRef node)
{
    if (!sf_node(node))
        return NULL;
    return (CGPDFNodeRef)[(id)node retain];
}

void CGPDFNodeRelease(CGPDFNodeRef node)
{
    if (!sf_node(node))
        return;
    [(id)node release];
}

CGRect CGPDFLayoutGetCharacterBounds(CGPDFLayoutRef layout, long index)
{
    SfLayout *object;
    SfChar *box;
    if (!layout || ![(id)layout isKindOfClass:[SfLayout class]] || index < 0)
        return sf_zero();
    object = (SfLayout *)layout;
    if ((unsigned long)index >= [object->chars count])
        return sf_zero();
    box = [object->chars objectAtIndex:(NSUInteger)index];
    return box->rect;
}

CGPDFSelectionRef CGPDFSelectionCreateInRect(CGPDFPageRef page, CGRect rect)
{
    SfLayout *layout = sf_layout(page, 1);
    SfSelection *selection;
    NSUInteger i, count;
    long start = -1;
    if (!layout)
        return NULL;
    selection = [[SfSelection alloc] init];
    selection->ranges = [[NSMutableArray alloc] init];
    count = [layout->chars count];
    for (i = 0; i < count; i++) {
        SfChar *box = [layout->chars objectAtIndex:i];
        if (sf_overlap(rect, box->rect)) {
            if (start < 0)
                start = (long)i;
        } else if (start >= 0) {
            SfRangeBox *range = [[SfRangeBox alloc] init];
            range->range = sf_range(start, (long)i - start);
            [selection->ranges addObject:range];
            [range release];
            start = -1;
        }
    }
    if (start >= 0) {
        SfRangeBox *range = [[SfRangeBox alloc] init];
        range->range = sf_range(start, (long)count - start);
        [selection->ranges addObject:range];
        [range release];
    }
    if (![selection->ranges count]) {
        [selection release];
        return NULL;
    }
    return (CGPDFSelectionRef)selection;
}

void CGPDFSelectionRelease(CGPDFSelectionRef selection)
{
    if (!sf_selection(selection))
        return;
    [(id)selection release];
}

long CGPDFSelectionGetNumberOfTextRanges(CGPDFSelectionRef selection)
{
    SfSelection *object = sf_selection(selection);
    if (!object)
        return 0;
    return (long)[object->ranges count];
}

CFRange CGPDFSelectionGetTextRange(CGPDFSelectionRef selection, long index)
{
    SfSelection *object = sf_selection(selection);
    SfRangeBox *box;
    if (!object || index < 0 || (unsigned long)index >= [object->ranges count])
        return sf_range(0, 0);
    box = [object->ranges objectAtIndex:(NSUInteger)index];
    return box->range;
}
