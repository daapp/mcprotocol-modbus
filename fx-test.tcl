#! /bin/sh
# \
exec tclsh "$0" ${1+"$@"}

source fx.tcl


array set config {
    serial_port /dev/ttyS10
    baud 38400
    parity e
    databits 7
    stopbits 1
}

set mode "$config(baud),$config(parity),$config(databits),$config(stopbits)"

puts -nonewline "Open serial port $mode ... "
flush stdout

set serial [fx open $config(serial_port) $mode]
puts " $serial"
flush $serial

set req {02 30 31 30 46 36 30 34 03 37 34}
puts "$serial << $req"
#puts -nonewline $serial $req
fx write $serial $req
flush $serial
puts -nonewline "$serial >> "
flush stdout 
puts [fx read $serial]

