# 2026-10-12T17:11:16.361463500
import vitis

client = vitis.create_client()
client.set_workspace(path="vitis_ws")

client.delete_component(name="difi_stage_a_test")

platform = client.get_component(name="difi_zynq_platform")
status = platform.update_hw(hw_design = "$COMPONENT_LOCATION/../../../vivado/difi_zynq_stage_b1/difi_zynq_stage_b1.xsa")

status = platform.build()

comp = client.create_app_component(name="difi_stage_b1_test",platform = "$COMPONENT_LOCATION/../difi_zynq_platform/export/difi_zynq_platform/difi_zynq_platform.xpfm",domain = "standalone_ps7_cortexa9_0")

status = platform.build()

comp = client.get_component(name="difi_stage_b1_test")
comp.build()

vitis.dispose()

