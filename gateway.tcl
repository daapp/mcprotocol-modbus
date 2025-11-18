#!/usr/bin/env tclsh

# из tcllib
package require crc16

# размер запроса по modbus
set mbReqSize 8

array set config {
    tcp_port 502
    serial_port COM3
    baud 38400
    parity e
    databits 7
    stopbits 1
    modbusDeviceAddress 1
}


proc log {message args} {
    puts [format "%s # $message" [clock format [clock seconds] -format {%H:%M:%S}] {*}$args]
}


# Функция для чтения конфигурации
proc read_config {file} {
    set config [list]

    set fd [open $file r]
    while {[gets $fd line] >= 0} {
        if {[regexp {^\s*(\w+)\s*=\s*(.+)\s*$} $line - key val]} {
            lappend config $key $val
        }
    }
    close $fd

    return $config
}


# Вычисление checksum modbus
proc mb_checksum {data} {
    crc::crc16 -seed 0xFFFF $data
}


# data - binary string
proc melsec_checksum {data} {
    binary scan $data cu* bytes
    set sum 0
    foreach byte $bytes {
        incr sum $byte
    }
    return [expr {$sum &0xFF}]
}


# return empty list on error
# or {function payload} list, where function is hex decoded function number, payload - binary string
proc mb_parse {data} {
    variable config
    if {$data eq ""} {
        log "mb_parse: empty package"
        return
    }
    binary scan $data cuH2a* device function rest
    if {$device == $config(modbusDeviceAddress)} {
        switch -- $function {
            03 {
                binary scan $data a6s body checkSum
                set cs [mb_checksum $body]
                if { $cs != $checkSum } {
                    log "Invalid check sum for package: %s" [binary encode hex $data]
                    return
                }

                binary scan $data @2a4 payload
                log "payload [binary encode hex $payload]"
                return [list $function $payload]
            }
            default {
                log "Function $function is not yet implemented"
                return
            }
        }
    } else {
        log "Ignore package for device $device"
        return
    }
}


# Отправка FX запроса и чтение ответа
proc fx_exchange {serial payload} {
    if 0 {
        Функция, которая будет преобразовывать и передавать в плк данные. все
        манипуляции идут с бинарными данными.  в примере данные представлены в
        hex для удобства.

        Пример входного пакета modbus tcp.
        01 03 00 A0 00 01 84 28

        Два байта первых отсекаем - адрес устройства и номер функции. адрес 01
        нам пофиг, номер функции всегда 03. поэтому пока тоже пофиг. но можно
        сделать проверку чтобы в будущем можно было писать (функция 06).

        Берем значение Adr=0x00A0
        Берем значение Len=0x0001
        Далее отсекаем старший байт Len -> Len=0x01, умножаем Len на 2 -> Len =
        0x02. умножать нужно потому что melsec оперирует данными длиной 8 бит,
        а мы запрашиваем данные длиной 16 бит.

        Из полученных Adr и Len формируем пакет данных на выходе.

        02 30 30 30 41 30 30 32 03 36 36

        Где 02 30 - константа. по протоколу melsec это команда "считать данные"
        30 30 41 30 - значение adr (00A0)  в формате ascii hex
        30 32 - значение len (02) в формате ascii hex
        03 - константа. по протоколу melsec это признак конца данных.
        36 36 - контрольная сумма по мобудлю 256 после 02 и до 03 включительно.
        для данного примера значение 36 36 (0x66) - верное.

        Далее мы отправляем бинарные данные 02 30 30 30 41 30 30 32 03 36 36 в порт $::serial, и получаем оттуда ответ.

        Ответ будет в формате 

        02 <данные> 03 CRC1 CRC2
        Мы берем данные из ответа и возвращаем их
    }
    binary scan $payload H2H2xcu a1 a2 len
 
    set addr [string toupper "$a1$a2"]
    binary scan $addr H2H2H2H2 a1 a2 a3 a4

    set len [expr {$len * 2}]
    set ascii [string toupper [binary encode hex [binary format cu $len]]]
    binary scan $ascii H2H2 l1 l2

    set rtuPayload [binary format c* [list 0x02 0x30 0x$a1 0x$a2 0x$a3 0x$a4 0x$l1 0x$l2 0x03]]
    binary scan $rtuPayload xa* body
    binary scan [binary format cu [melsec_checksum $body]] H2 sum
    append rtuPayload $sum

    log "Send to serial: [binary encode hex $rtuPayload]"
    puts -nonewline $serial $rtuPayload
    flush $serial

    return 1
}


proc mb_response {chan data} {
    if 0 {
        Здесь мы берем данные от ПЛК и формируем Modbus пакет в формате
        01 03 <длина в байтах, 1 байт> <данные> <результат mb_checksum, 2 байта.> 
        пинаем его в $chan и выходим
    }
    set message [binary format ccca*s 0x01 0x03 [string length $data] $data [mb_checksum $data]]
    lassign [fconfigure $chan -sockname] addr -> port
    log "$addr:${port} TCP response >>> [binary encode hex $message]"
    puts -nonewline $chan $message
    flush $chan

    return
}


# Обработчик Modbus TCP соединения
proc handle_client {serial chan addr port} {
    log "Client $addr:${port} connected ... $chan"

    fconfigure $chan -buffering none -encoding binary -translation binary
    while 1 {
        set data [read $chan $::mbReqSize]
        lassign [mb_parse $data] function payload

        if {[eof $chan]} break
        if {$function eq ""} continue
 
        log "$addr:${port} TCP request << $function [binary encode hex $payload]"
        switch -- $function {
            03 {
                set response [fx_exchange $serial $payload]
                mb_response $chan $response
            }
            default {
                log "Ignore package [binary encode hex $data]"
            }
        }
    }
    close $chan
}


if {$argc != 1} {
    puts stderr "Usage: $argv0 file.conf"
    exit 1
}

array set config [read_config [lindex $argv 0]]

set serial [open $config(serial_port) r+]
fconfigure $serial \
    -mode "$config(baud),$config(parity),$config(databits),$config(stopbits)" \
    -buffering none \
    -encoding binary \
    -translation binary \
    -blocking 0

# Запуск TCP сервера
log "Starting server on port $config(tcp_port) ..."
socket -server [list handle_client $serial] $config(tcp_port)

# Бесконечный цикл для работы как служба
vwait forever

