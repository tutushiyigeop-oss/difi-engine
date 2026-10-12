# 2026-10-12T15:30:02.623160
import vitis

client = vitis.create_client()
client.set_workspace(path="vitis_ws")

platform = client.create_platform_component(name = "difi_zynq_platform",hw_design = "$COMPONENT_LOCATION/../../../vivado/difi_zynq_stage_a/difi_zynq_stage_a.xsa",os = "standalone",cpu = "ps7_cortexa9_0",domain_name = "standalone_ps7_cortexa9_0")

comp = client.create_app_component(name="difi_dma_test",platform = "$COMPONENT_LOCATION/../difi_zynq_platform/export/difi_zynq_platform/difi_zynq_platform.xpfm",domain = "standalone_ps7_cortexa9_0")

platform = client.get_component(name="difi_zynq_platform")
status = platform.build()

status = platform.build()

comp = client.get_component(name="difi_dma_test")
comp.build()

status = platform.build()

comp.build()

status = platform.build()

comp.build()

status = comp.clean()

status = platform.build()

comp.build()

status = platform.build()

comp.build()

status = comp.clean()

status = platform.build()

comp.build()

status = comp.clean()

status = platform.build()

comp.build()

status = comp.clean()

status = platform.build()

comp.build()

vitis.dispose()

