#!/usr/bin/env tclsh

# из tcllib
package require crc16


array set config {
    tcp_port 502
    serial_port COM3
    baud 38400
    parity e
    databits 7
    stopbits 1
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


# Вычисление checksum melsec. Понадобится но наверное потом, если сделаем не только чтение но и запись по modbus.
proc fx_checksum {data} {}


# Вычисление checksum modbus
proc mb_checksum {data} {
    crc::crc16 -seed 0xFFFF $data
}


# Отправка FX запроса и чтение ответа
proc fx_exchange {serial data} {
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

        Из полученных Adr и Len формируем пакет данных на выходе

        02 30 30 30 41 30 30 32 03 36 36 Где
        02 30 - константа. по протоколу melsec это команда "считать данные"
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
    puts [info level 0]
    puts -nonewline $serial $data
    flush $serial
    return 1
}


proc mb_push {chan data} {
    if 0 {
        Здесь мы берем данные от ПЛК и формируем Modbus пакет в формате
        01 03 <длина в байтах, 1 байт> <данные> <результат mb_checksum, 2 байта.> 
        пинаем его в $chan и выходим
    }
    set message [binary format ccca*s 0x01 0x03 [string length $data] $data [mb_checksum $data]]
    lassign [fconfigure $chan -sockname] addr -> port
    puts "$addr:${port} TCP response >>> [binary encode hex $message]"
    puts -nonewline $chan $message
    flush $chan
}


# Обработчик Modbus TCP соединения
proc handle_client {serial chan addr port} {
    puts "Client $addr:${port} connected ... $chan"

    fconfigure $chan -buffering none -encoding binary -translation binary
    while 1 {
        # Чтение команды 03 modbus (8 bytes)
        set data [read $chan 8]

        if {[eof $chan]} break

        puts "$addr:${port} TCP request << [binary encode hex $data]"
		set response [fx_exchange $chan $data]
		mb_push $chan $response
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
puts "Starting server on port $config(tcp_port) ..."
socket -server [list handle_client $serial] $config(tcp_port)

# Бесконечный цикл для работы как служба
vwait forever

