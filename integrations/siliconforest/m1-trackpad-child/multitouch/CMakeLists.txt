add_kext_bundle(SFM1SPIHID.kext INFO_PLIST Info.plist KERNEL_PRIVATE
    BUNDLE_IDENTIFIER org.siliconforest.driver.SFM1SPIHID BUNDLE_VERSION 0.1.0
    ANTIMAIN_FUNCTION sf_m1kbd_stop)
set_property(TARGET SFM1SPIHID.kext PROPERTY OUTPUT_NAME SFM1SPIHID)
target_sources(SFM1SPIHID.kext PRIVATE
    SFM1SPIHID.cpp SFM1KeyboardHW.cpp m1kbd_board.c m1kbd_pio.c m1kbd_hid.c
    native_protocol/dl_spi_hid.c m1tp_enum.c SFM1SPITrackpad.cpp m1tp_child_policy.c descriptor_guard.c m1tp_trace.c
    m1tp_mt.c m1tp_mt_selftest.c)
target_include_directories(SFM1SPIHID.kext PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/../IOHIDFamily/IOHIDSystem
    ${CMAKE_CURRENT_SOURCE_DIR}/../IOHIDFamily/include
    ${CMAKE_CURRENT_SOURCE_DIR}/../IOHIDFamily/IOHIDFamily
    ${CMAKE_CURRENT_SOURCE_DIR}/../IOHIDFamily)
target_link_libraries(SFM1SPIHID.kext PRIVATE xnu_kernel_private_headers)
target_compile_options(SFM1SPIHID.kext PRIVATE
    "$<$<COMPILE_LANGUAGE:CXX>:SHELL:-include ${CMAKE_CURRENT_SOURCE_DIR}/../IOHIDFamily/include/sf_hid_compat.h>"
    -Wall -Wextra -Wframe-larger-than=1024)
set_property(TARGET SFM1SPIHID.kext PROPERTY C_STANDARD 11)
set_property(TARGET SFM1SPIHID.kext PROPERTY CXX_STANDARD 14)
install(TARGETS SFM1SPIHID.kext DESTINATION System/Library/Extensions COMPONENT BaseSystem)
