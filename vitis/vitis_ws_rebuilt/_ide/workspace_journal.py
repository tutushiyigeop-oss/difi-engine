# 2026-10-21T12:58:51.210931200
import vitis

client = vitis.create_client()
client.set_workspace(path="vitis_ws_rebuilt")

platform = client.create_platform_component(name = "difi_platform_stage_b5_UDP",hw_design = "$COMPONENT_LOCATION/../../../vivado/rebuilt/b5_raw_export/b5_raw_export_rebuilt.xsa",os = "standalone",cpu = "ps7_cortexa9_0",domain_name = "standalone_ps7_cortexa9_0")

platform = client.get_component(name="difi_platform_stage_b5_UDP")
domain = platform.get_domain(name="standalone_ps7_cortexa9_0")

status = domain.set_lib(lib_name="lwip220", path="D:\software\xilinx_2024.2\Vitis\2024.2\data\embeddedsw\ThirdParty\sw_services\lwip220_v1_1")

status = platform.build()

comp = client.create_app_component(name="difi_b5_udp_tx",platform = "$COMPONENT_LOCATION/../difi_platform_stage_b5_UDP/export/difi_platform_stage_b5_UDP/difi_platform_stage_b5_UDP.xpfm",domain = "standalone_ps7_cortexa9_0")

status = platform.build()

comp = client.get_component(name="difi_b5_udp_tx")
comp.build()

platform = client.create_platform_component(name = "difi_ip_platform",hw_design = "$COMPONENT_LOCATION/../../../vivado/rebuilt/packaged_ip/packaged_ip_rebuilt.xsa",os = "standalone",cpu = "ps7_cortexa9_0",domain_name = "standalone_ps7_cortexa9_0")

platform = client.get_component(name="difi_ip_platform")
status = platform.build()

comp = client.create_app_component(name="difi_ip_loopback_test",platform = "$COMPONENT_LOCATION/../difi_ip_platform/export/difi_ip_platform/difi_ip_platform.xpfm",domain = "standalone_ps7_cortexa9_0")

status = platform.build()

comp = client.get_component(name="difi_ip_loopback_test")
comp.build()

