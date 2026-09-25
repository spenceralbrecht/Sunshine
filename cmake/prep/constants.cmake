# source assets will be installed from this directory
set(SUNSHINE_SOURCE_ASSETS_DIR "${CMAKE_SOURCE_DIR}/src_assets")

# Keep the C++ feature gate consistent with the optional platform implementation.
# Linux may additionally disable it when a required package is unavailable.
if(SUNSHINE_ENABLE_TRAY)
    set(SUNSHINE_TRAY 1)
else()
    set(SUNSHINE_TRAY 0)
endif()
