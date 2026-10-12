# 2026-10-12T20:18:11.406474800
import vitis

client = vitis.create_client()
client.set_workspace(path="vitis_ws")

platform = client.create_platform_component(name = "difi_platform_stage_a",hw_design = "$COMPONENT_LOCATION/../../../vivado/difi_zynq_stage_a/difi_zynq_stage_a.xsa",os = "standalone",cpu = "ps7_cortexa9_0",domain_name = "standalone_ps7_cortexa9_0")

platform = client.get_component(name="difi_platform_stage_a")
status = platform.build()

comp = client.create_app_component(name="difi_stage_a_test",platform = "$COMPONENT_LOCATION/../difi_platform_stage_a/export/difi_platform_stage_a/difi_platform_stage_a.xpfm",domain = "standalone_ps7_cortexa9_0")

status = platform.build()

comp = client.get_component(name="difi_stage_a_test")
comp.build()

status = platform.build()

comp.build()

client.delete_component(name="difi_dma_test")

platform = client.create_platform_component(name = "difi_platform_stage_b1",hw_design = "$COMPONENT_LOCATION/../../../vivado/difi_zynq_stage_b1/difi_zynq_stage_b1.xsa",os = "standalone",cpu = "ps7_cortexa9_0",domain_name = "standalone_ps7_cortexa9_0")

platform = client.get_component(name="difi_platform_stage_b1")
status = platform.build()

client.delete_component(name="difi_zynq_platform")

status = platform.build()

comp = client.get_component(name="difi_stage_b1_test")
comp.build()

status = comp.clean()

status = platform.build()

comp.build()

client.delete_component(name="difi_stage_b1_test")

comp = client.create_app_component(name="difi_stage_b1_test",platform = "$COMPONENT_LOCATION/../difi_platform_stage_b1/export/difi_platform_stage_b1/difi_platform_stage_b1.xpfm",domain = "standalone_ps7_cortexa9_0")

status = platform.build()

comp.build()

status = platform.build()

comp.build()

platform = client.create_platform_component(name = "difi_platform_stage_b2",hw_design = "$COMPONENT_LOCATION/../../../vivado/difi_zynq_stage_b2/difi_zynq_stage_b2.xsa",os = "standalone",cpu = "ps7_cortexa9_0",domain_name = "standalone_ps7_cortexa9_0")

platform = client.get_component(name="difi_platform_stage_b2")
status = platform.build()

comp = client.create_app_component(name="difi_stage_b2_test",platform = "$COMPONENT_LOCATION/../difi_platform_stage_b2/export/difi_platform_stage_b2/difi_platform_stage_b2.xpfm",domain = "standalone_ps7_cortexa9_0")

status = platform.build()

comp = client.get_component(name="difi_stage_b2_test")
comp.build()

status = platform.build()

comp.build()

status = comp.clean()

status = platform.build()

comp.build()

status = comp.clean()

status = platform.build()

comp.build()

vitis.dispose()

