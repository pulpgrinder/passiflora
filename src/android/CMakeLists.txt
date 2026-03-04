cmake_minimum_required(VERSION 3.22)
project(passiflora C)

set(SRC_ROOT ${CMAKE_CURRENT_SOURCE_DIR}/../..)

# ── Generate zipdata.c from src/www if it doesn't already exist ────
# When building from Android Studio, mkzipfile.sh hasn't been run.
# We generate it here so the build is self-contained.
set(ZIPDATA_C ${SRC_ROOT}/zipdata.c)
set(CONTENT_DIR ${SRC_ROOT}/src/www)
set(SYSTEMID_JS ${CONTENT_DIR}/systemid.js)

# ── Generate systemid.js for Android ──────────────────────────────
if(NOT EXISTS ${SYSTEMID_JS} OR NOT "${_SYSTEMID_OS}" STREQUAL "Android")
    file(WRITE ${SYSTEMID_JS} "// Auto-generated file — DO NOT EDIT. This file is overwritten on every build.\nPASSIFLORA_OS_NAME = \"Android\";\n")
endif()

if(NOT EXISTS ${ZIPDATA_C})
    # Find all content files so CMake re-runs when they change
    file(GLOB_RECURSE CONTENT_FILES ${CONTENT_DIR}/*)

    # Use the shell script if available, otherwise use a CMake fallback
    find_program(BASH_EXE bash)
    if(BASH_EXE)
        execute_process(
            COMMAND ${BASH_EXE} ${SRC_ROOT}/mkzipfile.sh ${CONTENT_DIR} ${ZIPDATA_C}
            WORKING_DIRECTORY ${SRC_ROOT}
            RESULT_VARIABLE MKZIP_RESULT
        )
        if(NOT MKZIP_RESULT EQUAL 0)
            message(FATAL_ERROR "mkzipfile.sh failed (exit ${MKZIP_RESULT}). "
                "Generate zipdata.c manually: sh mkzipfile.sh src/www zipdata.c")
        endif()
    else()
        message(FATAL_ERROR "zipdata.c not found and bash not available. "
            "Generate it first: sh mkzipfile.sh src/www zipdata.c")
    endif()
endif()

add_library(passiflora SHARED
    ${SRC_ROOT}/passiflora.c
    ${SRC_ROOT}/UI.c
)

target_include_directories(passiflora PRIVATE ${SRC_ROOT})

# 16KB page size compatibility (Android 15+)
target_link_options(passiflora PRIVATE -Wl,-z,max-page-size=16384)

find_library(log-lib log)
target_link_libraries(passiflora ${log-lib})
