start_server {tags {"bitops"}} {
    test {BITFIELD signed SET and GET basics} {
        r del bits
        set results {}
        lappend results [r bitfield bits set i8 0 -100]
        lappend results [r bitfield bits set i8 0 101]
        lappend results [r bitfield bits get i8 0]
        set results
    } {0 -100 101}

    test {BITFIELD unsigned SET and GET basics} {
        r del bits
        set results {}
        lappend results [r bitfield bits set u8 0 255]
        lappend results [r bitfield bits set u8 0 100]
        lappend results [r bitfield bits get u8 0]
        set results
    } {0 255 100}

    test {BITFIELD #<idx> form} {
        r del bits
        set results {}
        r bitfield bits set u8 #0 65
        r bitfield bits set u8 #1 66
        r bitfield bits set u8 #2 67
        r get bits
    } {ABC}

    test {BITFIELD basic INCRBY form} {
        r del bits
        set results {}
        r bitfield bits set u8 #0 10
        lappend results [r bitfield bits incrby u8 #0 100]
        lappend results [r bitfield bits incrby u8 #0 100]
        set results
    } {110 210}

    test {BITFIELD chaining of multiple commands} {
        r del bits
        set results {}
        r bitfield bits set u8 #0 10
        lappend results [r bitfield bits incrby u8 #0 100 incrby u8 #0 100]
        set results
    } {{110 210}}

    test {BITFIELD unsigned overflow wrap} {
        r del bits
        set results {}
        r bitfield bits set u8 #0 100
        lappend results [r bitfield bits overflow wrap incrby u8 #0 257]
        lappend results [r bitfield bits get u8 #0]
        lappend results [r bitfield bits overflow wrap incrby u8 #0 255]
        lappend results [r bitfield bits get u8 #0]
    } {101 101 100 100}

    test {BITFIELD unsigned overflow sat} {
        r del bits
        set results {}
        r bitfield bits set u8 #0 100
        lappend results [r bitfield bits overflow sat incrby u8 #0 257]
        lappend results [r bitfield bits get u8 #0]
        lappend results [r bitfield bits overflow sat incrby u8 #0 -255]
        lappend results [r bitfield bits get u8 #0]
    } {255 255 0 0}

    test {BITFIELD signed overflow wrap} {
        r del bits
        set results {}
        r bitfield bits set i8 #0 100
        lappend results [r bitfield bits overflow wrap incrby i8 #0 257]
        lappend results [r bitfield bits get i8 #0]
        lappend results [r bitfield bits overflow wrap incrby i8 #0 255]
        lappend results [r bitfield bits get i8 #0]
    } {101 101 100 100}

    test {BITFIELD signed overflow sat} {
        r del bits
        set results {}
        r bitfield bits set u8 #0 100
        lappend results [r bitfield bits overflow sat incrby i8 #0 257]
        lappend results [r bitfield bits get i8 #0]
        lappend results [r bitfield bits overflow sat incrby i8 #0 -255]
        lappend results [r bitfield bits get i8 #0]
    } {127 127 -128 -128}

    test {BITFIELD regression for #3221} {
        r set bits 1
        r bitfield bits get u1 0
    } {0}

    test {BITFIELD regression for #3564} {
        for {set j 0} {$j < 10} {incr j} {
            r del mystring
            set res [r BITFIELD mystring SET i8 0 10 SET i8 64 10 INCRBY i8 10 99900]
            assert {$res eq {0 0 60}}
        }
        r del mystring
    }
}

start_server {tags {"repl external:skip"}} {
    start_server {} {
        set master [srv -1 client]
        set master_host [srv -1 host]
        set master_port [srv -1 port]
        set slave [srv 0 client]

        test {BITFIELD: setup slave} {
            $slave slaveof $master_host $master_port
            wait_for_condition 50 100 {
                [s 0 master_link_status] eq {up}
            } else {
                fail "Replication not started."
            }
        }

        test {BITFIELD: write on master, read on slave} {
            $master del bits
            assert_equal 0 [$master bitfield bits set u8 0 255]
            assert_equal 255 [$master bitfield bits set u8 0 100]
            wait_for_ofs_sync $master $slave
            assert_equal 100 [$slave bitfield_ro bits get u8 0]
        }

        test {BITFIELD_RO fails when write option is used} {
            catch {$slave bitfield_ro bits set u8 0 100 get u8 0} err
            assert_match {*ERR BITFIELD_RO only supports the GET subcommand*} $err
        }
    }
}
