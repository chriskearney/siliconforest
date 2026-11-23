# SPDX-License-Identifier: GPL-2.0-only
add_kext_bundle(SFAppleAVE.kext INFO_PLIST Info.plist KERNEL_PRIVATE
 BUNDLE_IDENTIFIER org.siliconforest.driver.SFAppleAVE BUNDLE_VERSION 0.1.0)
set_property(TARGET SFAppleAVE.kext PROPERTY OUTPUT_NAME SFAppleAVE)
target_sources(SFAppleAVE.kext PRIVATE
 SFAppleAVE.cpp sfave_bringup.cpp sf_soc.cpp sf_dart_table.c
 sfave_identity.c sfave_preload.c sfave_ipc.c sfave_dapf.c
 sfave_lx.c upstream/ave_session.c upstream/ave_cmd.c)
# The upstream session and command code see the Linux API through lxshim.
set_source_files_properties(sfave_lx.c upstream/ave_session.c upstream/ave_cmd.c PROPERTIES
 COMPILE_OPTIONS "-D__KERNEL__;-include;${CMAKE_CURRENT_SOURCE_DIR}/lxshim/sfave_lx.h;-I${CMAKE_CURRENT_SOURCE_DIR}/lxshim;-I${CMAKE_CURRENT_SOURCE_DIR}/upstream;-Wno-everything")
target_include_directories(SFAppleAVE.kext PRIVATE
 ${CMAKE_CURRENT_SOURCE_DIR} ${CMAKE_CURRENT_SOURCE_DIR}/../include)
target_link_libraries(SFAppleAVE.kext PRIVATE xnu_kernel_private_headers)
target_compile_options(SFAppleAVE.kext PRIVATE -Wall -Os)
set_property(TARGET SFAppleAVE.kext PROPERTY CXX_STANDARD 14)
install(TARGETS SFAppleAVE.kext DESTINATION System/Library/Extensions COMPONENT BaseSystem)
