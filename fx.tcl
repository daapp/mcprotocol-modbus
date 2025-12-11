namespace eval fx {
    variable queue
    # queue store incomplete fx frame for each serial port
    # keys:
    # - portname,data - frame content
    # - portname,state - state of frame reading
    array set queue {}

    variable defaultMode "38400,e,7,1"

    # fxChars: 5 special characters,  0..9, A..F
    variable fxChars [dict create {*}{
        ENQ 05
        ACK 06
        NAK 15
        STX 02
        ETX 03
    }]
    # fill fxChars with additional characters 0..9, A..F
    foreach char {0 1 2 3 4 5 6 7 8 9 A B C D E F} {
        binary scan $char H2 code
        dict set fxChars $char $code
    }

    # export subcommands beginning with lower case letter
    namespace export {[a-z][-_a-z0-9]*}
    namespace ensemble create
}


# fx::open - open serial port
# port - serial port name
# mode - value for fconfigure $chan -mode, see "man 3tcl open"
# Return: serial port channel name
proc fx::open {port {mode ""} {callback ""}} {
    variable defaultMode
    variable queue

    if {$mode eq ""} {
        set mode $defaultMode
    }
    set blocking [expr {$callback eq ""}]

    set serial [::open $port r+]
    chan configure $serial -mode $mode \
        -buffering none \
        -encoding binary \
        -translation binary \
        -blocking $blocking

    if {$callback ne ""} {
        set queue($serial,data) ""
        set queue($serial,state) STX
        chan event $serial readable [list [namespace current]::ReadAsync $serial $callback]
    }

    return $serial
}


proc fx::close {serial} {
    variable queue
    array unset queue $serial,*
    chan close $serial
}


# fx::readFrame - read frame from FX232 device
# serial - tcl channel name
# Return: frame in asciiHex encoding as list if checksum is valid, otherwise - error
proc fx::readFrame {serial} {
    variable fxChars

    set res [list]
    set pos 0
    while 1 {
        set hex [readChar $serial]
        if {$pos == 0} {
            if {$hex eq [dict get $fxChars STX]} {
                lappend res $hex
            } else {
                return -code error \
                    -errorinfo "invalid data from $serial: should be [dict get $fxChars STX], but $hex received"
            }
        } else {
            lappend res $hex
            if {$hex eq [dict get $fxChars ETX]} {
                break
            }
        }
        incr pos
    }
    set cs [Checksum [lrange $res 1 end]]
 
    # read FX control sum
    lappend res [readChar $serial]
    lappend res [readChar $serial]

    if {$cs ne [lrange $res end-1 end]} {
        return -code error -errorinfo "invalid checksum in $res"
    } else {
        return $res
    }
}


proc fx::ReadAsync {serial callback} {
    variable fxChars
    variable queue

    set hex [readChar $serial]
    switch -- $queue($serial,state) {
        "STX" {
            if {$hex eq [dict get $fxChars STX]} {
                lappend queue($serial,data) $hex
                set queue($serial,state) ETX
            } else {
                return -code error \
                    -errorinfo "invalid data from $serial: should be [dict get $fxChars STX], but $hex receives"
            }
        }
        "ETX" {
            lappend queue($serial,data) $hex
            if {$hex eq [dict get $fxChars ETX]} {
                set queue($serial,state) SUM1
            }
        }
        "SUM1" {
            lappend queue($serial,data) $hex
            set queue($serial,state) SUM2
        }
        "SUM2" {
            lappend queue($serial,data) $hex
            set cs [Checksum [lrange $queue($serial,data) 1 end-2]]
            if {$cs ne [lrange $queue($serial,data) end-1 end]} {
                return -code error -errorinfo "invalid checksum in $queue($serial,data)"
            } else {
                set frame $queue($serial,data)
                set queue($serial,data) ""
                set queue($serial,state) STX
                uplevel #0 [list $callback $serial $frame]
            }
        }
    }
}


# fx::readChar - read single byte from serial port
# Return: ascii hex value of byte
proc fx::readChar {serial} {
    variable fxChars

    set c [ToAsciiHex [chan read $serial 1]]
    if {$c in [dict values $fxChars]} {
        return $c
    } else {
        return -code error -errorinfo "invalid character $c in $serial"
    }
}


# fx::writeFrame - write converted ascii hex list to serial port
proc fx::writeFrame {serial asciiHexList} {
    chan puts -nonewline $serial [FromAsciiHex $asciiHexList]
    flush $serial
}


# Return: asciiHex value of check sum
proc fx::Checksum {asciiHexList} {
    set sum 0
    foreach byte $asciiHexList {
        incr sum 0x$byte
    }
    ToAsciiHex [format %02X [expr {$sum & 0xFF}]]
}


# fx::SplitAsciiHex - split ascii hex string into list by two digits
proc fx::SplitAsciiHex {asciiHex} {
    set len [string length $asciiHex]
    set res [list]
    for {set p 0} {$p <= $len-2} {incr p 2} {
        lappend res [string range $asciiHex $p $p+1]
    }
    return $res
}


# fx::ToAsciiHex - convert binary string to ascii hex list
proc fx::ToAsciiHex {binData} {
    binary scan $binData H* bytes
    SplitAsciiHex [string toupper $bytes]
}


# fx::FromAsciiHex - convert ascii hex list to binary string
proc fx::FromAsciiHex {asciiHexList} {
    binary format H* [join $asciiHexList {}]
}

