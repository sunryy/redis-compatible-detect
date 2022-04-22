start_server {
    tags {"set"}
    overrides {
    }
} {
    proc create_set {key entries} {
        r del $key
        foreach entry $entries { r sadd $key $entry }
    }

    test {SADD, SCARD, SISMEMBER, SMISMEMBER, SMEMBERS basics - regular set} {
        create_set myset {foo}
        assert_encoding hashtable myset
        assert_equal 1 [r sadd myset bar]
        assert_equal 0 [r sadd myset bar]
        assert_equal 2 [r scard myset]
        assert_equal 1 [r sismember myset foo]
        assert_equal 1 [r sismember myset bar]
        assert_equal 0 [r sismember myset bla]
        assert_equal {1} [r smismember myset foo]
        assert_equal {1 1} [r smismember myset foo bar]
        assert_equal {1 0} [r smismember myset foo bla]
        assert_equal {0 1} [r smismember myset bla foo]
        assert_equal {0} [r smismember myset bla]
        assert_equal {bar foo} [lsort [r smembers myset]]
    }

    test {SADD, SCARD, SISMEMBER, SMISMEMBER, SMEMBERS basics - intset} {
        create_set myset {17}
        assert_encoding intset myset
        assert_equal 1 [r sadd myset 16]
        assert_equal 0 [r sadd myset 16]
        assert_equal 2 [r scard myset]
        assert_equal 1 [r sismember myset 16]
        assert_equal 1 [r sismember myset 17]
        assert_equal 0 [r sismember myset 18]
        assert_equal {1} [r smismember myset 16]
        assert_equal {1 1} [r smismember myset 16 17]
        assert_equal {1 0} [r smismember myset 16 18]
        assert_equal {0 1} [r smismember myset 18 16]
        assert_equal {0} [r smismember myset 18]
        assert_equal {16 17} [lsort [r smembers myset]]
    }

    test {SMISMEMBER against non set} {
        r lpush mylist foo
        assert_error WRONGTYPE* {r smismember mylist bar}
    }

    test {SMISMEMBER non existing key} {
        assert_equal {0} [r smismember myset1 foo]
        assert_equal {0 0} [r smismember myset1 foo bar]
    }

    test {SMISMEMBER requires one or more members} {
        r del zmscoretest
        r zadd zmscoretest 10 x
        r zadd zmscoretest 20 y
        
        catch {r smismember zmscoretest} e
        assert_match {*ERR*wrong*number*arg*} $e
    }

    test {SADD against non set} {
        r lpush mylist foo
        assert_error WRONGTYPE* {r sadd mylist bar}
    }

    test "SADD a non-integer against an intset" {
        create_set myset {1 2 3}
        assert_encoding intset myset
        assert_equal 1 [r sadd myset a]
        assert_encoding hashtable myset
    }

    test "SADD an integer larger than 64 bits" {
        create_set myset {213244124402402314402033402}
        assert_encoding hashtable myset
        assert_equal 1 [r sismember myset 213244124402402314402033402]
        assert_equal {1} [r smismember myset 213244124402402314402033402]
    }

    test "SADD overflows the maximum allowed integers in an intset" {
        r del myset
        for {set i 0} {$i < 512} {incr i} { r sadd myset $i }
        assert_encoding intset myset
        assert_equal 1 [r sadd myset 512]
        assert_encoding hashtable myset
    }

    test {Variadic SADD} {
        r del myset
        assert_equal 3 [r sadd myset a b c]
        assert_equal 2 [r sadd myset A a b c B]
        assert_equal [lsort {A a b c B}] [lsort [r smembers myset]]
    }

    test "Set encoding after DEBUG RELOAD" {
        r del myintset
        r del myhashset
        r del mylargeintset
        for {set i 0} {$i <  100} {incr i} { r sadd myintset $i }
        for {set i 0} {$i < 1280} {incr i} { r sadd mylargeintset $i }
        for {set i 0} {$i <  256} {incr i} { r sadd myhashset [format "i%03d" $i] }
        assert_encoding intset myintset
        assert_encoding hashtable mylargeintset
        assert_encoding hashtable myhashset

        r debug reload
        assert_encoding intset myintset
        assert_encoding hashtable mylargeintset
        assert_encoding hashtable myhashset
    } {} {needs:debug}

    test {SREM basics - regular set} {
        create_set myset {foo bar ciao}
        assert_encoding hashtable myset
        assert_equal 0 [r srem myset qux]
        assert_equal 1 [r srem myset foo]
        assert_equal {bar ciao} [lsort [r smembers myset]]
    }

    test {SREM basics - intset} {
        create_set myset {3 4 5}
        assert_encoding intset myset
        assert_equal 0 [r srem myset 6]
        assert_equal 1 [r srem myset 4]
        assert_equal {3 5} [lsort [r smembers myset]]
    }

    test {SREM with multiple arguments} {
        r del myset
        r sadd myset a b c d
        assert_equal 0 [r srem myset k k k]
        assert_equal 2 [r srem myset b d x y]
        lsort [r smembers myset]
    } {a c}

    test {SREM variadic version with more args needed to destroy the key} {
        r del myset
        r sadd myset 1 2 3
        r srem myset 1 2 3 4 5 6 7 8
    } {3}

    test "SINTERCARD with illegal arguments" {
        assert_error "ERR wrong number of arguments for 'sintercard' command" {r sintercard}
        assert_error "ERR wrong number of arguments for 'sintercard' command" {r sintercard 1}

        assert_error "ERR numkeys*" {r sintercard 0 myset{t}}
        assert_error "ERR numkeys*" {r sintercard a myset{t}}

        assert_error "ERR Number of keys*" {r sintercard 2 myset{t}}
        assert_error "ERR Number of keys*" {r sintercard 3 myset{t} myset2{t}}

        assert_error "ERR syntax error*" {r sintercard 1 myset{t} myset2{t}}
        assert_error "ERR syntax error*" {r sintercard 1 myset{t} bar_arg}
        assert_error "ERR syntax error*" {r sintercard 1 myset{t} LIMIT}

        assert_error "ERR LIMIT*" {r sintercard 1 myset{t} LIMIT -1}
        assert_error "ERR LIMIT*" {r sintercard 1 myset{t} LIMIT a}
    }

    test "SINTERCARD against non-set should throw error" {
        r del set{t}
        r sadd set{t} a b c
        r set key1{t} x

        assert_error "WRONGTYPE*" {r sintercard 1 key1{t}}
        assert_error "WRONGTYPE*" {r sintercard 2 set{t} key1{t}}
        assert_error "WRONGTYPE*" {r sintercard 2 key1{t} noset{t}}
    }

    test "SINTERCARD against non-existing key" {
        assert_equal 0 [r sintercard 1 non-existing-key]
        assert_equal 0 [r sintercard 1 non-existing-key limit 0]
        assert_equal 0 [r sintercard 1 non-existing-key limit 10]
    }

    foreach {type} {hashtable intset} {
        for {set i 1} {$i <= 5} {incr i} {
            r del [format "set%d{t}" $i]
        }
        for {set i 0} {$i < 200} {incr i} {
            r sadd set1{t} $i
            r sadd set2{t} [expr $i+195]
        }
        foreach i {199 195 1000 2000} {
            r sadd set3{t} $i
        }
        for {set i 5} {$i < 200} {incr i} {
            r sadd set4{t} $i
        }
        r sadd set5{t} 0

        # To make sure the sets are encoded as the type we are testing -- also
        # when the VM is enabled and the values may be swapped in and out
        # while the tests are running -- an extra element is added to every
        # set that determines its encoding.
        set large 200
        if {$type eq "hashtable"} {
            set large foo
        }

        for {set i 1} {$i <= 5} {incr i} {
            r sadd [format "set%d{t}" $i] $large
        }

        test "Generated sets must be encoded as $type" {
            for {set i 1} {$i <= 5} {incr i} {
                assert_encoding $type [format "set%d{t}" $i]
            }
        }

        test "SINTER with two sets - $type" {
            assert_equal [list 195 196 197 198 199 $large] [lsort [r sinter set1{t} set2{t}]]
        }

        test "SINTERCARD with two sets - $type" {
            assert_equal 6 [r sintercard 2 set1{t} set2{t}]
            assert_equal 6 [r sintercard 2 set1{t} set2{t} limit 0]
            assert_equal 3 [r sintercard 2 set1{t} set2{t} limit 3]
            assert_equal 6 [r sintercard 2 set1{t} set2{t} limit 10]
        }

        test "SINTERSTORE with two sets - $type" {
            r sinterstore setres{t} set1{t} set2{t}
            assert_encoding $type setres{t}
            assert_equal [list 195 196 197 198 199 $large] [lsort [r smembers setres{t}]]
        }

        test "SINTERSTORE with two sets, after a DEBUG RELOAD - $type" {
            r debug reload
            r sinterstore setres{t} set1{t} set2{t}
            assert_encoding $type setres{t}
            assert_equal [list 195 196 197 198 199 $large] [lsort [r smembers setres{t}]]
        } {} {needs:debug}

        test "SUNION with two sets - $type" {
            set expected [lsort -uniq "[r smembers set1{t}] [r smembers set2{t}]"]
            assert_equal $expected [lsort [r sunion set1{t} set2{t}]]
        }

        test "SUNIONSTORE with two sets - $type" {
            r sunionstore setres{t} set1{t} set2{t}
            assert_encoding $type setres{t}
            set expected [lsort -uniq "[r smembers set1{t}] [r smembers set2{t}]"]
            assert_equal $expected [lsort [r smembers setres{t}]]
        }

        test "SINTER against three sets - $type" {
            assert_equal [list 195 199 $large] [lsort [r sinter set1{t} set2{t} set3{t}]]
        }

        test "SINTERCARD against three sets - $type" {
            assert_equal 3 [r sintercard 3 set1{t} set2{t} set3{t}]
            assert_equal 3 [r sintercard 3 set1{t} set2{t} set3{t} limit 0]
            assert_equal 2 [r sintercard 3 set1{t} set2{t} set3{t} limit 2]
            assert_equal 3 [r sintercard 3 set1{t} set2{t} set3{t} limit 10]
        }

        test "SINTERSTORE with three sets - $type" {
            r sinterstore setres{t} set1{t} set2{t} set3{t}
            assert_equal [list 195 199 $large] [lsort [r smembers setres{t}]]
        }

        test "SUNION with non existing keys - $type" {
            set expected [lsort -uniq "[r smembers set1{t}] [r smembers set2{t}]"]
            assert_equal $expected [lsort [r sunion nokey1{t} set1{t} set2{t} nokey2{t}]]
        }

        test "SDIFF with two sets - $type" {
            assert_equal {0 1 2 3 4} [lsort [r sdiff set1{t} set4{t}]]
        }

        test "SDIFF with three sets - $type" {
            assert_equal {1 2 3 4} [lsort [r sdiff set1{t} set4{t} set5{t}]]
        }

        test "SDIFFSTORE with three sets - $type" {
            r sdiffstore setres{t} set1{t} set4{t} set5{t}
            # When we start with intsets, we should always end with intsets.
            if {$type eq {intset}} {
                assert_encoding intset setres{t}
            }
            assert_equal {1 2 3 4} [lsort [r smembers setres{t}]]
        }
    }

    test "SDIFF with first set empty" {
        r del set1{t} set2{t} set3{t}
        r sadd set2{t} 1 2 3 4
        r sadd set3{t} a b c d
        r sdiff set1{t} set2{t} set3{t}
    } {}

    test "SDIFF with same set two times" {
        r del set1
        r sadd set1 a b c 1 2 3 4 5 6
        r sdiff set1 set1
    } {}

    test "SDIFF against non-set should throw error" {
        # with an empty set
        r set key1{t} x
        assert_error "WRONGTYPE*" {r sdiff key1{t} noset{t}}
        # different order
        assert_error "WRONGTYPE*" {r sdiff noset{t} key1{t}}

        # with a legal set
        r del set1{t}
        r sadd set1{t} a b c
        assert_error "WRONGTYPE*" {r sdiff key1{t} set1{t}}
        # different order
        assert_error "WRONGTYPE*" {r sdiff set1{t} key1{t}}
    }

    test "SDIFF should handle non existing key as empty" {
        r del set1{t} set2{t} set3{t}

        r sadd set1{t} a b c
        r sadd set2{t} b c d
        assert_equal {a} [lsort [r sdiff set1{t} set2{t} set3{t}]]
        assert_equal {} [lsort [r sdiff set3{t} set2{t} set1{t}]]
    }

    test "SDIFFSTORE against non-set should throw error" {
        r del set1{t} set2{t} set3{t} key1{t}
        r set key1{t} x

        # with en empty dstkey
        assert_error "WRONGTYPE*" {r SDIFFSTORE set3{t} key1{t} noset{t}}
        assert_equal 0 [r exists set3{t}]
        assert_error "WRONGTYPE*" {r SDIFFSTORE set3{t} noset{t} key1{t}}
        assert_equal 0 [r exists set3{t}]

        # with a legal dstkey
        r sadd set1{t} a b c
        r sadd set2{t} b c d
        r sadd set3{t} e
        assert_error "WRONGTYPE*" {r SDIFFSTORE set3{t} key1{t} set1{t} noset{t}}
        assert_equal 1 [r exists set3{t}]
        assert_equal {e} [lsort [r smembers set3{t}]]

        assert_error "WRONGTYPE*" {r SDIFFSTORE set3{t} set1{t} key1{t} set2{t}}
        assert_equal 1 [r exists set3{t}]
        assert_equal {e} [lsort [r smembers set3{t}]]
    }

    test "SDIFFSTORE should handle non existing key as empty" {
        r del set1{t} set2{t} set3{t}

        r set setres{t} xxx
        assert_equal 0 [r sdiffstore setres{t} foo111{t} bar222{t}]
        assert_equal 0 [r exists setres{t}]

        # with a legal dstkey, should delete dstkey
        r sadd set3{t} a b c
        assert_equal 0 [r sdiffstore set3{t} set1{t} set2{t}]
        assert_equal 0 [r exists set3{t}]

        r sadd set1{t} a b c
        assert_equal 3 [r sdiffstore set3{t} set1{t} set2{t}]
        assert_equal 1 [r exists set3{t}]
        assert_equal {a b c} [lsort [r smembers set3{t}]]

        # with a legal dstkey and empty set2, should delete the dstkey
        r sadd set3{t} a b c
        assert_equal 0 [r sdiffstore set3{t} set2{t} set1{t}]
        assert_equal 0 [r exists set3{t}]
    }

    test "SINTER against non-set should throw error" {
        r set key1{t} x
        assert_error "WRONGTYPE*" {r sinter key1{t} noset{t}}
        # different order
        assert_error "WRONGTYPE*" {r sinter noset{t} key1{t}}

        r sadd set1{t} a b c
        assert_error "WRONGTYPE*" {r sinter key1{t} set1{t}}
        # different order
        assert_error "WRONGTYPE*" {r sinter set1{t} key1{t}}
    }

    test "SINTER should handle non existing key as empty" {
        r del set1{t} set2{t} set3{t}
        r sadd set1{t} a b c
        r sadd set2{t} b c d
        r sinter set1{t} set2{t} set3{t}
    } {}

    test "SINTER with same integer elements but different encoding" {
        r del set1{t} set2{t}
        r sadd set1{t} 1 2 3
        r sadd set2{t} 1 2 3 a
        r srem set2{t} a
        assert_encoding intset set1{t}
        assert_encoding hashtable set2{t}
        lsort [r sinter set1{t} set2{t}]
    } {1 2 3}

    test "SINTERSTORE against non-set should throw error" {
        r del set1{t} set2{t} set3{t} key1{t}
        r set key1{t} x

        # with en empty dstkey
        assert_error "WRONGTYPE*" {r sinterstore set3{t} key1{t} noset{t}}
        assert_equal 0 [r exists set3{t}]
        assert_error "WRONGTYPE*" {r sinterstore set3{t} noset{t} key1{t}}
        assert_equal 0 [r exists set3{t}]

        # with a legal dstkey
        r sadd set1{t} a b c
        r sadd set2{t} b c d
        r sadd set3{t} e
        assert_error "WRONGTYPE*" {r sinterstore set3{t} key1{t} set2{t} noset{t}}
        assert_equal 1 [r exists set3{t}]
        assert_equal {e} [lsort [r smembers set3{t}]]

        assert_error "WRONGTYPE*" {r sinterstore set3{t} noset{t} key1{t} set2{t}}
        assert_equal 1 [r exists set3{t}]
        assert_equal {e} [lsort [r smembers set3{t}]]
    }

    test "SINTERSTORE against non existing keys should delete dstkey" {
        r del set1{t} set2{t} set3{t}

        r set setres{t} xxx
        assert_equal 0 [r sinterstore setres{t} foo111{t} bar222{t}]
        assert_equal 0 [r exists setres{t}]

        # with a legal dstkey
        r sadd set3{t} a b c
        assert_equal 0 [r sinterstore set3{t} set1{t} set2{t}]
        assert_equal 0 [r exists set3{t}]

        r sadd set1{t} a b c
        assert_equal 0 [r sinterstore set3{t} set1{t} set2{t}]
        assert_equal 0 [r exists set3{t}]

        assert_equal 0 [r sinterstore set3{t} set2{t} set1{t}]
        assert_equal 0 [r exists set3{t}]
    }

    test "SUNION against non-set should throw error" {
        r set key1{t} x
        assert_error "WRONGTYPE*" {r sunion key1{t} noset{t}}
        # different order
        assert_error "WRONGTYPE*" {r sunion noset{t} key1{t}}

        r del set1{t}
        r sadd set1{t} a b c
        assert_error "WRONGTYPE*" {r sunion key1{t} set1{t}}
        # different order
        assert_error "WRONGTYPE*" {r sunion set1{t} key1{t}}
    }

    test "SUNION should handle non existing key as empty" {
        r del set1{t} set2{t} set3{t}

        r sadd set1{t} a b c
        r sadd set2{t} b c d
        assert_equal {a b c d} [lsort [r sunion set1{t} set2{t} set3{t}]]
    }

    test "SUNIONSTORE against non-set should throw error" {
        r del set1{t} set2{t} set3{t} key1{t}
        r set key1{t} x

        # with en empty dstkey
        assert_error "WRONGTYPE*" {r sunionstore set3{t} key1{t} noset{t}}
        assert_equal 0 [r exists set3{t}]
        assert_error "WRONGTYPE*" {r sunionstore set3{t} noset{t} key1{t}}
        assert_equal 0 [r exists set3{t}]

        # with a legal dstkey
        r sadd set1{t} a b c
        r sadd set2{t} b c d
        r sadd set3{t} e
        assert_error "WRONGTYPE*" {r sunionstore set3{t} key1{t} key2{t} noset{t}}
        assert_equal 1 [r exists set3{t}]
        assert_equal {e} [lsort [r smembers set3{t}]]

        assert_error "WRONGTYPE*" {r sunionstore set3{t} noset{t} key1{t} key2{t}}
        assert_equal 1 [r exists set3{t}]
        assert_equal {e} [lsort [r smembers set3{t}]]
    }

    test "SUNIONSTORE should handle non existing key as empty" {
        r del set1{t} set2{t} set3{t}

        r set setres{t} xxx
        assert_equal 0 [r sunionstore setres{t} foo111{t} bar222{t}]
        assert_equal 0 [r exists setres{t}]

        # set1 set2 both empty, should delete the dstkey
        r sadd set3{t} a b c
        assert_equal 0 [r sunionstore set3{t} set1{t} set2{t}]
        assert_equal 0 [r exists set3{t}]

        r sadd set1{t} a b c
        r sadd set3{t} e f
        assert_equal 3 [r sunionstore set3{t} set1{t} set2{t}]
        assert_equal 1 [r exists set3{t}]
        assert_equal {a b c} [lsort [r smembers set3{t}]]

        r sadd set3{t} d
        assert_equal 3 [r sunionstore set3{t} set2{t} set1{t}]
        assert_equal 1 [r exists set3{t}]
        assert_equal {a b c} [lsort [r smembers set3{t}]]
    }

    test "SUNIONSTORE against non existing keys should delete dstkey" {
        r set setres{t} xxx
        assert_equal 0 [r sunionstore setres{t} foo111{t} bar222{t}]
        assert_equal 0 [r exists setres{t}]
    }

    foreach {type contents} {hashtable {a b c} intset {1 2 3}} {
        test "SPOP basics - $type" {
            create_set myset $contents
            assert_encoding $type myset
            assert_equal $contents [lsort [list [r spop myset] [r spop myset] [r spop myset]]]
            assert_equal 0 [r scard myset]
        }

        test "SPOP with <count>=1 - $type" {
            create_set myset $contents
            assert_encoding $type myset
            assert_equal $contents [lsort [list [r spop myset 1] [r spop myset 1] [r spop myset 1]]]
            assert_equal 0 [r scard myset]
        }

        test "SRANDMEMBER - $type" {
            create_set myset $contents
            unset -nocomplain myset
            array set myset {}
            for {set i 0} {$i < 100} {incr i} {
                set myset([r srandmember myset]) 1
            }
            assert_equal $contents [lsort [array names myset]]
        }
    }

    # As seen in intsetRandomMembers
    test "SPOP using integers, testing Knuth's and Floyd's algorithm" {
        create_set myset {1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20}
        assert_encoding intset myset
        assert_equal 20 [r scard myset]
        r spop myset 1
        assert_equal 19 [r scard myset]
        r spop myset 2
        assert_equal 17 [r scard myset]
        r spop myset 3
        assert_equal 14 [r scard myset]
        r spop myset 10
        assert_equal 4 [r scard myset]
        r spop myset 10
        assert_equal 0 [r scard myset]
        r spop myset 1
        assert_equal 0 [r scard myset]
    } {}

    test "SPOP using integers with Knuth's algorithm" {
        r spop nonexisting_key 100
    } {}

    test "SPOP new implementation: code path #1" {
        set content {1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20}
        create_set myset $content
        set res [r spop myset 30]
        assert {[lsort $content] eq [lsort $res]}
    }

    test "SPOP new implementation: code path #2" {
        set content {1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20}
        create_set myset $content
        set res [r spop myset 2]
        assert {[llength $res] == 2}
        assert {[r scard myset] == 18}
        set union [concat [r smembers myset] $res]
        assert {[lsort $union] eq [lsort $content]}
    }

    test "SPOP new implementation: code path #3" {
        set content {1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20}
        create_set myset $content
        set res [r spop myset 18]
        assert {[llength $res] == 18}
        assert {[r scard myset] == 2}
        set union [concat [r smembers myset] $res]
        assert {[lsort $union] eq [lsort $content]}
    }

    test "SRANDMEMBER count of 0 is handled correctly" {
        r srandmember myset 0
    } {}

    test "SRANDMEMBER with <count> against non existing key" {
        r srandmember nonexisting_key 100
    } {}

    # Make sure we can distinguish between an empty array and a null response
    r readraw 1

    test "SRANDMEMBER count of 0 is handled correctly - emptyarray" {
        r srandmember myset 0
    } {*0}

    test "SRANDMEMBER with <count> against non existing key - emptyarray" {
        r srandmember nonexisting_key 100
    } {*0}

    r readraw 0


    proc setup_move {} {
        r del myset3{t} myset4{t}
        create_set myset1{t} {1 a b}
        create_set myset2{t} {2 3 4}
        assert_encoding hashtable myset1{t}
        assert_encoding intset myset2{t}
    }

    test "SMOVE basics - from regular set to intset" {
        # move a non-integer element to an intset should convert encoding
        setup_move
        assert_equal 1 [r smove myset1{t} myset2{t} a]
        assert_equal {1 b} [lsort [r smembers myset1{t}]]
        assert_equal {2 3 4 a} [lsort [r smembers myset2{t}]]
        assert_encoding hashtable myset2{t}

        # move an integer element should not convert the encoding
        setup_move
        assert_equal 1 [r smove myset1{t} myset2{t} 1]
        assert_equal {a b} [lsort [r smembers myset1{t}]]
        assert_equal {1 2 3 4} [lsort [r smembers myset2{t}]]
        assert_encoding intset myset2{t}
    }

    test "SMOVE basics - from intset to regular set" {
        setup_move
        assert_equal 1 [r smove myset2{t} myset1{t} 2]
        assert_equal {1 2 a b} [lsort [r smembers myset1{t}]]
        assert_equal {3 4} [lsort [r smembers myset2{t}]]
    }

    test "SMOVE non existing key" {
        setup_move
        assert_equal 0 [r smove myset1{t} myset2{t} foo]
        assert_equal 0 [r smove myset1{t} myset1{t} foo]
        assert_equal {1 a b} [lsort [r smembers myset1{t}]]
        assert_equal {2 3 4} [lsort [r smembers myset2{t}]]
    }

    test "SMOVE non existing src set" {
        setup_move
        assert_equal 0 [r smove noset{t} myset2{t} foo]
        assert_equal {2 3 4} [lsort [r smembers myset2{t}]]
    }

    test "SMOVE from regular set to non existing destination set" {
        setup_move
        assert_equal 1 [r smove myset1{t} myset3{t} a]
        assert_equal {1 b} [lsort [r smembers myset1{t}]]
        assert_equal {a} [lsort [r smembers myset3{t}]]
        assert_encoding hashtable myset3{t}
    }

    test "SMOVE from intset to non existing destination set" {
        setup_move
        assert_equal 1 [r smove myset2{t} myset3{t} 2]
        assert_equal {3 4} [lsort [r smembers myset2{t}]]
        assert_equal {2} [lsort [r smembers myset3{t}]]
        assert_encoding intset myset3{t}
    }

    test "SMOVE wrong src key type" {
        r set x{t} 10
        assert_error "WRONGTYPE*" {r smove x{t} myset2{t} foo}
    }

    test "SMOVE wrong dst key type" {
        r set x{t} 10
        assert_error "WRONGTYPE*" {r smove myset2{t} x{t} foo}
    }

    test "SMOVE with identical source and destination" {
        r del set{t}
        r sadd set{t} a b c
        r smove set{t} set{t} b
        lsort [r smembers set{t}]
    } {a b c}

    test "SMOVE only notify dstset when the addition is successful" {
        r del srcset{t}
        r del dstset{t}

        r sadd srcset{t} a b
        r sadd dstset{t} a

        r watch dstset{t}

        r multi
        r sadd dstset{t} c

        set r2 [redis_client]
        $r2 smove srcset{t} dstset{t} a

        # The dstset is actually unchanged, multi should success
        r exec
        set res [r scard dstset{t}]
        assert_equal $res 2
        #$r2 close
    }
}

