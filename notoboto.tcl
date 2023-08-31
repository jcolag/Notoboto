#!/usr/bin/wish

# Notoboto:  A note-taking application that can work with but migrates
# away from Boost Note.

package require Img
package require Tclx
package require json
package require uuid

set configfile "~/.config/Miniboost.json"

set width [expr { [winfo vrootwidth  .] / 4 * 3 }]
set height [expr { [winfo vrootheight .] / 4 * 3 }]
set x 0
set y [expr { [winfo vrootheight .] - $height }]

set confp [open $configfile r]
set conf_json [read $confp]
set config [::json::json2dict $conf_json]

set noteroot [dict get $config "location"]
set notefile [append notefile $noteroot "/boostnote.json"]
set mapp [open $notefile r]
set map_json [read $mapp]
set map [::json::json2dict $map_json]
set typing_timer {}
set saving false

set current_folder -1
set folders_unsorted [dict get $map "folders"]
set folders [lsort -index 5 $folders_unsorted]
set matches [list]
set current_note [dict create]

set bg [dict get $config "backgroundColor"]
set fg [dict get $config "foregroundColor"]

close $confp
close $mapp

font create uifont -family TkDefaultFont -size 14
# [dict get $config "textSize"]
font create txfont -family TkFixedFont -size 18
# [dict get $config "textSize"]
image create photo icon48 -file notoboto-48.png
image create photo icon512 -file notoboto-512.png

frame .fr -background $bg
pack .fr -fill both -expand 1

frame .fr.pnl -relief raised -borderwidth 1 -background $bg
pack .fr.pnl -fill both -expand 1

frame .fr.pnl.choose -width [expr {$width / 5 }] -background $bg
pack .fr.pnl.choose -side left -fill y

menu .mbar -background $bg -foreground $fg
. configure -menu .mbar

menu .mbar.fl -tearoff 0 -background $bg -foreground $fg
.mbar add cascade -menu .mbar.fl -label File -underline 0

.mbar.fl add command -label Exit -command { exit } -background $bg -foreground $fg

frame .fr.pnl.choose.topics -background $bg
pack .fr.pnl.choose.topics -side top

scrollbar .fr.pnl.choose.topics.topicscroll -orient vertical -background $bg -command ".fr.pnl.choose.topics.topic yview"
pack .fr.pnl.choose.topics.topicscroll -side right -fill y -expand 1

listbox .fr.pnl.choose.topics.topic -background $bg -foreground $fg -font uifont -yscrollcommand ".fr.pnl.choose.topics.topicscroll set" -exportselection false
pack .fr.pnl.choose.topics.topic -side left

frame .fr.pnl.choose.category -background $bg
pack .fr.pnl.choose.category -side top

# These two controls will need to get re-oriented, once we have the facility
# to hide and otherwise modify widgets set up.
button .fr.pnl.choose.category.addtopic -text "New Category ➕" -background $bg -foreground $fg -font uifont
pack .fr.pnl.choose.category.addtopic -side top -fill y

entry .fr.pnl.choose.category.catname -background $bg -foreground $fg -font uifont
pack .fr.pnl.choose.category.catname -side bottom

frame .fr.pnl.choose.notes -background $bg
pack .fr.pnl.choose.notes -side top

scrollbar .fr.pnl.choose.notes.notescroll -orient vertical -background $bg -command ".fr.pnl.choose.notes.note yview"
pack .fr.pnl.choose.notes.notescroll -side right -fill y -expand 1

listbox .fr.pnl.choose.notes.note -background $bg -foreground $fg -font uifont -yscrollcommand ".fr.pnl.choose.notes.notescroll set" -exportselection false
pack .fr.pnl.choose.notes.note -side top -expand 1 -fill y

button .fr.pnl.choose.view -text "View in Browser 🌐" -background $bg -foreground $fg -font uifont
pack .fr.pnl.choose.view -side top -fill x

button .fr.pnl.choose.auto -text "Auto-Preview ✅❌" -background $bg -foreground $fg -font uifont
pack .fr.pnl.choose.auto -side top -fill x

button .fr.pnl.choose.new -text "New Note ➕" -background $bg -foreground $fg -font uifont
pack .fr.pnl.choose.new -side top -fill x

button .fr.pnl.choose.reload -text "Reload File 🔃" -background $bg -foreground $fg -font uifont
pack .fr.pnl.choose.reload -side top -fill x

scrollbar .fr.pnl.textscroll -orient vertical -background $bg -command ".fr.pnl.notearea yview"
pack .fr.pnl.textscroll -side right -fill y -expand 1

text .fr.pnl.notearea -background $bg -foreground [dict get $config "textColor"] -font txfont -wrap word -undo true -padx 5 -pady 5 -yscrollcommand ".fr.pnl.textscroll set"
pack .fr.pnl.notearea -side left -fill y -expand 1

wm title . Notoboto
wm geometry . ${width}x${height}+${x}+${y}
wm iconphoto . -default icon48 icon512

