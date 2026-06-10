set xsa_file "build/system_top.xsa"
set gen_dir "build/sdk/fsbl_hsi"
set out_dir "build/sdk/fsbl"

file delete -force $gen_dir $out_dir
file mkdir $gen_dir
file mkdir "$out_dir/Release"

hsi open_hw_design $xsa_file
hsi set_repo_path "/opt/Xilinx/Vitis/2023.2/data/embeddedsw"

set cpu_name [lindex [hsi get_cells -filter {IP_TYPE==PROCESSOR}] 0]
puts "Generating FSBL for processor: $cpu_name"

if {[catch {
	hsi generate_app -hw [hsi current_hw_design] -os standalone -proc $cpu_name -app zynq_fsbl -dir $gen_dir
} err]} {
	puts "First generate_app form failed: $err"
	puts "Trying software-design generate_app form..."

	hsi create_sw_design fsbl -proc $cpu_name -os standalone

	if {[catch {
		hsi generate_app -app zynq_fsbl -sw fsbl -dir $gen_dir
	} err2]} {
		error "Failed to generate FSBL: $err2"
	}
}

proc find_files {dir pattern} {
	set results {}
	foreach path [glob -nocomplain -directory $dir *] {
		if {[file isdirectory $path]} {
			set results [concat $results [find_files $path $pattern]]
		} elseif {[string match $pattern [file tail $path]]} {
			lappend results $path
		}
	}
	return $results
}

set makefiles [find_files $gen_dir "Makefile"]
if {[llength $makefiles] > 0} {
	set make_dir [file dirname [lindex $makefiles 0]]
	puts "Building generated FSBL in $make_dir"
	if {[catch {exec make -C $make_dir >@ stdout 2>@ stderr} make_err]} {
		puts "FSBL make returned an error or warning output:"
		puts $make_err
	}
} else {
	puts "No generated FSBL Makefile found; checking for prebuilt ELF."
}

set elfs [find_files $gen_dir "*.elf"]
if {[llength $elfs] == 0} {
	error "FSBL ELF was not generated under $gen_dir"
}

set fsbl_elf [lindex $elfs 0]
puts "Using FSBL ELF: $fsbl_elf"
file copy -force $fsbl_elf "$out_dir/Release/fsbl.elf"

hsi close_hw_design [hsi current_hw_design]
