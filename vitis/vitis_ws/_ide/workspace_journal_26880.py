# 2026-10-12T16:55:26.289722300
import vitis

client = vitis.create_client()
client.set_workspace(path="vitis_ws")

platform = client.get_component(name="difi_zynq_platform")
status = platform.update_hw(hw_design = "$COMPONENT_LOCATION/../../../vivado/difi_zynq_stage_b1/difi_zynq_stage_b1.xsa")

status = platform.build()

comp = client.clone_component(name="difi_dma_test",new_name="difi_stage_a_test")

status = platform.build()

comp = client.get_component(name="difi_stage_a_test")
status = comp.clean()

comp.build()

status = comp.clean()

status = platform.update_hw(hw_design = "$COMPONENT_LOCATION/../../../vivado/difi_zynq_stage_a/difi_zynq_stage_a.xsa")

status = platform.build()

status = platform.build()

comp.build()

vitis.dispose()