foreach {folder} $folders {
  .fr.pnl.choose.topics.topic insert end [dict get $folder "name"]
  .fr.pnl.choose.topics.topic itemconfigure end -foreground [dict get $folder "color"]
}

# Set handler for changing the subject selection.
bind .fr.pnl.choose.topics.topic <<ListboxSelect>> {
  set idx [%W curselection]
  set temp [openFolder $idx $folders $noteroot getNote $matches]
  set current_folder $idx

  if {$temp != -1} {
    set matches $temp
  }
}

# Set handler for changing the note selection.
bind .fr.pnl.choose.notes.note <<ListboxSelect>> {
  set idx [%W curselection]

  if {$idx == ""} {
    return
  }

  set current_note [lindex $matches $idx]

  .fr.pnl.notearea delete 0.0 end
  .fr.pnl.notearea insert 0.0 [dict get $current_note content]
}

# Bind a timeout to keystrokes.
bind .fr.pnl.notearea <Key> {
  after idle resetTimer
}

# Reset the timer.
proc resetTimer {} {
  after cancel $::typing_timer
  set ::typing_timer [after 1000 typingTimeout]
}

# Handle the expired typing timer by writing out the updated note.
proc typingTimeout {} {
  if {$::saving} {
    # Don't interfere with an existing action.
    return
  }

  after cancel $::typing_timer

  global current_note
  set $::saving true
  set filename [dict get $current_note key]
  set stats [dict get $current_note stats]
  set now [clock seconds]

  # Update content
  set text [.fr.pnl.notearea get 1.0 end]
  set lines [split $text "\n"]
  set first [join [lrange $lines 0 0]]
  set first [string trim $first "#"]
  dict set current_note content $text
  dict set current_note title [string trim $first]

  # Update timestamps.
  set time [clock format $now -gmt true -format "%Y-%m-%dT%H:%M:%S.000Z"]
  dict set stats mtime $time
  dict set stats mtimeMs [expr $now * 1000]
  dict set current_note stats $stats
  dict set current_note updatedAt $time

  # Write the file.
  set cson [stringifyCson $current_note]
  set path [append path $::noteroot "/notes/" $filename]
  set fp [open $path w]
  puts $fp $cson
  close $fp
  set $::saving false
}

# Handle requests for new notes.
proc newNote { } {
  global current_folder
  global folders
  global matches
  set note [dict create]
  set stats [dict create]
  set now [clock seconds]
  set time [clock format $now -gmt true -format "%Y-%m-%dT%H:%M:%S.000Z"]
  set folder [lindex $folders $current_folder]

  dict set note createdAt $time
  dict set note updatedAt $time
  dict set note type "MARKDOWN_NOTE"
  dict set note folder [dict get $folder key]
  dict set note title "Untitled Note"
  dict set note content ""
  dict set note tags {}
  dict set note isStarred false
  dict set note isTrahsed false

  dict set stats dev 64769
  dict set stats mode 33204
  dict set stats nlink 1
  dict set stats uid [id userid]
  dict set stats gid [id groupid]
  dict set stats rdev 0
  dict set stats blksize 4096
  dict set stats ino 0
  dict set stats size 0
  dict set stats blocks 24
  dict set stats atimeMs $now
  dict set stats mtimeMs $now
  dict set stats ctimeMs $now
  dict set stats atime $time
  dict set stats ctime $time
  dict set stats mtime $time
  dict set stats birthtime $time

  dict set note stats $stats
  dict set note key [uuid::uuid generate]

  set matches [linsert $matches 0 $note]
  .fr.pnl.choose.notes.note insert 0 [dict get $note title]
  .fr.pnl.choose.notes.note see 0
}

# Find all note files that match the subject's key.
proc openFolder { idx folders root getNote matches } {
  if {$idx == ""} {
    return -1
  }

  set path [append files $root "/notes/*.cson"]
  set files [glob $path]
  set o [lindex $folders $idx]
  set key [dict get $o "key"]
  set count 0
  set matches [list]

  .fr.pnl.choose.notes.note delete 0 end
  foreach {file} $files {
    set fp [open $file r]
    set text [read $fp]
    close $fp

    if {[string first $key $text] != -1} {
      set obj [parseCson $text]
      set title [dict get $obj title]
      set title [string trim $title '"']

      if {![dict get $obj isTrashed]} {
        # Add the title to the note list if the note hasn't been
        # deleted and it's part of the folder.
        lappend matches $obj
        incr count
      }
    }
  }

  set matches [lsort -command recency -decreasing $matches]

  foreach {match} $matches {
    .fr.pnl.choose.notes.note insert end [dict get $match title]
  }

  return $matches
}

# Open the note in the text control.
proc openNote { idx } {
  return $idx
}

# Compare dates for sorting.
proc recency { a b } {
  set date1 [dict get $a updatedAt]
  set date2 [dict get $b updatedAt]

  if {$date2 < $date1} {
    return 1
  }

  return -1
}

# Transform CSON into a Tcl dictionary
proc parseCson {cson_string} {
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

# Transform a Tcl dictionary into a CSON string
proc stringifyCson {obj} {
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
      set inner [stringifyCson $value]
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

