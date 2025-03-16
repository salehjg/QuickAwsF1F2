#!/bin/bash

set -e  # Exit on error
set -o pipefail  # Catch pipeline errors
set -x  # Debug mode

# Variables
CMAKE_VERSION="3.31.5"
CMAKE_URL="https://github.com/Kitware/CMake/archive/refs/tags/v${CMAKE_VERSION}.zip"
INSTALL_PREFIX="/usr/local"
NUM_CORES=$(nproc)

check_cmake_installed() {
    if command -v cmake &>/dev/null; then
        INSTALLED_VERSION=$(cmake --version | head -n1 | awk '{print $3}')
        if [ "$INSTALLED_VERSION" == "$CMAKE_VERSION" ]; then
            echo "CMake $CMAKE_VERSION is already installed. Skipping build."
            exit 0
        else
            echo "Installed CMake version ($INSTALLED_VERSION) does not match required version ($CMAKE_VERSION). Proceeding with build."
        fi
    fi
}

install_dependencies() {
    sudo apt update && sudo apt install -y unzip build-essential libssl-dev
}

download_and_build_cmake() {
    wget "$CMAKE_URL" -O "cmake-${CMAKE_VERSION}.zip"
    unzip "cmake-${CMAKE_VERSION}.zip"
    cd "CMake-${CMAKE_VERSION}" || exit 1

    ./bootstrap --prefix="$INSTALL_PREFIX"
    make -j "$NUM_CORES"
    sudo make install
}

verify_installation() {
    cmake --version
    echo "CMake $CMAKE_VERSION installed successfully."
}


recipe_build_cmake() {
    check_cmake_installed
    install_dependencies
    download_and_build_cmake
    verify_installation
}
