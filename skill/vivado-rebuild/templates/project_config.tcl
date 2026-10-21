# EDIT THIS TEMPLATE and save a copy inside YOUR repository, for example:
# scripts/vivado/config/my_project.tcl
# All paths below are relative to the REPOSITORY ROOT, not this Tcl file.
# Rebuild assumes the custom IP and user RTL are committed in the repo.
set ::vrskill_config [dict create \
    name           my_fpga_project \
    bd_name        design_1 \
    part           xc7z020clg400-2 \
    top            design_1_wrapper \
    vivado_version 2024.2 \
    snapshot_rel   scripts/vivado/generated/my_fpga_project \
    build_rel      vivado/rebuilt/my_fpga_project \
    report_rel     report/results/vivado_rebuild/my_fpga_project \
    rtl_globs      {rtl/top/*.v rtl/common/*.v rtl/include/*.vh} \
    include_dirs   {rtl/include} \
    ip_repo_dirs   {ip_repo} \
]
