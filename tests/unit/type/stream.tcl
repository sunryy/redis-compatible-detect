# return value is like strcmp() and similar.
proc streamCompareID {a b} {
    if {$a eq $b} {return 0}
    lassign [split $a -] a_ms a_seq
    lassign [split $b -] b_ms b_seq
    if {$a_ms > $b_ms} {return 1}
    if {$a_ms < $b_ms} {return -1}
    # Same ms case, compare seq.
    if {$a_seq > $b_seq} {return 1}
    if {$a_seq < $b_seq} {return -1}
}

# return the ID immediately greater than the specified one.
# Note that this function does not care to handle 'seq' overflow
# since it's a 64 bit value.
proc streamNextID {id} {
    lassign [split $id -] ms seq
    incr seq
    join [list $ms $seq] -
}

# Generate a random stream entry ID with the ms part between min and max
# and a low sequence number (0 - 999 range), in order to stress test
# XRANGE against a Tcl implementation implementing the same concept
# with Tcl-only code in a linear array.
proc streamRandomID {min_id max_id} {
    lassign [split $min_id -] min_ms min_seq
    lassign [split $max_id -] max_ms max_seq
    set delta [expr {$max_ms-$min_ms+1}]
    set ms [expr {$min_ms+[randomInt $delta]}]
    set seq [randomInt 1000]
    return $ms-$seq
}

# Tcl-side implementation of XRANGE to perform fuzz testing in the Redis
# XRANGE implementation.
proc streamSimulateXRANGE {items start end} {
    set res {}
    foreach i $items  {
        set this_id [lindex $i 0]
        if {[streamCompareID $this_id $start] >= 0} {
            if {[streamCompareID $this_id $end] <= 0} {
                lappend res $i
            }
        }
    }
    return $res
}

set content {} ;# Will be populated with Tcl side copy of the stream content.

