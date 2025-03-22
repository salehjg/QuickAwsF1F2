# import common.sh
source common.sh

# https://adaptivesupport.amd.com/s/article/51582?language=en_US
# Users should not add xilinx to their LD_LIBRARY_PATH, but instead rely on the loaders
# (Vivado and ISE DS applications have boot loaders) to set up the necessary environment needed to run the application.

{
    recipe_first_steps
    
    recipe_install_cmake_from_apt
    #recipe_build_cmake
    recipe_vnc_server
    recipe_clone_aws_repo
    recipe_setup_aws_vitis
    recipe_setup_aws_xrt
    
    recipe_last_steps
} 2>&1 | tee full.log

