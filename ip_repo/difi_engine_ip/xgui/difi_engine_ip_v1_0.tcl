proc init_gui { IPINST } {
  ipgui::add_param $IPINST -name "Component_Name"
  
  set Page_0 [ipgui::add_page $IPINST -name "Page 0"]
  ipgui::add_param $IPINST -name "CLK_FREQ_HZ" -parent ${Page_0}

}

proc update_PARAM_VALUE.CLK_FREQ_HZ { PARAM_VALUE.CLK_FREQ_HZ } {
	
}

proc validate_PARAM_VALUE.CLK_FREQ_HZ { PARAM_VALUE.CLK_FREQ_HZ } {
	
	return true
}

proc update_MODELPARAM_VALUE.CLK_FREQ_HZ { MODELPARAM_VALUE.CLK_FREQ_HZ PARAM_VALUE.CLK_FREQ_HZ } {
	
	set_property value [get_property value ${PARAM_VALUE.CLK_FREQ_HZ}] ${MODELPARAM_VALUE.CLK_FREQ_HZ}
}
