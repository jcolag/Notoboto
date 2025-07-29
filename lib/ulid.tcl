# SPDX-FileCopyrightText: 2017 dbohdan
#
# SPDX-License-Identifier: MIT

# A ULID generator with optional Critcl acceleration.
# The default RNG is [::tcl::mathfunc::rand] in pure Tcl and the libc function
# rand() when using Critcl. You can replace the default RNG by setting
# ::ulid::defaultRng to a script that returns a number between 0 and 31.
# Copyright (c) 2017 dbohdan.
# License: MIT.
namespace eval ::ulid {
    variable version 0.1.2
    variable base32 [split 0123456789ABCDEFGHJKMNPQRSTVWXYZ {}]
    if {![info exists useCritcl]} {
        variable useCritcl 0
        if {![catch {
            package require critcl 3
        }]} {
            set useCritcl [::critcl::compiling]
        }
    }
}

# $t is the time in milliseconds.
proc ::ulid::encode-time {t len} {
    if {($t < 0) || ($t > 0xffffffffffff)} {
        error "expected unsigned integer representable in 48 bits but got\
               \"$t\""
    }

    set result {}
    for {set i 0} {$i < $len} {incr i} {
        set m [expr {$t % 32}]
        set result [lindex $::ulid::base32 $m]$result
        set t [expr {($t - $m) / 32}]
    }

    return $result
}

proc ::ulid::gen-random {rng len} {
    set result {}
    for {set i 0} {$i < $len} {incr i} {
        append result [lindex $::ulid::base32 [{*}$rng]]
    }
    return $result
}

proc ::ulid::rng {} {
    return [expr {int(32 * rand())}]
}

if {$::ulid::useCritcl} {
    ::critcl::ccode "#define ULID_BASE32 \"[join $::ulid::base32 {}]\""
    ::critcl::cinit {
        Tcl_Time t;
        Tcl_GetTime(&t);
        srand((unsigned int)(t.sec ^ t.usec));
    } {}
    critcl::cproc ulid::rng-accel {} int {
        return rand() % 32;
    }
    critcl::ccommand ulid::ulid-accel {cdata interp objc objv} {
        Tcl_Obj* result;
        char s[27];
        int i, m;
        Tcl_WideInt t;

        if (objc != 3) {
            Tcl_WrongNumArgs(interp, 1, objv, "t rng");
            return TCL_ERROR;
        }
        if ((Tcl_GetWideIntFromObj(interp, objv[1], &t) != TCL_OK) ||
            (t < 0) || (t > 0xffffffffffff)) {
            Tcl_SetObjResult(interp,
                             Tcl_NewStringObj("expected unsigned integer "
                                              "representable in 48 bits", -1));
            return TCL_ERROR;
        }

        for (i = 9; i >= 0; i--) {
            m = t % 32;
            s[i] = ULID_BASE32[m];
            t = (t - m) / 32;
        }
        for (i = 10; i < 26; i++) {
            int random;
            int rc = Tcl_EvalObjEx(interp, objv[2], 0);
            if (rc != TCL_OK) {
                return rc;
            }
            rc = Tcl_GetIntFromObj(interp, Tcl_GetObjResult(interp), &random);
            if (rc != TCL_OK) {
                return rc;
            }
            if ((random < 0) || (random > 31)) {
                Tcl_SetObjResult(interp,
                                 Tcl_NewStringObj("expected random integer "
                                                  "between 0 and 31", -1));
                return TCL_ERROR;
            }
            s[i] = ULID_BASE32[random % 32];
        }
        s[26] = '\0';

        Tcl_SetObjResult(interp, Tcl_NewStringObj(s, -1));
        return TCL_OK;
    }
    ulid::ulid-accel 0 ::ulid::rng
}

proc ::ulid::ulid {{t {}} {rng {}}} {
    if {$t eq {}} {
        set t [expr {[clock milliseconds]}]
    }
    if {$rng eq {}} {
        if {[info exists ::ulid::defaultRng]} {
            set rng $::ulid::defaultRng
        } elseif {$::ulid::useCritcl} {
            set rng ::ulid::rng-accel
        } else {
            set rng ::ulid::rng
        }
    }
    if {$::ulid::useCritcl} {
        return [ulid-accel $t $rng]
    } else {
        return [encode-time $t 10][gen-random $rng 16]
    }
}

proc ::ulid::test {} {
    if {$::ulid::useCritcl} {
        for {set i 0} {$i < [clock seconds]} {incr i 100001} {
            set accel [string range [::ulid::ulid $i] 0 9]
            set ::ulid::useCritcl 0
            set pure  [string range [::ulid::ulid $i] 0 9]
            set ::ulid::useCritcl 1
            if {$accel ne $pure} {
                error "Critcl ULID time \"$accel\" doesn't equal\
                       pure Tcl ULID time \"$pure\" for t $i"
            }
        }

        set ::ulid::useCritcl 0
        catch {::ulid::ulid nope}
        catch {::ulid::ulid 0 error}
        set ::ulid::useCritcl 1

        puts -nonewline "with Critcl:\n    "
    }

    puts [time ::ulid::ulid 10000]
    catch {::ulid::ulid nope}
    catch {::ulid::ulid 0 error}

    if {$::ulid::useCritcl} {
        puts -nonewline "without Critcl:\n    "
        set ::ulid::useCritcl 0
        puts [time ::ulid::ulid 10000]
        set ::ulid::useCritcl 1
    }
}

if {[info exists argv0] && ([file tail [info script]] eq [file tail $argv0])} {
    if {$argv eq {--test}} {
        ::ulid::test
    } else {
        set n [expr {$argv eq {} ? 1 : $argv}]
        if {![string is integer -strict $n]} {
            puts "usage: $argv0 \[--test | n\]"
            exit 1
        }
        for {set i 0} {$i < $n} {incr i} {
            puts [::ulid::ulid]
        }
    }
}

