# SPDX-License-Identifier: MIT
(import ../objc-framework.nix {
  name = "ImageCaptureCore";
  arc = false;
  prepare = ''
    mkdir browser
    cp userland/ImageCaptureCore/ICDeviceBrowser.m browser/
    cp ${./PreviewCapture.m} browser/
    # This build has no capture backend and cannot authorize one.
    sed -i 's/ICAuthorizationStatusAuthorized/ICAuthorizationStatusRestricted/g; s/\<AUTHORIZED\>/RESTRICTED/g' browser/ICDeviceBrowser.m
  '';
}).overrideAttrs (old: {
  buildPhase = builtins.replaceStrings [ "userland/ImageCaptureCore/*.m" ] [ "browser/*.m" ] old.buildPhase;
})
