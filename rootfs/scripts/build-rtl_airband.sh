#!/bin/bash
# shellcheck shell=bash

set -e

# Check to see if rtl_airband exists
if [[ -e "/usr/local/bin/rtl_airband" ]]; then
    echo "/usr/local/bin/rtl_airband already exists, not building"
else
    echo "Building rtl_airband optimised for this host's CPU"

    pushd /opt/rtlsdr-airband > /dev/null 2>&1

    # Make build dir
    mkdir -p /opt/rtlsdr-airband/build
    pushd /opt/rtlsdr-airband/build > /dev/null 2>&1

    # Prepare cmake args
    CMAKE_CMD=()

    # Determine architecture and apply compiler optimisations.
    # User can set `RTLSDRAIRBAND_BUILD_PLATFORM` to override auto detection if required.
    # May be required for armv7 non-RPi...

    if [[ -n "$RTLSDRAIRBAND_BUILD_PLATFORM" ]]; then

        # Set cmake to build with user-specified platform.
        CMAKE_CMD+=("-DPLATFORM=$RTLSDRAIRBAND_BUILD_PLATFORM")

    else

        # Attempt to auto-detect best build platform

        # Make sure `file` (libmagic) is available
        FILEBINARY=$(which file)
        if [ -z "$FILEBINARY" ]; then

            # If not available, build with no optimisations.
            # This should never happen, as it's included in the Dockerfile.
            echo "ERROR: 'file' (libmagic) not available, cannot detect architecture! Will build with no optimisations."
            CMAKE_CMD+=("-DPLATFORM=default")

        else

            FILEOUTPUT=$("${FILEBINARY}" -L "${FILEBINARY}")

            # 32-bit x86
            # Example output:
            # /usr/bin/file: ELF 32-bit LSB shared object, Intel 80386, version 1 (SYSV), dynamically linked, interpreter /lib/ld-musl-i386.so.1, stripped
            # /usr/bin/file: ELF 32-bit LSB shared object, Intel 80386, version 1 (SYSV), dynamically linked, interpreter /lib/ld-linux.so.2, for GNU/Linux 3.2.0, BuildID[sha1]=d48e1d621e9b833b5d33ede3b4673535df181fe0, stripped  
            if echo "${FILEOUTPUT}" | grep "Intel 80386" > /dev/null; then
                echo "Building with \"native\" optimisations."
                CMAKE_CMD+=("-DPLATFORM=native")
            fi

            # x86-64
            # Example output:
            # /usr/bin/file: ELF 64-bit LSB shared object, x86-64, version 1 (SYSV), dynamically linked, interpreter /lib/ld-musl-x86_64.so.1, stripped
            # /usr/bin/file: ELF 64-bit LSB shared object, x86-64, version 1 (SYSV), dynamically linked, interpreter /lib64/ld-linux-x86-64.so.2, for GNU/Linux 3.2.0, BuildID[sha1]=6b0b86f64e36f977d088b3e7046f70a586dd60e7, stripped
            if echo "${FILEOUTPUT}" | grep "x86-64" > /dev/null; then
                echo "Building with \"native\" optimisations."
                CMAKE_CMD+=("-DPLATFORM=native")
            fi

            # armel
            # /usr/bin/file: ELF 32-bit LSB shared object, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-linux.so.3, for GNU/Linux 3.2.0, BuildID[sha1]=f57b617d0d6cd9d483dcf847b03614809e5cd8a9, stripped
            if echo "${FILEOUTPUT}" | grep "ARM" > /dev/null; then

                # ARCH="arm"

                # Future TODO - detect and support armv6

                # armhf
                # Example outputs:
                # /usr/bin/file: ELF 32-bit LSB shared object, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-musl-armhf.so.1, stripped  # /usr/bin/file: ELF 32-bit LSB shared object, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-linux-armhf.so.3, for GNU/Linux 3.2.0, BuildID[sha1]=921490a07eade98430e10735d69858e714113c56, stripped
                # /usr/bin/file: ELF 32-bit LSB shared object, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-linux-armhf.so.3, for GNU/Linux 3.2.0, BuildID[sha1]=921490a07eade98430e10735d69858e714113c56, stripped
                if echo "${FILEOUTPUT}" | grep "armhf" > /dev/null; then

                    # Note - currently this script assumes the user is using an rpiv2 if it detects this CPU type,
                    # however this may not always be the case. We should find a way to determine if the CPU has
                    # videocore, and set rpiv2 if it does, or armv7-generic if it does not. This is a future TODO.
                    echo "Building with \"rpiv2\" optimisations."
                    CMAKE_CMD+=("-DPLATFORM=rpiv2")
                fi

                # arm64
                # Example output:
                # /usr/bin/file: ELF 64-bit LSB shared object, ARM aarch64, version 1 (SYSV), dynamically linked, interpreter /lib/ld-musl-aarch64.so.1, stripped
                # /usr/bin/file: ELF 64-bit LSB shared object, ARM aarch64, version 1 (SYSV), dynamically linked, interpreter /lib/ld-linux-aarch64.so.1, for GNU/Linux 3.7.0, BuildID[sha1]=a8d6092fd49d8ec9e367ac9d451b3f55c7ae7a78, stripped
                if echo "${FILEOUTPUT}" | grep "aarch64" > /dev/null; then
                    echo "Building with \"armv8-generic\" optimisations."
                    CMAKE_CMD+=("-DPLATFORM=armv8-generic")
                fi

            fi

            # If we don't have an architecture at this point, there's been a problem and we can't continue
            if [ -z "${ARCH}" ]; then
                echo "WARNING: Unable to determine architecture, will build with no optimisations."
                CMAKE_CMD+=("-DPLATFORM=default")
            fi
        fi
    fi

    # Do we build with NFM?
    # Handle "--no-modeac-auto"
    if [[ -n "$NFM_MAKE" ]]; then
        CMAKE_CMD+=("-DNFM=ON")
    fi

    # Turn off profiling
    CMAKE_CMD+=("-DPROFILING=OFF")
    CMAKE_CMD+=("-DCMAKE_BUILD_TYPE=Release")

    # Run cmake
    # shellcheck disable=SC2016
    cmake "${CMAKE_CMD[@]}" ../ \
        2>&1 | stdbuf -o0 sed --unbuffered '/^$/d' | stdbuf -o0 awk '{print "[building rtlair_band: cmake] " $0}'

    # Run make
    # shellcheck disable=SC2016
    make \
        2>&1 | stdbuf -o0 sed --unbuffered '/^$/d' | stdbuf -o0 awk '{print "[building rtlair_band: make] " $0}'

    # Install
    # shellcheck disable=SC2016
    make install \
        2>&1 | stdbuf -o0 sed --unbuffered '/^$/d' | stdbuf -o0 awk '{print "[building rtlair_band: make install] " $0}'

    # Change back to original directory
    popd > /dev/null 2>&1 
    popd > /dev/null 2>&1
fi
