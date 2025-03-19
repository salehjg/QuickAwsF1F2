# import common.sh
source common.sh

{
    recipe_install_cmake_from_apt
    #recipe_build_cmake
    recipe_vnc_server
    recipe_clone_aws_repo
    recipe_setup_aws_vitis
    recipe_setup_aws_xrt
} 2>&1 | tee full.log