#!/bin/bash

#set -e  # Exit on error
set -o pipefail  # Catch pipeline errors
# set -x  # Debug mode

export AWS_FPGA_REPO_DIR=~/aws/
LOG_FILE="$(pwd)/msg.log"

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" >> "$LOG_FILE"
}

# Function to add a line if it doesn't exist
add_if_not_exists() {
    local line="$1"
    local config_file="$2"
    
    # Check if the configuration already exists (ignoring commented lines)
    if ! sudo grep -q "^${line}" "$config_file"; then
        echo "Adding: $line"
        echo "$line" | sudo tee -a "$config_file" > /dev/null
    else
        echo "Line already exists: $line"
    fi
}

recipe_first_steps() {
    # We first write stuff to activate.sh, then in recipe_last_steps() we make a copy of it to cmakewrapper and add another line to it.
    echo "#!/bin/bash" > ~/activate.sh
    echo "if [[ -z "\$MY_ENV_ACTIVATED" ]]; then" >> ~/activate.sh
    echo "  export MY_ENV_ACTIVATED=1" >> ~/activate.sh
    sudo apt update
    sudo apt install -y terminator fish unzip htop

    # Install latest clangd
    wget https://apt.llvm.org/llvm.sh
    chmod +x llvm.sh
    sudo ./llvm.sh 19
    sudo apt install -y clangd-19 ninja-build
    sudo update-alternatives --install /usr/bin/clangd clangd /usr/bin/clangd-19 100
    rm llvm.sh
    log_message "Installed clangd-19 and set it as default with update-alternatives."
}

recipe_last_steps() {
    echo "  export PATH=\$PATH" >> ~/activate.sh 
    echo "  export LD_LIBRARY_PATH=\$LD_LIBRARY_PATH" >> ~/activate.sh
    echo "fi" >> ~/activate.sh
    cp ~/activate.sh ~/cmakewrapper
    sudo chmod +x ~/activate.sh
    sudo chmod +x ~/cmakewrapper
    echo "/usr/bin/cmake \"\$@\"" >> ~/cmakewrapper

    log_message "Finalized ~/activate.sh, you have to source it before using anything F1 and Vitis related."
    log_message "Finalized ~/cmakewrapper, use it instead of the cmake executable. No need to source activate.sh before. No need to worry about double sourcing."
    
    # increase sshd timeout, see https://bobcares.com/blog/ssh-timeout-server-not-responding/
    local SSH_CONFIG="/etc/ssh/sshd_config"

    # Add each line if it doesn't exist
    add_if_not_exists "KeepAlive yes" "$SSH_CONFIG"
    add_if_not_exists "ClientAliveInterval 120" "$SSH_CONFIG"
    add_if_not_exists "ClientAliveCountMax 2" "$SSH_CONFIG"

    echo "About to restart the ssh service. The ssh connection will drop."
    log_message "SSH configuration update complete"
    log_message "Restarting SSH service..."

    # Restart SSH service with systemd
    sudo systemctl restart sshd

    log_message "SSH service has been restarted."
}

recipe_build_cmake() {
    log_message " ##### Recipe: recipe_build_cmake"
    local CMAKE_VERSION="3.29.6"
    local CMAKE_URL="https://github.com/Kitware/CMake/archive/refs/tags/v${CMAKE_VERSION}.zip"
    local INSTALL_PREFIX="/usr/local"
    local NUM_CORES
    NUM_CORES=$(nproc)

    if command -v cmake &>/dev/null; then
        INSTALLED_VERSION=$(cmake --version | head -n1 | awk '{print $3}')
        if [ "$INSTALLED_VERSION" == "$CMAKE_VERSION" ]; then
            log_message "CMake $CMAKE_VERSION is already installed. Skipping build."
        else
            log_message "Installed CMake version ($INSTALLED_VERSION) does not match required version ($CMAKE_VERSION). Please uninstall it."
            exit 1
        fi
    else
        sudo apt update && sudo apt install -y unzip build-essential libssl-dev
        wget "$CMAKE_URL" -O "cmake-${CMAKE_VERSION}.zip"
        unzip "cmake-${CMAKE_VERSION}.zip"
        cd "CMake-${CMAKE_VERSION}" || exit 1

        ./bootstrap --prefix="$INSTALL_PREFIX"
        make -j "$NUM_CORES"
        sudo make install

        cmake --version
        log_message "CMake $CMAKE_VERSION installed successfully."
    fi
}

recipe_install_cmake_from_apt() {
    log_message " ##### Recipe: recipe_install_cmake_from_apt"

    if command -v cmake &>/dev/null; then
        sudo apt remove -y --purge --auto-remove cmake
    fi

    # https://askubuntu.com/questions/355565/how-do-i-install-the-latest-version-of-cmake-from-the-command-line
    sudo apt update && sudo apt install -y software-properties-common lsb-release && sudo apt clean all
    wget -O - https://apt.kitware.com/keys/kitware-archive-latest.asc 2>/dev/null | gpg --dearmor - | sudo tee /etc/apt/trusted.gpg.d/kitware.gpg >/dev/null
    sudo apt-add-repository "deb https://apt.kitware.com/ubuntu/ $(lsb_release -cs) main"
    sudo apt update
    sudo apt install -y kitware-archive-keyring
    sudo rm /etc/apt/trusted.gpg.d/kitware.gpg

    sudo apt update
    # w/o --allow-downgrades the latest version will be installed!
    sudo apt install -y --allow-downgrades cmake=3.29.6-0kitware1ubuntu20.04.1 cmake-data=3.29.6-0kitware1ubuntu20.04.1
    log_message "CMake version $(cmake --version) installed successfully from kitware apt repo."
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

recipe_clone_aws_repo() {
    log_message " ##### Recipe: recipe_clone_aws_repo"
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
    echo "  export AWS_PLATFORM=\"$AWS_PLATFORM\"" >> ~/activate.sh

    PLATFORM_REPO_PATHS="$(dirname "$AWS_PLATFORM")"
    echo "  export PLATFORM_REPO_PATHS=\"$PLATFORM_REPO_PATHS\"" >> ~/activate.sh

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
    log_message "XRT installed successfully from $(pwd)/xrt_*.deb"

    echo "  source /opt/xilinx/xrt/setup.sh > /dev/null 2>&1 # to prevent conflicts with rsync." >> ~/activate.sh
    echo "  source /opt/Xilinx/Vitis/2024.1/settings64.sh > /dev/null 2>&1" >> ~/activate.sh
    echo "  source /opt/Xilinx/Vitis_HLS/2024.1/settings64.sh > /dev/null 2>&1" >> ~/activate.sh
    echo "  source /opt/Xilinx/Vivado/2024.1/settings64.sh > /dev/null 2>&1" >> ~/activate.sh

    log_message "XRT initialization script added to ~/activate.sh"
}