start_server [list overrides [] ] {

# test if the server supports such large configs (avoid 32 bit builds)
catch {
    r config set proto-max-bulk-len 10000000000 ;#10gb
    r config set client-query-buffer-limit 10000000000 ;#10gb
}
if {[lindex [r config get proto-max-bulk-len] 1] == 10000000000} {

    set str_length 4400000000 ;#~4.4GB

    test {SADD, SCARD, SISMEMBER - large data} {
        r flushdb
        r write "*3\r\n\$4\r\nSADD\r\n\$5\r\nmyset\r\n"
        assert_equal 1 [write_big_bulk $str_length "aaa"]
        r write "*3\r\n\$4\r\nSADD\r\n\$5\r\nmyset\r\n"
        assert_equal 1 [write_big_bulk $str_length "bbb"]
        r write "*3\r\n\$4\r\nSADD\r\n\$5\r\nmyset\r\n"
        assert_equal 0 [write_big_bulk $str_length "aaa"]
        assert_encoding hashtable myset
        set s0 [s used_memory]
        assert {$s0 > [expr $str_length * 2]}
        assert_equal 2 [r scard myset]

        r write "*3\r\n\$9\r\nSISMEMBER\r\n\$5\r\nmyset\r\n"
        assert_equal 1 [write_big_bulk $str_length "aaa"]
        r write "*3\r\n\$9\r\nSISMEMBER\r\n\$5\r\nmyset\r\n"
        assert_equal 0 [write_big_bulk $str_length "ccc"]
        r write "*3\r\n\$4\r\nSREM\r\n\$5\r\nmyset\r\n"
        assert_equal 1 [write_big_bulk $str_length "bbb"]
        assert_equal [read_big_bulk {r spop myset} yes "aaa"] $str_length
    } {} {large-memory}
} ;# skip 32bit builds
}
