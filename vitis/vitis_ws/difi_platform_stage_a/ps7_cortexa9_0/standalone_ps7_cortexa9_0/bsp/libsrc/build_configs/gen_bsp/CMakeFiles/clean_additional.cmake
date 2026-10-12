# Additional clean files
cmake_minimum_required(VERSION 3.16)

if("${CONFIG}" STREQUAL "" OR "${CONFIG}" STREQUAL "")
  file(REMOVE_RECURSE
  "D:\\Study\\project\\DIFI\\vitis\\vitis_ws\\difi_platform_stage_a\\ps7_cortexa9_0\\standalone_ps7_cortexa9_0\\bsp\\include\\sleep.h"
  "D:\\Study\\project\\DIFI\\vitis\\vitis_ws\\difi_platform_stage_a\\ps7_cortexa9_0\\standalone_ps7_cortexa9_0\\bsp\\include\\xiltimer.h"
  "D:\\Study\\project\\DIFI\\vitis\\vitis_ws\\difi_platform_stage_a\\ps7_cortexa9_0\\standalone_ps7_cortexa9_0\\bsp\\include\\xtimer_config.h"
  "D:\\Study\\project\\DIFI\\vitis\\vitis_ws\\difi_platform_stage_a\\ps7_cortexa9_0\\standalone_ps7_cortexa9_0\\bsp\\lib\\libxiltimer.a"
  )
endif()
