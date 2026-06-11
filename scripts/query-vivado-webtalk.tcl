foreach p [list_param] {
  if {[string match -nocase *webtalk* $p] || [string match -nocase *talk* $p] || [string match -nocase *host* $p]} {
    puts $p
  }
}
exit
