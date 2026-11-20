// SPDX-License-Identifier: MIT
#import "SFHydra.h"
#import <dispatch/dispatch.h>
#include <stdio.h>
#include <stdlib.h>

int main(void) {
    @autoreleasepool {
        HYDExportParams *export = [HYDExportParams new];
        if (export.textureCompression != 0 || export.isSiblingPath || export.firstLayerName)
            return 2;
        export.textureCompression = 2;
        export.firstLayerName = @"Forest";
        export.isSiblingPath = YES;
        if (export.textureCompression != 2 || !export.isSiblingPath || ![export.firstLayerName isEqualToString:@"Forest"])
            return 3;

        HYDStageTransformParams *transform = [HYDStageTransformParams new];
        if (transform.scale != 100 || transform.metersPerUnit != 0.1 || transform.upAxis != 1)
            return 4;
        transform.rotation = (SFHydraVector){12, 34, 56};
        transform.bbox = (SFHydraVector){78, 90, 12};
        SFHydraVector rotation = transform.rotation;
        SFHydraVector bounds = transform.bbox;
        if (rotation[0] != 12 || rotation[1] != 34 || rotation[2] != 56 || bounds[0] != 78 || bounds[1] != 90 || bounds[2] != 12)
            return 5;

        HYDSceneNode *root = [[HYDSceneNode alloc] init:@"Scene" parent:nil];
        HYDSceneNode *child = [[HYDSceneNode alloc] init:@"Input" parent:root];
        if (root.numberOfChildren || child.parent != root || ![root.hierarchialPath isEqualToString:@""] ||
            ![child.hierarchialPath isEqualToString:@"/Input"] || ![child.hierarchialName isEqualToString:@"Input"])
            return 6;
        [root addChild:child];
        if (root.numberOfChildren != 1 || [root childAtIndex:0] != child || [root childAtIndex:1])
            return 7;
        [root removeChildAt:0];
        if (root.numberOfChildren)
            return 8;

        HYDRenderer *renderer = [[HYDRenderer alloc] initWithFeatures:nil];
        NSError *error = nil;
        NSURL *url = [NSURL fileURLWithPath:@"hydra-probe-must-not-create.usdz"];
        if (!renderer || renderer.sceneHierarchy || [renderer loadAssets:@[url]] || [renderer transformStage:transform] ||
            [renderer writeTo:url withParams:export error:&error] || ![error.domain isEqualToString:SFHydraErrorDomain] ||
            error.code != SFHydraRendererUnavailable || ![error.userInfo[NSURLErrorKey] isEqual:url] ||
            [[NSFileManager defaultManager] fileExistsAtPath:url.path])
            return 9;
        [renderer loadAssetsAsync:@[url] complete:^{
            puts("Hydra parameter and scene metadata, unavailable renderer, and callback passed");
            exit(0);
        }];
    }
    dispatch_main();
}
