transcript on

set repo_root  [file normalize [pwd]]
set rtl_dir    [file join $repo_root "rtl"]
set work_dir   [file join $repo_root "sim" "work"]

cd $repo_root

puts "INFO: repo_root = $repo_root"
puts "INFO: rtl_dir   = $rtl_dir"

if {[file exists $work_dir]} {
    vdel -lib $work_dir -all
}
file mkdir [file dirname $work_dir]
vlib $work_dir
vmap work $work_dir

set rtl_files [list \
    [file join $rtl_dir "apb_host_driver.v"] \
    [file join $rtl_dir "filter_apb_if.v"] \
    [file join $rtl_dir "sram_reader.v"] \
    [file join $rtl_dir "sram_writer.v"] \
    [file join $rtl_dir "pixel_matrix_3x3.v"] \
    [file join $rtl_dir "sort3.v"] \
    [file join $rtl_dir "median_filter_3x3.v"] \
    [file join $rtl_dir "RGB2YCbCr.v"] \
    [file join $rtl_dir "sram_2Mx64.v"] \
    [file join $rtl_dir "median_filter_top.v"] \
    [file join $rtl_dir "testbench.sv"] \
]

puts "INFO: compiling RTL..."
vlog -sv -work work {*}$rtl_files

puts "INFO: starting simulation..."
vsim -c -t 1ps work.testbench \
    +OUT_FILE=rtl/output

run -all

puts "INFO: simulation finished"
quit -f
