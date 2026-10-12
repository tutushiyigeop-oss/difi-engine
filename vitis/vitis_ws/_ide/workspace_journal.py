# 2026-10-12T21:01:26.807253300
import vitis

client = vitis.create_client()
client.set_workspace(path="vitis_ws")

platform = client.create_platform_component(name = "difi_platform_stage_b3",hw_design = "$COMPONENT_LOCATION/../../../vivado/difi_zynq_stage_b3/difi_zynq_stage_b3.xsa",os = "standalone",cpu = "ps7_cortexa9_0",domain_name = "standalone_ps7_cortexa9_0")

platform = client.get_component(name="difi_platform_stage_b3")
status = platform.build()

comp = client.create_app_component(name="difi_stage_b3_test",platform = "$COMPONENT_LOCATION/../difi_platform_stage_b3/export/difi_platform_stage_b3/difi_platform_stage_b3.xpfm",domain = "standalone_ps7_cortexa9_0")

status = platform.build()

comp = client.get_component(name="difi_stage_b3_test")
comp.build()

status = platform.build()

comp.build()

vitis.dispose()

