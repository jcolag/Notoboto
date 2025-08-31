# SPDX-FileCopyrightText: 2024 John Colagioia <jcolag@colagioia.net>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

# A quick (and probably unreliable) library to parse and emit CSON
# from a dict object.

namespace eval ::cson {
  variable version 0.0.1
  if {![info exists useCritcl]} {
    variable useCritcl 0
    if {![catch {
      package require critcl 3
    }]} {
      set useCritcl [::critcl::compiling]
    }
  }
}

# Transform CSON into a Tcl dictionary.
# $cson_string is a string, describing an object using CSON.
proc ::cson::parse {cson_string} {
  set cson_data [dict create]
  set multiline false
  set insub ""
  set mlkey ""
  set subobject [dict create]

  foreach line [split $cson_string "\n"] {
    if {$insub != "" && ![string match "  *" $line]} {
      # Clean up sub-object when complete
      dict set cson_data $insub $subobject
      set insub ""
    }

    if {$line == ""} {
      # Ignore it
    } elseif {$multiline} {
      if {$line == "'''"} {
        # End the multi-line string.
        set multiline false
        set mlkey ""
      } else {
        # Add another line to the multi-line string.
        set next [string range $line 2 end]
        set value [dict get $cson_data $mlkey]
        append value "\n"
        append value $next
        dict set cson_data $mlkey [string trimleft $value "\n"]
        set value ""
      }
    } elseif {[regexp {^(\w+)\s*:\s*'''\s*$} $line - key]} {
      # Start a multi-line string.
      set multiline true
      set mlkey $key
      dict set cson_data $key ""
    } elseif {[regexp {^(\w+)\s*:\s*('.+')$} $line - key value]} {
      # Add a single-quoted string.
      set v [string range $value 1 end-1]
      dict set cson_data $key $v
    } elseif {[regexp {^(\w+)\s*:\s*(".+")$} $line - key value]} {
      # Add a double-quoted string.
      set v [string range $value 1 end-1]
      dict set cson_data $key $v
    } elseif {[regexp {^(\w+)\s*:\s*(.+)$} $line - key value]} {
      # Add a bare value.
      dict set cson_data $key $value
    } elseif {[regexp {^(\w+)\s*:\s*$} $line - key]} {
      # Begin a sub-object value.
      set insub $key
      set subobject [dict create]
    } elseif {$insub != ""} {
      if {[regexp {^  (\w+)*\s*:\s*('?.+'?)$} $line - key value]} {
        # Add to the sub=pbject.
        if {[string match "'" $value]} {
          set value [string range $value 1 end-1]
        }
        dict set subobject $key $value
      }
    }
  }

  return $cson_data
}

# Transform a Tcl dictionary into a CSON string.
# $obj is the dictionary.
proc ::cson::stringify {obj} {
  set result ""
  set keys [dict keys $obj]

  foreach {key} $keys {
    set value [dict get $obj $key]
    set lines [split $value "\n"]

    if {[llength $lines] > 1} {
      # Key is a multi-line string.
      append result "$key: '''\n"
      foreach {line} $lines {
        append result "  $line\n"
      }
      set result [string trim $result]
      append result "\n'''\n"
    } elseif {[expr {[string is list $value] && ([llength $value]&1) == 0}] && [llength $value] > 20} {
      # Print a sub-object.
      set inner [::cson::stringify $value]
      append result "$key:\n"
      foreach {l} [split $inner "\n"] {
        append result "  $l\n"
      }
    } else {
      # Print single-line key/value pairs.
      if {[regexp {[A-Za-z]} $value] && ![string match "'*'" $value] && $value != true && $value != false} {
        set value "'$value'"
      }
      append result "$key: $value\n"
    }
  }

  return [string trim $result]
}