start_server {
    tags {"stream"}
} {
    test "XADD wrong number of args" {
        assert_error {*wrong number of arguments for 'xadd' command} {r XADD mystream}
        assert_error {*wrong number of arguments for 'xadd' command} {r XADD mystream *}
        assert_error {*wrong number of arguments for 'xadd' command} {r XADD mystream * field}
    }

    test {XADD can add entries into a stream that XRANGE can fetch} {
        r XADD mystream * item 1 value a
        r XADD mystream * item 2 value b
        assert_equal 2 [r XLEN mystream]
        set items [r XRANGE mystream - +]
        assert_equal [lindex $items 0 1] {item 1 value a}
        assert_equal [lindex $items 1 1] {item 2 value b}
    }

    test {XADD IDs are incremental} {
        set id1 [r XADD mystream * item 1 value a]
        set id2 [r XADD mystream * item 2 value b]
        set id3 [r XADD mystream * item 3 value c]
        assert {[streamCompareID $id1 $id2] == -1}
        assert {[streamCompareID $id2 $id3] == -1}
    }

    test {XADD IDs are incremental when ms is the same as well} {
        r multi
        r XADD mystream * item 1 value a
        r XADD mystream * item 2 value b
        r XADD mystream * item 3 value c
        lassign [r exec] id1 id2 id3
        assert {[streamCompareID $id1 $id2] == -1}
        assert {[streamCompareID $id2 $id3] == -1}
    }

    test {XADD IDs correctly report an error when overflowing} {
        r DEL mystream
        r xadd mystream 18446744073709551615-18446744073709551615 a b
        assert_error ERR* {r xadd mystream * c d}
    }

    test {XADD auto-generated sequence is incremented for last ID} {
        r DEL mystream
        set id1 [r XADD mystream 123-456 item 1 value a]
        set id2 [r XADD mystream 123-* item 2 value b]
        lassign [split $id2 -] _ seq
        assert {$seq == 457}
        assert {[streamCompareID $id1 $id2] == -1}
    }

    test {XADD auto-generated sequence is zero for future timestamp ID} {
        r DEL mystream
        set id1 [r XADD mystream 123-456 item 1 value a]
        set id2 [r XADD mystream 789-* item 2 value b]
        lassign [split $id2 -] _ seq
        assert {$seq == 0}
        assert {[streamCompareID $id1 $id2] == -1}
    }

    test {XADD auto-generated sequence can't be smaller than last ID} {
        r DEL mystream
        r XADD mystream 123-456 item 1 value a
        assert_error ERR* {r XADD mystream 42-* item 2 value b}
    }

    test {XADD auto-generated sequence can't overflow} {
        r DEL mystream
        r xadd mystream 1-18446744073709551615 a b
        assert_error ERR* {r xadd mystream 1-* c d}
    }

    test {XADD 0-* should succeed} {
        r DEL mystream
        set id [r xadd mystream 0-* a b]
        lassign [split $id -] _ seq
        assert {$seq == 1}
    }

    test {XADD with MAXLEN option} {
        r DEL mystream
        for {set j 0} {$j < 1000} {incr j} {
            if {rand() < 0.9} {
                r XADD mystream MAXLEN 5 * xitem $j
            } else {
                r XADD mystream MAXLEN 5 * yitem $j
            }
        }
        assert {[r xlen mystream] == 5}
        set res [r xrange mystream - +]
        set expected 995
        foreach r $res {
            assert {[lindex $r 1 1] == $expected}
            incr expected
        }
    }

    test {XADD with MAXLEN option and the '=' argument} {
        r DEL mystream
        for {set j 0} {$j < 1000} {incr j} {
            if {rand() < 0.9} {
                r XADD mystream MAXLEN = 5 * xitem $j
            } else {
                r XADD mystream MAXLEN = 5 * yitem $j
            }
        }
        assert {[r XLEN mystream] == 5}
    }

    test {XADD with MAXLEN option and the '~' argument} {
        r DEL mystream
        r config set stream-node-max-entries 100
        for {set j 0} {$j < 1000} {incr j} {
            if {rand() < 0.9} {
                r XADD mystream MAXLEN ~ 555 * xitem $j
            } else {
                r XADD mystream MAXLEN ~ 555 * yitem $j
            }
        }
        assert {[r XLEN mystream] == 600}
    }

    test {XADD with NOMKSTREAM option} {
        r DEL mystream
        assert_equal "" [r XADD mystream NOMKSTREAM * item 1 value a]
        assert_equal 0 [r EXISTS mystream]
        r XADD mystream * item 1 value a
        r XADD mystream NOMKSTREAM * item 2 value b
        assert_equal 2 [r XLEN mystream]
        set items [r XRANGE mystream - +]
        assert_equal [lindex $items 0 1] {item 1 value a}
        assert_equal [lindex $items 1 1] {item 2 value b}
    }

    test {XADD with MINID option} {
        r DEL mystream
        for {set j 1} {$j < 1001} {incr j} {
            set minid 1000
            if {$j >= 5} {
                set minid [expr {$j-5}]
            }
            if {rand() < 0.9} {
                r XADD mystream MINID $minid $j xitem $j
            } else {
                r XADD mystream MINID $minid $j yitem $j
            }
        }
        assert {[r xlen mystream] == 6}
        set res [r xrange mystream - +]
        set expected 995
        foreach r $res {
            assert {[lindex $r 1 1] == $expected}
            incr expected
        }
    }

    test {XTRIM with MINID option} {
        r DEL mystream
        r XADD mystream 1-0 f v
        r XADD mystream 2-0 f v
        r XADD mystream 3-0 f v
        r XADD mystream 4-0 f v
        r XADD mystream 5-0 f v
        r XTRIM mystream MINID = 3-0
        assert_equal [r XRANGE mystream - +] {{3-0 {f v}} {4-0 {f v}} {5-0 {f v}}}
    }

    test {XTRIM with MINID option, big delta from master record} {
        r DEL mystream
        r XADD mystream 1-0 f v
        r XADD mystream 1641544570597-0 f v
        r XADD mystream 1641544570597-1 f v
        r XTRIM mystream MINID 1641544570597-0
        assert_equal [r XRANGE mystream - +] {{1641544570597-0 {f v}} {1641544570597-1 {f v}}}
    }

    proc insert_into_stream_key {key {count 10000}} {
        r multi
        for {set j 0} {$j < $count} {incr j} {
            # From time to time insert a field with a different set
            # of fields in order to stress the stream compression code.
            if {rand() < 0.9} {
                r XADD $key * item $j
            } else {
                r XADD $key * item $j otherfield foo
            }
        }
        r exec
    }

    test {XADD mass insertion and XLEN} {
        r DEL mystream
        insert_into_stream_key mystream

        set items [r XRANGE mystream - +]
        for {set j 0} {$j < 10000} {incr j} {
            assert {[lrange [lindex $items $j 1] 0 1] eq [list item $j]}
        }
        assert {[r xlen mystream] == $j}
    }

    test {XADD with ID 0-0} {
        r DEL otherstream
        catch {r XADD otherstream 0-0 k v} err
        assert {[r EXISTS otherstream] == 0}
    }

    test {XADD with LIMIT delete entries no more than limit} {
        r del yourstream
        for {set j 0} {$j < 3} {incr j} {
            r XADD yourstream * xitem v
        }
        r XADD yourstream MAXLEN ~ 0 limit 1 * xitem v
        assert {[r XLEN yourstream] == 4}
    }

    test {XRANGE COUNT works as expected} {
        assert {[llength [r xrange mystream - + COUNT 10]] == 10}
    }

    test {XREVRANGE COUNT works as expected} {
        assert {[llength [r xrevrange mystream + - COUNT 10]] == 10}
    }

    test {XRANGE can be used to iterate the whole stream} {
        set last_id "-"
        set j 0
        while 1 {
            set elements [r xrange mystream $last_id + COUNT 100]
            if {[llength $elements] == 0} break
            foreach e $elements {
                assert {[lrange [lindex $e 1] 0 1] eq [list item $j]}
                incr j;
            }
            set last_id [streamNextID [lindex $elements end 0]]
        }
        assert {$j == 10000}
    }

    test {XREVRANGE returns the reverse of XRANGE} {
        assert {[r xrange mystream - +] == [lreverse [r xrevrange mystream + -]]}
    }

    test {XRANGE exclusive ranges} {
        set ids {0-1 0-18446744073709551615 1-0 42-0 42-42
                 18446744073709551615-18446744073709551614
                 18446744073709551615-18446744073709551615}
        set total [llength $ids]
        r multi
        r DEL vipstream
        foreach id $ids {
            r XADD vipstream $id foo bar
        }
        r exec
        assert {[llength [r xrange vipstream - +]] == $total}
        assert {[llength [r xrange vipstream ([lindex $ids 0] +]] == $total-1}
        assert {[llength [r xrange vipstream - ([lindex $ids $total-1]]] == $total-1}
        assert {[llength [r xrange vipstream (0-1 (1-0]] == 1}
        assert {[llength [r xrange vipstream (1-0 (42-42]] == 1}
        catch {r xrange vipstream (- +} e
        assert_match {ERR*} $e
        catch {r xrange vipstream - (+} e
        assert_match {ERR*} $e
        catch {r xrange vipstream (18446744073709551615-18446744073709551615 +} e
        assert_match {ERR*} $e
        catch {r xrange vipstream - (0-0} e
        assert_match {ERR*} $e
    }

    test {XREAD with non empty stream} {
        set res [r XREAD COUNT 1 STREAMS mystream 0-0]
        assert {[lrange [lindex $res 0 1 0 1] 0 1] eq {item 0}}
    }

    test {Non blocking XREAD with empty streams} {
        set res [r XREAD STREAMS s1{t} s2{t} 0-0 0-0]
        assert {$res eq {}}
    }


    test "XREAD: XADD + DEL should not awake client" {
        set rd [redis_deferring_client]
        r del s1
        $rd XREAD BLOCK 20000 STREAMS s1 $
        wait_for_blocked_clients_count 1
        r multi
        r XADD s1 * old abcd1234
        r DEL s1
        r exec
        r XADD s1 * new abcd1234
        set res [$rd read]
        assert {[lindex $res 0 0] eq {s1}}
        assert {[lindex $res 0 1 0 1] eq {new abcd1234}}
        $rd close
    }

    test "XREAD: XADD + DEL + LPUSH should not awake client" {
        set rd [redis_deferring_client]
        r del s1
        $rd XREAD BLOCK 20000 STREAMS s1 $
        wait_for_blocked_clients_count 1
        r multi
        r XADD s1 * old abcd1234
        r DEL s1
        r LPUSH s1 foo bar
        r exec
        r DEL s1
        r XADD s1 * new abcd1234
        set res [$rd read]
        assert {[lindex $res 0 0] eq {s1}}
        assert {[lindex $res 0 1 0 1] eq {new abcd1234}}
        $rd close
    }

    test {XREAD with same stream name multiple times should work} {
        r XADD s2 * old abcd1234
        set rd [redis_deferring_client]
        $rd XREAD BLOCK 20000 STREAMS s2 s2 s2 $ $ $
        wait_for_blocked_clients_count 1
        r XADD s2 * new abcd1234
        set res [$rd read]
        assert {[lindex $res 0 0] eq {s2}}
        assert {[lindex $res 0 1 0 1] eq {new abcd1234}}
        $rd close
    }

    test {XREAD + multiple XADD inside transaction} {
        r XADD s2 * old abcd1234
        set rd [redis_deferring_client]
        $rd XREAD BLOCK 20000 STREAMS s2 s2 s2 $ $ $
        wait_for_blocked_clients_count 1
        r MULTI
        r XADD s2 * field one
        r XADD s2 * field two
        r XADD s2 * field three
        r EXEC
        set res [$rd read]
        assert {[lindex $res 0 0] eq {s2}}
        assert {[lindex $res 0 1 0 1] eq {field one}}
        assert {[lindex $res 0 1 1 1] eq {field two}}
        $rd close
    }

    test {XDEL basic test} {
        r del somestream
        r xadd somestream * foo value0
        set id [r xadd somestream * foo value1]
        r xadd somestream * foo value2
        r xdel somestream $id
        assert {[r xlen somestream] == 2}
        set result [r xrange somestream - +]
        assert {[lindex $result 0 1 1] eq {value0}}
        assert {[lindex $result 1 1 1] eq {value2}}
    }

    test {XREVRANGE regression test for issue #5006} {
        # Add non compressed entries
        r xadd teststream 1234567891230 key1 value1
        r xadd teststream 1234567891240 key2 value2
        r xadd teststream 1234567891250 key3 value3

        # Add SAMEFIELD compressed entries
        r xadd teststream2 1234567891230 key1 value1
        r xadd teststream2 1234567891240 key1 value2
        r xadd teststream2 1234567891250 key1 value3

        assert_equal [r xrevrange teststream 1234567891245 -] {{1234567891240-0 {key2 value2}} {1234567891230-0 {key1 value1}}}

        assert_equal [r xrevrange teststream2 1234567891245 -] {{1234567891240-0 {key1 value2}} {1234567891230-0 {key1 value1}}}
    }

    test {XREAD streamID edge (no-blocking)} {
        r del x
        r XADD x 1-1 f v
        r XADD x 1-18446744073709551615 f v
        r XADD x 2-1 f v
        set res [r XREAD BLOCK 0 STREAMS x 1-18446744073709551615]
        assert {[lindex $res 0 1 0] == {2-1 {f v}}}
    }

    test {XREAD streamID edge (blocking)} {
        r del x
        set rd [redis_deferring_client]
        $rd XREAD BLOCK 0 STREAMS x 1-18446744073709551615
        wait_for_blocked_clients_count 1
        r XADD x 1-1 f v
        r XADD x 1-18446744073709551615 f v
        r XADD x 2-1 f v
        set res [$rd read]
        assert {[lindex $res 0 1 0] == {2-1 {f v}}}
        $rd close
    }

    test {XADD streamID edge} {
        r del x
        r XADD x 2577343934890-18446744073709551615 f v ;# we need the timestamp to be in the future
        r XADD x * f2 v2
        assert_equal [r XRANGE x - +] {{2577343934890-18446744073709551615 {f v}} {2577343934891-0 {f2 v2}}}
    }

    test {XTRIM with MAXLEN option basic test} {
        r DEL mystream
        for {set j 0} {$j < 1000} {incr j} {
            if {rand() < 0.9} {
                r XADD mystream * xitem $j
            } else {
                r XADD mystream * yitem $j
            }
        }
        r XTRIM mystream MAXLEN 666
        assert {[r XLEN mystream] == 666}
        r XTRIM mystream MAXLEN = 555
        assert {[r XLEN mystream] == 555}
        r XTRIM mystream MAXLEN ~ 444
        assert {[r XLEN mystream] == 500}
        r XTRIM mystream MAXLEN ~ 400
        assert {[r XLEN mystream] == 400}
    }

    test {XADD with LIMIT consecutive calls} {
        r del mystream
        r config set stream-node-max-entries 10
        for {set j 0} {$j < 100} {incr j} {
            r XADD mystream * xitem v
        }
        r XADD mystream MAXLEN ~ 55 LIMIT 30 * xitem v
        assert {[r xlen mystream] == 71}
        r XADD mystream MAXLEN ~ 55 LIMIT 30 * xitem v
        assert {[r xlen mystream] == 62}
        r config set stream-node-max-entries 100
    }

    test {XTRIM with ~ is limited} {
        r del mystream
        r config set stream-node-max-entries 1
        for {set j 0} {$j < 102} {incr j} {
            r XADD mystream * xitem v
        }
        r XTRIM mystream MAXLEN ~ 1
        assert {[r xlen mystream] == 2}
        r config set stream-node-max-entries 100
    }

    test {XTRIM without ~ is not limited} {
        r del mystream
        r config set stream-node-max-entries 1
        for {set j 0} {$j < 102} {incr j} {
            r XADD mystream * xitem v
        }
        r XTRIM mystream MAXLEN 1
        assert {[r xlen mystream] == 1}
        r config set stream-node-max-entries 100
    }

    test {XTRIM without ~ and with LIMIT} {
        r del mystream
        r config set stream-node-max-entries 1
        for {set j 0} {$j < 102} {incr j} {
            r XADD mystream * xitem v
        }
        assert_error ERR* {r XTRIM mystream MAXLEN 1 LIMIT 30}
    }

    test {XTRIM with LIMIT delete entries no more than limit} {
        r del mystream
        r config set stream-node-max-entries 2
        for {set j 0} {$j < 3} {incr j} {
            r XADD mystream * xitem v
        }
        assert {[r XTRIM mystream MAXLEN ~ 0 LIMIT 1] == 0}
        assert {[r XTRIM mystream MAXLEN ~ 0 LIMIT 2] == 2}
    }
}

start_server {tags {"stream needs:debug"} overrides {}} {
    test {XADD with MAXLEN > xlen can propagate correctly} {
        for {set j 0} {$j < 100} {incr j} {
            r XADD mystream * xitem v
        }
        r XADD mystream MAXLEN 200 * xitem v
        incr j
        assert {[r xlen mystream] == $j}
        r debug loadaof
        r XADD mystream * xitem v
        incr j
        assert {[r xlen mystream] == $j}
    }
}

start_server {tags {"stream needs:debug"} overrides {}} {
    test {XADD with MINID > lastid can propagate correctly} {
        for {set j 0} {$j < 100} {incr j} {
            set id [expr {$j+1}]
            r XADD mystream $id xitem v
        }
        r XADD mystream MINID 1 * xitem v
        incr j
        assert {[r xlen mystream] == $j}
        r debug loadaof
        r XADD mystream * xitem v
        incr j
        assert {[r xlen mystream] == $j}
    }
}

start_server {tags {"stream needs:debug"} overrides {}} {
    test {XADD with ~ MAXLEN can propagate correctly} {
        for {set j 0} {$j < 100} {incr j} {
            r XADD mystream * xitem v
        }
        r XADD mystream MAXLEN ~ $j * xitem v
        incr j
        assert {[r xlen mystream] == $j}
        r config set stream-node-max-entries 1
        r debug loadaof
        r XADD mystream * xitem v
        incr j
        assert {[r xlen mystream] == $j}
    }
}


start_server {tags {"stream needs:debug"} overrides {}} {
    test {XTRIM with ~ MAXLEN can propagate correctly} {
        for {set j 0} {$j < 100} {incr j} {
            r XADD mystream * xitem v
        }
        r XTRIM mystream MAXLEN ~ 85
        assert {[r xlen mystream] == 90}
        r config set stream-node-max-entries 1
        r debug loadaof
        r XADD mystream * xitem v
        incr j
        assert {[r xlen mystream] == 91}
    }
}

start_server {tags {"stream xsetid"}} {
    test {XADD can CREATE an empty stream} {
        r XADD mystream MAXLEN 0 * a b
        assert {[dict get [r xinfo stream mystream] length] == 0}
    }

    test {XSETID can set a specific ID} {
        r XSETID mystream "200-0"
        set reply [r XINFO stream mystream]
        assert_equal [dict get $reply last-generated-id] "200-0"
        assert_equal [dict get $reply entries-added] 1
    }

    test {XSETID cannot SETID with smaller ID} {
        r XADD mystream * a b
        catch {r XSETID mystream "1-1"} err
        r XADD mystream MAXLEN 0 * a b
        set err
    } {ERR*smaller*}

    test {XSETID cannot SETID on non-existent key} {
        catch {r XSETID stream 1-1} err
        set _ $err
    } {ERR no such key}

    test {XSETID cannot run with an offset but without a maximal tombstone} {
        catch {r XSETID stream 1-1 0} err
        set _ $err
    } {ERR syntax error}

    test {XSETID cannot run with a maximal tombstone but without an offset} {
        catch {r XSETID stream 1-1 0-0} err
        set _ $err
    } {ERR syntax error}

    test {XSETID errors on negstive offset} {
        catch {r XSETID stream 1-1 ENTRIESADDED -1 MAXDELETEDID 0-0} err
        set _ $err
    } {ERR*must be positive}

    test {XSETID cannot set the maximal tombstone with larger ID} {
        r DEL x
        r XADD x 1-0 a b
        
        catch {r XSETID x "1-0" ENTRIESADDED 1 MAXDELETEDID "2-0" } err
        r XADD mystream MAXLEN 0 * a b
        set err
    } {ERR*smaller*}

    test {XSETID cannot set the offset to less than the length} {
        r DEL x
        r XADD x 1-0 a b
        
        catch {r XSETID x "1-0" ENTRIESADDED 0 MAXDELETEDID "0-0" } err
        r XADD mystream MAXLEN 0 * a b
        set err
    } {ERR*smaller*}
}

start_server {tags {"stream offset"}} {
    test {XADD advances the entries-added counter and sets the recorded-first-entry-id} {
        r DEL x
        r XADD x 1-0 data a

        set reply [r XINFO STREAM x FULL]
        assert_equal [dict get $reply entries-added] 1
        assert_equal [dict get $reply recorded-first-entry-id] "1-0"

        r XADD x 2-0 data a
        set reply [r XINFO STREAM x FULL]
        assert_equal [dict get $reply entries-added] 2
        assert_equal [dict get $reply recorded-first-entry-id] "1-0"
    }

    test {XDEL/TRIM are reflected by recorded first entry} {
        r DEL x
        r XADD x 1-0 data a
        r XADD x 2-0 data a
        r XADD x 3-0 data a
        r XADD x 4-0 data a
        r XADD x 5-0 data a

        set reply [r XINFO STREAM x FULL]
        assert_equal [dict get $reply entries-added] 5
        assert_equal [dict get $reply recorded-first-entry-id] "1-0"

        r XDEL x 2-0
        set reply [r XINFO STREAM x FULL]
        assert_equal [dict get $reply recorded-first-entry-id] "1-0"

        r XDEL x 1-0
        set reply [r XINFO STREAM x FULL]
        assert_equal [dict get $reply recorded-first-entry-id] "3-0"

        r XTRIM x MAXLEN = 2
        set reply [r XINFO STREAM x FULL]
        assert_equal [dict get $reply recorded-first-entry-id] "4-0"
    }

    test {Maxmimum XDEL ID behaves correctly} {
        r DEL x
        r XADD x 1-0 data a
        r XADD x 2-0 data b
        r XADD x 3-0 data c

        set reply [r XINFO STREAM x FULL]
        assert_equal [dict get $reply max-deleted-entry-id] "0-0"

        r XDEL x 2-0
        set reply [r XINFO STREAM x FULL]
        assert_equal [dict get $reply max-deleted-entry-id] "2-0"

        r XDEL x 1-0
        set reply [r XINFO STREAM x FULL]
        assert_equal [dict get $reply max-deleted-entry-id] "2-0"
    }
}

start_server {tags {"stream needs:debug"} overrides {}} {
    test {Empty stream can be rewrite into AOF correctly} {
        r XADD mystream MAXLEN 0 * a b
        assert {[dict get [r xinfo stream mystream] length] == 0}
        r bgrewriteaof
        waitForBgrewriteaof r
        r debug loadaof
        assert {[dict get [r xinfo stream mystream] length] == 0}
    }

    test {Stream can be rewrite into AOF correctly after XDEL lastid} {
        r XSETID mystream 0-0
        r XADD mystream 1-1 a b
        r XADD mystream 2-2 a b
        assert {[dict get [r xinfo stream mystream] length] == 2}
        r XDEL mystream 2-2
        r bgrewriteaof
        waitForBgrewriteaof r
        r debug loadaof
        assert {[dict get [r xinfo stream mystream] length] == 1}
        assert_equal [dict get [r xinfo stream mystream] last-generated-id] "2-2"
    }
}

start_server {tags {"stream"}} {
    test {XGROUP HELP should not have unexpected options} {
        catch {r XGROUP help xxx} e
        assert_match "*wrong number of arguments for 'xgroup|help' command" $e
    }

    test {XINFO HELP should not have unexpected options} {
        catch {r XINFO help xxx} e
        assert_match "*wrong number of arguments for 'xinfo|help' command" $e
    }
}
