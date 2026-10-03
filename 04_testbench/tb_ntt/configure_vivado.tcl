# vivado -mode batch -source configure_vivado.tcl -tclargs <project.xpr>
set tb_dir [file dirname [file normalize [info script]]]
set repo_dir [file dirname [file dirname $tb_dir]]
if {[llength $argv] != 1} { error "Expected path to project.xpr" }
set project_file [file normalize [lindex $argv 0]]
file copy $project_file "${project_file}.ntt-backup-[clock seconds]"
open_project $project_file

foreach {ip coe} {blk_mem_gen_3 gamma_p1_n512.coe blk_mem_gen_4 gamma_p2_n512.coe} {
    if {[llength [get_ips -quiet $ip]] == 0} {
        create_ip -name blk_mem_gen -vendor xilinx.com -library ip -version 8.4 -module_name $ip
    }
    set_property -dict [list CONFIG.Memory_Type {Single_Port_ROM} \
        CONFIG.Write_Width_A {32} CONFIG.Read_Width_A {32} \
        CONFIG.Write_Depth_A {512} CONFIG.Enable_A {Use_ENA_Pin} \
        CONFIG.Register_PortA_Output_of_Memory_Primitives {true} \
        CONFIG.Register_PortA_Output_of_Memory_Core {false} \
        CONFIG.Load_Init_File {true} \
        CONFIG.Coe_File [file join $repo_dir 05_software rom $coe]] [get_ips $ip]
    generate_target all [get_ips $ip]
}
set ntt_file [file join $repo_dir 03_design ntt.vhd]
if {[llength [get_files -quiet $ntt_file]] == 0} {
    add_files -fileset sources_1 -norecurse $ntt_file
}
set_property file_type {VHDL 2008} [get_files $ntt_file]

foreach sim_name {sim_ntt sim_ntt_p1 sim_ntt_p2} {
    if {[llength [get_filesets -quiet $sim_name]] == 0} {
        create_fileset -simset $sim_name
    }
    set fs [get_filesets $sim_name]
    foreach path [list [file join $tb_dir ntt_tb.vhd] [file join $tb_dir vectors_p1.txt] [file join $tb_dir vectors_p2.txt]] {
        if {[llength [get_files -quiet -of_objects $fs $path]] == 0} {
            add_files -fileset $sim_name -norecurse $path
        }
    }
    set_property file_type {VHDL 2008} [get_files -of_objects $fs *ntt_tb.vhd]
    set_property file_type {Data Files} [get_files -of_objects $fs *vectors_*.txt]
    set_property top ntt_tb $fs
    set_property generic {} $fs
    set_property xsim.simulate.runtime {0ns} $fs
    update_compile_order -fileset $sim_name
}
current_fileset -simset [get_filesets sim_ntt]
launch_simulation -simset sim_ntt -mode behavioral
log_wave -r /ntt_tb/*
run 2 ms
close_sim
close_project
