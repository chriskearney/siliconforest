# SPDX-License-Identifier: MIT
# CoreServices.framework for the disk root and the images: the tree's arm64 build at the lab's
# SiliconForest revision (../rebase/pd.nix)
#   + patches/coreservices-text-encoding-converter.patch (GitHub issue 45):
#       CreateTextEncoding, GetTextEncodingBase/Variant/Format, TECCreateConverter,
#       TECConvertText, TECFlushText, TECClearConverterContextInfo, TECDisposeConverter and
#       LocaleRefGetPartString. Homebrew's vim calls all of them at every start and neovim
#       imports the last; without them dyld refuses both programs.
#       See docs/roadmap/issues/SF-S-homebrew.md ("Framework gaps").
#
#   nix-build --extra-experimental-features 'nix-command flakes' --no-out-link build-coreservices.nix
let
  pd = import ../qemu-dev/sf-userland.nix;
in pd.packages.x86_64-linux.coreServices-arm64.overrideAttrs (old: {
  pname = "siliconforest-coreservices";
  patches = (old.patches or []) ++ [
    ./patches/coreservices-text-encoding-converter.patch
    # FSGetCatalogInfo, FSGetVolumeParms, LSCopyAllHandlersForURLScheme (VLC media player 3.0:
    # docs/roadmap/issues/SF-AH-vlc.md)
    ./patches/coreservices-catalog-info-and-url-handlers.patch
  ];
  buildPhase = builtins.replaceStrings
    [ "src/Libraries/CoreServices/UnicodeUtilities.c \\" ]
    [ "src/Libraries/CoreServices/UnicodeUtilities.c src/Libraries/CoreServices/TextEncodingConverter.c \\" ]
    old.buildPhase;
})
