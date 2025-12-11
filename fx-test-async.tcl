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

set n 4
proc processFrame {serial asciiHexList} {
    puts "$serial >> $asciiHexList"

    incr ::n -1
    if {$::n == 0} {
        set ::forever 1
    } else {
        puts "$::serial << $::req"
        fx write $::serial $::req
    }
}

puts -nonewline "Open serial port $mode ... "
flush stdout

set serial [fx open $config(serial_port) $mode processFrame]
puts " $serial"
flush $serial

set req {02 30 31 30 46 36 30 34 03 37 34}
puts "$serial << $req"

fx writeFrame $serial $req

vwait forever

