/* SPDX-License-Identifier: MIT */
#ifndef SF_IMAGECAPTURECORE_H
#define SF_IMAGECAPTURECORE_H
#import <Foundation/Foundation.h>

@class ICDevice, ICDeviceBrowser;
typedef NSUInteger ICDeviceTypeMask;
typedef NSString *ICAuthorizationStatus;

enum {
    ICDeviceTypeMaskCamera = 1,
    ICDeviceLocationTypeMaskLocal = 256,
};

@protocol ICDeviceBrowserDelegate <NSObject>
- (void)deviceBrowser:(ICDeviceBrowser *)browser didAddDevice:(ICDevice *)device moreComing:(BOOL)more;
- (void)deviceBrowser:(ICDeviceBrowser *)browser didRemoveDevice:(ICDevice *)device moreGoing:(BOOL)more;
@optional
- (void)deviceBrowserDidEnumerateLocalDevices:(ICDeviceBrowser *)browser;
@end

@interface ICDeviceBrowser : NSObject
@property (assign) id<ICDeviceBrowserDelegate> delegate;
@property ICDeviceTypeMask browsedDeviceTypeMask;
@property (readonly, getter=isBrowsing) BOOL browsing;
@property (readonly, getter=isSuspended) BOOL suspended;
@property (readonly) NSArray *devices;
@property (readonly) ICDevice *preferredDevice;
- (void)start;
- (void)stop;
- (ICAuthorizationStatus)contentsAuthorizationStatus;
@end

#endif
