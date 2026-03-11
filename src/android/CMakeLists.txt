cmake_minimum_required(VERSION 3.22)
project(passiflora C)

set(SRC_ROOT ${CMAKE_CURRENT_SOURCE_DIR}/../..)

# ── Generate zipdata.c from src/www if it doesn't already exist ────
# When building from Android Studio, mkzipfile.sh hasn't been run.
# We generate it here so the build is self-contained.
set(ZIPDATA_C ${SRC_ROOT}/src/C/generated/zipdata.h)
set(CONTENT_DIR ${SRC_ROOT}/src/www)
set(CONFIG_JS ${CONTENT_DIR}/generated/config.js)

# ── Generate config.js for Android (fallback if not already built) ──
if(NOT EXISTS ${CONFIG_JS})
    file(WRITE ${CONFIG_JS} "// Auto-generated file — DO NOT EDIT. This file is overwritten on every build.\nvar PassifloraConfig = {\n  os_name: \"Android\",\n  menus: [],\n  handleMenu: function(title) { alert(\"Menu item clicked: \" + title); }\n};\n")
endif()

if(NOT EXISTS ${ZIPDATA_C})
    # Find all content files so CMake re-runs when they change
    file(GLOB_RECURSE CONTENT_FILES ${CONTENT_DIR}/*)

    # Use the shell script if available, otherwise use a CMake fallback
    find_program(BASH_EXE bash)
    if(BASH_EXE)
        execute_process(
            COMMAND ${BASH_EXE} ${SRC_ROOT}/nixscripts/mkzipfile.sh ${CONTENT_DIR} ${ZIPDATA_C}
            WORKING_DIRECTORY ${SRC_ROOT}
            RESULT_VARIABLE MKZIP_RESULT
        )
        if(NOT MKZIP_RESULT EQUAL 0)
            message(FATAL_ERROR "mkzipfile.sh failed (exit ${MKZIP_RESULT}). "
                "Generate zipdata.h manually: sh nixscripts/mkzipfile.sh src/www src/C/generated/zipdata.h")
        endif()
    else()
        message(FATAL_ERROR "zipdata.c not found and bash not available. "
            "Generate it first: sh nixscripts/mkzipfile.sh src/www src/C/generated/zipdata.h")
    endif()
endif()

add_library(passiflora SHARED
    ${SRC_ROOT}/src/C/passiflora.c
    ${SRC_ROOT}/src/C/UI.c
)

target_include_directories(passiflora PRIVATE ${SRC_ROOT} ${SRC_ROOT}/src/C)

# ── Read src/permissions and set -DPERM_* compile definitions ──────
set(PERM_FILE ${SRC_ROOT}/src/permissions)
if(EXISTS ${PERM_FILE})
    file(STRINGS ${PERM_FILE} PERM_LINES)
    foreach(LINE ${PERM_LINES})
        # Each line is "name 0|1"
        string(REGEX MATCH "^([a-z]+) +1" _m "${LINE}")
        if(_m)
            string(REGEX REPLACE "^([a-z]+) +1" "\\1" PNAME "${LINE}")
            # androidexternalstorage is Android-only (manifest/Java), not a C define
            if(NOT PNAME STREQUAL "androidexternalstorage")
                string(TOUPPER ${PNAME} PUPPER)
                target_compile_definitions(passiflora PRIVATE PERM_${PUPPER})
            endif()
        endif()
    endforeach()
endif()

# 16KB page size compatibility (Android 15+)
target_link_options(passiflora PRIVATE -Wl,-z,max-page-size=16384)

find_library(log-lib log)
target_link_libraries(passiflora ${log-lib})
