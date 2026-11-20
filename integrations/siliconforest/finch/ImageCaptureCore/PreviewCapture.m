/* SPDX-License-Identifier: MIT */
#import <ImageCaptureCore/ImageCaptureCore.h>

void _ICInitialize(void)
{
    /* Realize the browser class. There is no device transport to start. */
    (void)[ICDeviceBrowser class];
}

id _ICCreateDeviceMatchingDeviceID(id deviceID)
{
    /* Nothing can match until an Image Capture transport publishes devices. */
    (void)deviceID;
    return nil;
}
