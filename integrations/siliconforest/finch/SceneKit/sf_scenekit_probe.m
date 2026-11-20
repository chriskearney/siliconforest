/* SPDX-License-Identifier: MIT OR Apache-2.0 */
/* Headless check of the SceneKit load subset. It does not open a window. */
#import "SFSceneKit.h"
#import <objc/runtime.h>
#import <stdio.h>
#import <string.h>

@interface SFProbeView : SCNView
@end
@implementation SFProbeView
@end

static int sf_fail;

static void expect(int ok, const char *label)
{
    if (!ok) {
        printf("fail %s\n", label);
        sf_fail++;
    }
}

static int super_named(Class cls, const char *name)
{
    Class parent = class_getSuperclass(cls);
    return parent && strcmp(class_getName(parent), name) == 0;
}

/* SCNRenderer is the measured superclass and is not a Preview import, so the
   probe reaches it through SCNOffscreenRenderer instead of linking its class. */
static int chain_named(Class cls, const char *parent, const char *grand)
{
    Class p = class_getSuperclass(cls);
    Class g = p ? class_getSuperclass(p) : Nil;
    return p && g
        && strcmp(class_getName(p), parent) == 0
        && strcmp(class_getName(g), grand) == 0;
}

static int string_is(NSString *value, const char *expect_utf8)
{
    return value && strcmp([value UTF8String], expect_utf8) == 0;
}

int main(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    SFProbeView *view;
    id pov;
    NSURL *url;
    NSDictionary *options;
    SCNSceneSource *source;
    __block int handler_calls = 0;
    __block int handler_error = 0;
    id scene;
    setvbuf(stdout, NULL, _IONBF, 0);

    expect(super_named([SCNView class], "NSView"), "SCNView");
    expect(chain_named([SCNOffscreenRenderer class], "SCNRenderer", "NSObject"), "SCNOffscreenRenderer");
    expect(super_named([SCNCamera class], "NSObject"), "SCNCamera");
    expect(super_named([SCNSceneSource class], "NSObject"), "SCNSceneSource");
    expect(super_named([SCNTransaction class], "NSObject"), "SCNTransaction");
    printf("super SCNView=%s SCNOffscreenRenderer=%s SCNCamera=%s SCNSceneSource=%s SCNTransaction=%s\n",
        class_getName(class_getSuperclass([SCNView class])),
        class_getName(class_getSuperclass([SCNOffscreenRenderer class])),
        class_getName(class_getSuperclass([SCNCamera class])),
        class_getName(class_getSuperclass([SCNSceneSource class])),
        class_getName(class_getSuperclass([SCNTransaction class])));

    view = [[SFProbeView alloc] initWithFrame:NSMakeRect(0, 0, 32, 16)];
    expect(view && super_named([view class], "SCNView"), "subclass");
    pov = [[NSObject alloc] init];
    [view setPointOfView:pov animate:YES];
    [view setSceneTime:2.5];
    [view setAllowsCameraControl:YES];
    [view setScene:nil];
    expect([view pointOfView] == pov, "pointOfView");
    expect([view sceneTime] == 2.5, "sceneTime");
    expect([view allowsCameraControl], "cameraControl");
    expect([view scene] == nil, "sceneStoredNil");

    expect(string_is(SCNExportPointOfViewAttribute, "kExportPointOfViewAttribute"), "exportPov");
    expect(string_is(SCNSceneEndTimeAttributeKey, "kSceneEndTimeAttributeKey"), "endTime");
    expect(string_is(SCNSceneSourceAssetAuthorKey, "author"), "author");
    expect(string_is(SCNSceneSourceAssetAuthoringToolKey, "authoring_tool"), "tool");
    expect(string_is(SCNSceneSourceAssetContributorsKey, "contributors"), "contributors");
    expect(string_is(SCNSceneSourceAssetUpAxisKey, "up_axis"), "upAxis");
    expect(string_is(SCNSceneSourceSceneIndexKey, "kSceneSourceSceneIndexKey"), "sceneIndex");
    expect(string_is(SCNSceneStartTimeAttributeKey, "kSceneStartTimeAttributeKey"), "startTime");
    printf("strings %s %s %s %s %s %s %s %s\n",
        [SCNExportPointOfViewAttribute UTF8String], [SCNSceneEndTimeAttributeKey UTF8String],
        [SCNSceneSourceAssetAuthorKey UTF8String], [SCNSceneSourceAssetAuthoringToolKey UTF8String],
        [SCNSceneSourceAssetContributorsKey UTF8String], [SCNSceneSourceAssetUpAxisKey UTF8String],
        [SCNSceneSourceSceneIndexKey UTF8String], [SCNSceneStartTimeAttributeKey UTF8String]);

    url = [NSURL fileURLWithPath:@"/tmp/sf-scenekit-missing.usdz"];
    options = [NSDictionary dictionaryWithObject:[NSNumber numberWithInt:0] forKey:SCNSceneSourceSceneIndexKey];
    source = [SCNSceneSource sceneSourceWithURL:url options:options];
    expect(source && [[source url] isEqual:url], "url");
    expect([[source options] objectForKey:SCNSceneSourceSceneIndexKey] != nil, "options");
    expect([source propertyForKey:SCNSceneSourceAssetAuthorKey] == nil, "authorNil");
    scene = [source sceneWithOptions:nil statusHandler:^(float progress, NSError *error, BOOL *stop) {
        (void)progress;
        (void)stop;
        handler_calls++;
        if (error)
            handler_error++;
    }];
    expect(scene == nil && handler_calls == 1 && handler_error == 1, "sceneLoad");
    expect([SCNOffscreenRenderer offscreenRendererWithContext:nil size:CGSizeMake(8, 8)] == nil, "renderer");

    [SCNTransaction begin];
    [SCNTransaction setAnimationDuration:1.5];
    [SCNTransaction flush];
    [SCNTransaction commit];
    expect([SCNTransaction animationDuration] == 1.5, "duration");
    expect([[SCNCamera camera] isKindOfClass:[SCNCamera class]], "camera");
    printf("scene_nil=%d renderer_nil=%d duration=%.1f camera=%s\n", scene == nil,
        [SCNOffscreenRenderer offscreenRendererWithContext:nil size:CGSizeMake(1, 1)] == nil,
        [SCNTransaction animationDuration], class_getName([[SCNCamera camera] class]));

    [view release];
    [pov release];
    [pool release];
    printf("failures=%d\n", sf_fail);
    return sf_fail ? 1 : 0;
}
