# SPDX-License-Identifier: GPL-2.0-only
add_kext_bundle(SFAppleAVE.kext INFO_PLIST Info.plist KERNEL_PRIVATE
 BUNDLE_IDENTIFIER org.siliconforest.driver.SFAppleAVE BUNDLE_VERSION 0.1.0)
set_property(TARGET SFAppleAVE.kext PROPERTY OUTPUT_NAME SFAppleAVE)
target_sources(SFAppleAVE.kext PRIVATE
 SFAppleAVE.cpp sfave_bringup.cpp sf_soc.cpp sf_dart_table.c
 sfave_identity.c sfave_preload.c sfave_ipc.c sfave_dapf.c)
target_include_directories(SFAppleAVE.kext PRIVATE
 ${CMAKE_CURRENT_SOURCE_DIR} ${CMAKE_CURRENT_SOURCE_DIR}/../include)
target_link_libraries(SFAppleAVE.kext PRIVATE xnu_kernel_private_headers)
target_compile_options(SFAppleAVE.kext PRIVATE -Wall -Os)
set_property(TARGET SFAppleAVE.kext PROPERTY CXX_STANDARD 14)
install(TARGETS SFAppleAVE.kext DESTINATION System/Library/Extensions COMPONENT BaseSystem)
