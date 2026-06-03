transcript on

set repo_root [file normalize [pwd]]
set rtl_dir   [file join $repo_root "rtl"]
set work_dir  [file join $repo_root "sim" "work_algo"]

cd $repo_root

puts "INFO: repo_root = $repo_root"

if {[file exists $work_dir]} {
    vdel -lib $work_dir -all
}
file mkdir [file dirname $work_dir]
vlib $work_dir
vmap work $work_dir

set rtl_files [list \
    [file join $rtl_dir "RGB2YCbCr.v"] \
    [file join $rtl_dir "pixel_matrix_3x3.v"] \
    [file join $rtl_dir "sort3.v"] \
    [file join $rtl_dir "median_filter_3x3.v"] \
    [file join $rtl_dir "algorithm_cycle_tb.sv"] \
]

puts "INFO: compiling RTL..."
vlog -sv -work work {*}$rtl_files

puts "INFO: starting algorithm cycle simulation..."
vsim -c -onfinish stop -voptargs=+acc -t 1ps work.algorithm_cycle_tb

log -r /*
add wave -r /*

run -all

puts "INFO: algorithm cycle simulation finished"
