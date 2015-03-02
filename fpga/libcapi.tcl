
foreach filename [glob $LIBCAPI/rtl/*.vhd] {
    set_global_assignment -name VHDL_FILE -library capi $filename
}
