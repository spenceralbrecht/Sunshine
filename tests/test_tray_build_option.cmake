# Run without configuring Sunshine or starting any GUI/service:
# cmake -P tests/test_tray_build_option.cmake
get_filename_component(ROOT "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)

set(APPLE TRUE)
unset(SUNSHINE_ENABLE_TRAY CACHE)
include("${ROOT}/cmake/prep/options.cmake")
include("${ROOT}/cmake/prep/constants.cmake")
if(SUNSHINE_ENABLE_TRAY OR NOT SUNSHINE_TRAY EQUAL 0)
    message(FATAL_ERROR "macOS must default to a tray-free build")
endif()

# Existing build caches and explicit options must select the matching C++ gate.
set(SUNSHINE_ENABLE_TRAY ON CACHE BOOL "" FORCE)
include("${ROOT}/cmake/prep/constants.cmake")
if(NOT SUNSHINE_TRAY EQUAL 1)
    message(FATAL_ERROR "Explicit ON must retain the feature")
endif()
set(SUNSHINE_ENABLE_TRAY OFF CACHE BOOL "" FORCE)
include("${ROOT}/cmake/prep/constants.cmake")
if(NOT SUNSHINE_TRAY EQUAL 0)
    message(FATAL_ERROR "OFF must remove C++ tray calls as well as AppKit sources")
endif()

set(APPLE FALSE)
unset(SUNSHINE_ENABLE_TRAY CACHE)
include("${ROOT}/cmake/prep/options.cmake")
include("${ROOT}/cmake/prep/constants.cmake")
if(NOT SUNSHINE_ENABLE_TRAY OR NOT SUNSHINE_TRAY EQUAL 1)
    message(FATAL_ERROR "Other platforms must retain their existing default")
endif()
message(STATUS "Tray build option regression checks passed")
