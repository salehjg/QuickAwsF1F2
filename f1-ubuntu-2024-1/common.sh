#!/bin/bash

#set -e  # Exit on error
set -o pipefail  # Catch pipeline errors
# set -x  # Debug mode

# Variables
CMAKE_VERSION="3.31.5"
CMAKE_URL="https://github.com/Kitware/CMake/archive/refs/tags/v${CMAKE_VERSION}.zip"
INSTALL_PREFIX="/usr/local"
NUM_CORES=$(nproc)

export AWS_FPGA_REPO_DIR=~/aws/

log_message() {
    local LOG_FILE="msg.log"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" >> "$LOG_FILE"
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
    log_message "CMake $CMAKE_VERSION installed successfully."
}


recipe_build_cmake() {
    log_message " ##### Recipe: recipe_build_cmake"
    if command -v cmake &>/dev/null; then
        INSTALLED_VERSION=$(cmake --version | head -n1 | awk '{print $3}')
        if [ "$INSTALLED_VERSION" == "$CMAKE_VERSION" ]; then
            log_message "CMake $CMAKE_VERSION is already installed. Skipping build."
        else
            log_message "Installed CMake version ($INSTALLED_VERSION) does not match required version ($CMAKE_VERSION). Please uninstall it."
            exit 1
        fi
    else
        install_dependencies
        download_and_build_cmake
        verify_installation
    fi
}

recipe_vnc_server() {
    log_message " ##### Recipe: recipe_vnc_server"
    USER=$(whoami)
    log_message "Detected user: $USER"
    sudo apt update
    sudo apt install -y git
    sudo apt install -y linux-headers-$(uname -r)
    sudo apt install -y xfce4 xfce4-goodies xorg dbus-x11 x11-xserver-utils
    XSTARTUP_FILE="$HOME/.vnc/xstartup"
    mkdir -p "$(dirname "$XSTARTUP_FILE")"
    cat <<EOL > "$XSTARTUP_FILE"
#!/bin/bash
export XDG_SESSION_TYPE=x11
export XDG_SESSION_DESKTOP=xfce
export XDG_CURRENT_DESKTOP=XFCE
# Set screen resolution to Full HD (1920x1080)
xrandr --output VNC-0 --mode 1920x1080
exec startxfce4 &
EOL
    chmod +x "$XSTARTUP_FILE"
    echo "xstartup file created and configured."
    sudo systemctl set-default graphical.target
    sudo apt install -y xrdp tigervnc-standalone-server tigervnc-common
    sudo systemctl start xrdp
    sudo systemctl enable xrdp
    sudo systemctl stop ufw
    sudo systemctl disable ufw
    sudo passwd $USER
    #vncserver -kill :1
    vncserver :1 -geometry 1920x1080 -localhost no
    VNC_LOG_PATH="$HOME/.vnc/$(hostname):1.log"
    log_message "VNC log file can be found at: $VNC_LOG_PATH"
    PUBLIC_IP=$(curl -s ifconfig.me)
    log_message "** VNC is now available at: $PUBLIC_IP:5901"
}

recipe_build_clone_aws_repo() {
    log_message " ##### Recipe: recipe_build_clone_aws_repo"
    USER=$(whoami)
    mkdir -p $AWS_FPGA_REPO_DIR

    sudo apt update
    sudo apt install -y awscli # dont install cmake, its too old to build xrt from src!
    aws configure
    git clone https://github.com/aws/aws-fpga.git $AWS_FPGA_REPO_DIR
    cd $AWS_FPGA_REPO_DIR
    git checkout f1_xdma_shell # ubuntu AMI is F1 - Vitis 2024.1, so we need to use this branch.
}

recipe_setup_aws_vitis() {
    log_message " ##### Recipe: recipe_setup_aws_vitis"
    cd $AWS_FPGA_REPO_DIR
    source vitis_setup.sh
    # Check if the variable is already defined in ~/.bashrc
    if grep -q "export AWS_PLATFORM=" ~/.bashrc; then
        log_message "AWS_PLATFORM is already defined in ~/.bashrc. Updating it to the new value."
        # Update the existing value in ~/.bashrc
        sed -i "s|^export AWS_PLATFORM=.*|export AWS_PLATFORM=\"$AWS_PLATFORM\"|" ~/.bashrc
    else
        log_message "Adding AWS_PLATFORM to ~/.bashrc."
        # Append the export command to ~/.bashrc
        echo "export AWS_PLATFORM=\"$AWS_PLATFORM\"" >> ~/.bashrc
    fi

    PLATFORM_REPO_PATHS="$(dirname "$AWS_PLATFORM")"

    # Check if PLATFORM_REPO_PATHS is already defined in ~/.bashrc
    if grep -q "export PLATFORM_REPO_PATHS=" ~/.bashrc; then
        log_message "PLATFORM_REPO_PATHS is already defined in ~/.bashrc. Updating it to the new value."
        # Update the existing value in ~/.bashrc
        sed -i "s|^export PLATFORM_REPO_PATHS=.*|export PLATFORM_REPO_PATHS=\"$PLATFORM_REPO_PATHS\"|" ~/.bashrc
    else
        log_message "Adding PLATFORM_REPO_PATHS to ~/.bashrc."
        # Append the export command to ~/.bashrc
        echo "export PLATFORM_REPO_PATHS=\"$PLATFORM_REPO_PATHS\"" >> ~/.bashrc
    fi

    source ~/.bashrc
    log_message "To confirm that the setup is correct, please run: /opt/Xilinx/Vitis/2024.1/bin/platforminfo -l"
    log_message "** AWS_PLATFORM is set to: $AWS_PLATFORM"
    log_message "** PLATFORM_REPO_PATHS is set to: $PLATFORM_REPO_PATHS"
}

recipe_setup_aws_xrt() {
    log_message " ##### Recipe: recipe_setup_aws_xrt"
    XRT_RELEASE_TAG=202410.2.17.319 # Substitute XRT_RELEASE_TAG=<TAG from above table>
    cd $AWS_FPGA_REPO_DIR
    source vitis_setup.sh
    cd $VITIS_DIR/Runtime
    export XRT_PATH="${VITIS_DIR}/Runtime/${XRT_RELEASE_TAG}"
    git clone http://www.github.com/Xilinx/XRT.git -b ${XRT_RELEASE_TAG} ${XRT_PATH}

    cd ${XRT_PATH}
    sudo ./src/runtime_src/tools/scripts/xrtdeps.sh

    cd build
    ./build.sh

    cd Release
    sudo apt install ./xrt_*.deb
}