#!/usr/bin/wish

# Notoboto:  A note-taking application that can work with but migrates
# away from Boost Note.

package require Img
package require Markdown
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
set creating_category false
set update_preview false

set current_folder -1
set folders_unsorted [dict get $map "folders"]
set folders [lsort -index 5 $folders_unsorted]
set matches [list]
set current_note [dict create]

set color_theme [exec gsettings get org.gnome.desktop.interface gtk-theme]
set fixedFontAttrs [font actual TkFixedFont]

set bg [dict get $config backgroundColor]
set fg [dict get $config foregroundColor]

close $confp
close $mapp

foreach argValue $argv {
  if {[string first "--theme=" $argValue] == 0} {
    set parts [split $argValue "="]
    set color_theme [lindex $parts 1]
  }
}

if {[dict exists $config darkBackgroundColor] && [string first dark $color_theme] >= 0} {
  set bg [dict get $config darkBackgroundColor]
}

# [dict get $config "textSize"]
font create uifont -family TkDefaultFont -size 14
font create txfont -family TkFixedFont -size 18
font create customFixedFont {*}$fixedFontAttrs -size 18
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

button .fr.pnl.choose.category.addtopic -text "New Category ➕" -background $bg -foreground $fg -font uifont -command newCategory
pack .fr.pnl.choose.category.addtopic -side left -fill y

entry .fr.pnl.choose.category.catname -background $bg -foreground $fg -font uifont

frame .fr.pnl.choose.notes -background $bg

scrollbar .fr.pnl.choose.notes.notescroll -orient vertical -background $bg -command ".fr.pnl.choose.notes.note yview"
pack .fr.pnl.choose.notes.notescroll -side right -fill y -expand 1

listbox .fr.pnl.choose.notes.note -background $bg -foreground $fg -font uifont -yscrollcommand ".fr.pnl.choose.notes.notescroll set" -exportselection false
pack .fr.pnl.choose.notes.note -side top -expand 1 -fill y

button .fr.pnl.choose.view -text "View in Browser 🌐" -background $bg -foreground $fg -font uifont -command previewNote

button .fr.pnl.choose.auto -text "Auto-Preview ❌" -background $bg -foreground $fg -font uifont -command autoUpdate

button .fr.pnl.choose.new -text "New Note ➕" -background $bg -foreground $fg -font uifont -command newNote

button .fr.pnl.choose.reload -text "Reload File 🔃" -background $bg -foreground $fg -font uifont -command reloadNote

scrollbar .fr.pnl.textscroll -orient vertical -background $bg -command ".fr.pnl.notearea yview"
pack .fr.pnl.textscroll -side right -fill y -expand 1

text .fr.pnl.notearea -background $bg -foreground [dict get $config "textColor"] -font txfont -wrap word -undo true -padx 5 -pady 5 -yscrollcommand ".fr.pnl.textscroll set"
pack .fr.pnl.notearea -side left -fill y -expand 1

menu .editorContext
.editorContext add command -label "Undo" -state disabled
.editorContext add command -label "Redo" -state disabled
.editorContext add separator
.editorContext add command -label "Cut" -state disabled
.editorContext add command -label "Copy" -command { copyText .fr.pnl.notearea }
.editorContext add command -label "Paste" -command { pasteText .fr.pnl.notearea }

wm title . Notoboto
wm geometry . ${width}x${height}+${x}+${y}
wm iconphoto . -default icon48 icon512

.fr.pnl.notearea configure -insertbackground [dict get $config "textColor"]

foreach {folder} $folders {
  .fr.pnl.choose.topics.topic insert end [dict get $folder "name"]
  .fr.pnl.choose.topics.topic itemconfigure end -foreground [dict get $folder "color"]
}

.fr.pnl.notearea tag bind link <Button-1> {openLink .fr.pnl.notearea %x %y}

bind .fr.pnl.notearea <KeyRelease> {
  addMarkdownSyntaxHighlighting .fr.pnl.notearea
  detectLinks .fr.pnl.notearea
}

# Set handler for changing the subject selection.
bind .fr.pnl.choose.topics.topic <<ListboxSelect>> {
  set idx [%W curselection]
  set temp [openFolder $idx $folders $noteroot getNote $matches]
  set current_folder $idx

  if {$temp != -1} {
    set matches $temp
  }

  pack .fr.pnl.choose.notes -side top
  pack forget .fr.pnl.choose.view
  pack forget .fr.pnl.choose.auto
  pack forget .fr.pnl.choose.new
  pack forget .fr.pnl.choose.reload
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
  pack .fr.pnl.choose.view -side top -fill x
  pack .fr.pnl.choose.auto -side top -fill x
  pack .fr.pnl.choose.new -side top -fill x
  detectLinks .fr.pnl.notearea
  addMarkdownSyntaxHighlighting .fr.pnl.notearea 
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

proc updateSelectedItem {} {
  set selected [selection get .fr.pnl.choose.notes.note]
  set firstLine [.fr.pnl.notearea.text get 1.0 1.0 lineend]
  .fr.pnl.choose.notes.note itemconfigure $selected -text $firstLine
}

# Handle the expired typing timer by writing out the updated note.
proc typingTimeout {} {
  if {$::saving} {
    # Don't interfere with an existing action.
    return
  }

  after cancel $::typing_timer

  global current_note
  global update_preview
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

  if {$update_preview} {
    previewNote false
  }
}

# Open a preview of the current note
proc previewNote {{ open true }} {
  global config
  global current_note
  global update_preview

  set md [dict get $current_note content]
  set title [dict get $current_note title]
  set key [dict get $current_note key]

  set style [dict get $config exportStyle]
  set fa [dict get $config fontAwesomeKit]
  set out_folder [dict get $config tempDire]

  set refresh ""

  if {$update_preview} {
    set refresh "<script>setTimeout(() => location.reload(), 12000);</script>"
  }

  set header "<!DOCTYPE html><html><head><title>$title</title><meta charset='utf-8'>$refresh<style>$style</style>$fa</head><body>"
  set footer "</body></html>"

  set html [::Markdown::convert $md]
  set filename "$key.html"
  set path "$out_folder/$filename"
  set fp [open $path w]

  puts $fp "$header$html$footer"
  close $fp
  if {$open} {
    set code [catch { exec xdg-open $path } result]
  }
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
  set key [uuid::uuid generate]

  dict set note createdAt $time
  dict set note updatedAt $time
  dict set note type "MARKDOWN_NOTE"
  dict set note folder [dict get $folder key]
  dict set note title "Untitled Note"
  dict set note content ""
  dict set note tags {}
  dict set note isStarred false
  dict set note isTrashed false

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
  dict set note key "$key.cson"

  set matches [linsert $matches 0 $note]
  .fr.pnl.choose.notes.note insert 0 [dict get $note title]
  .fr.pnl.choose.notes.note see 0
}

# Add a category to the notes.
proc newCategory { } {
  global creating_category
  global bg
  global fg

  if {$creating_category} {
    global folders
    global map
    global notefile

    set creating_category false
    set category [.fr.pnl.choose.category.catname get]

    pack forget .fr.pnl.choose.category.catname
    .fr.pnl.choose.category.addtopic configure -text "New Category ➕" -background $bg -foreground $fg
    if {$category ne ""} {
      set cat [dict create]

      # Placeholder until I can figure out the 20-hex-digit values.
      dict set cat key [uuid::uuid generate]
      dict set cat color [randomColor]
      dict set cat name $category
      # Save $category and add to .fr.pnl.choose.topics.topic
      lappend folders $cat
      set items [.fr.pnl.choose.topics.topic size]
      .fr.pnl.choose.topics.topic insert $items [dict get $cat name]
      .fr.pnl.choose.topics.topic see $items
      # Save configuration
      dict set map folders folders
    }
  } else {
    set creating_category true

    .fr.pnl.choose.category.catname delete 0 end
    pack .fr.pnl.choose.category.catname -side right
    .fr.pnl.choose.category.addtopic configure -text "➕" -background $bg -foreground $fg
  }
}

# Reload the current note.
proc reloadNote {} {
}

# Toggle whether to automatically update the note preview.
proc autoUpdate {} {
  global update_preview
  global bg
  global fg

  if {$update_preview} {
    set update_preview false
    .fr.pnl.choose.auto configure -text "Auto-Preview ❌" -background $bg -foreground $fg -font uifont
  } else {
    set update_preview true
    .fr.pnl.choose.auto configure -text "Auto-Preview ✅" -background $bg -foreground $fg -font uifont
  }
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

# Procedure to copy selected text from a text widget to the clipboard
proc copyText {widget} {
  if {[$widget tag ranges sel] != ""} {
    set selectedText [$widget get sel.first sel.last]
    clipboard clear
    clipboard append $selectedText
  }
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

# Generate a random color
proc randomColor {} {
  set h [expr { int(256 * rand()) }]
  set s [expr { int(256 * rand()) }]
  set v [expr { int(256 * rand()) }]
  lassign [hsvToRgb $h $s $v] r g b
  return [format "#%02x%02x%02x" $r $g $b]
}

# Convert HSV colors to RGB
proc hsvToRgb {h s v} {
  set Hi [expr { int( double($h) / 60 ) % 6 }]
  set f [expr { double($h) / 60 - $Hi }]
  set s [expr { double($s)/255 }]
  set v [expr { double($v)/255 }]
  set p [expr { double($v) * (1 - $s) }]
  set q [expr { double($v) * (1 - $f * $s) }]
  set t [expr { double($v) * (1 - (1 - $f) * $s) }]
  switch -- $Hi {
    0 {
      set r $v
      set g $t
      set b $p
    }
    1 {
      set r $q
      set g $v
      set b $p
    }
    2 {
      set r $p
      set g $v
      set b $t
    }
    3 {
      set r $p
      set g $q
      set b $v
    }
    4 {
      set r $t
      set g $p
      set b $v
    }
    5 {
      set r $v
      set g $p
      set b $q
    }
    default {
      error "Wrong Hi value in hsvToRgb procedure! This should never happen!"
    }
  }
  set r [expr {round($r*255)}]
  set g [expr {round($g*255)}]
  set b [expr {round($b*255)}]
  return [list $r $g $b]
}

# Open URL in default browser
proc openLink {widget x y} {
  set index [$widget index "@$x,$y"]
  set tagRanges [$widget tag ranges link]
  foreach {start end} $tagRanges {
    if {[$widget compare $start <= $index] && [$widget compare $index < $end]} {
      set url [$widget get $start $end]
      openUrlInBrowser $url
      break
    }
  }
}

# Function to open a URL in the default browser
proc openUrlInBrowser {url} {
  set os [tk windowingsystem]
  switch -- $os {
    "win32" {
      exec start $url
    }
    "aqua" {  # macOS
      exec open $url
    }
    default {  # Assume X11 (Linux, BSD, etc.)
      exec xdg-open $url
    }
  }
}

.fr.pnl.notearea tag configure link -underline true

# Tag links as clickable
proc detectLinks {widget} {
  set urlPattern {(http|https|ftp)://[a-zA-Z0-9./?=_&:@-]*}

  $widget tag remove link 1.0 end

  set startIndex "1.0"
  while 1 {
    set matchStart [$widget search -regexp $urlPattern $startIndex end]
    if {$matchStart == ""} break
    set textAfterMatchStart [$widget get $matchStart end]
    if {[regexp $urlPattern $textAfterMatchStart match]} {
      set matchEnd [$widget index "$matchStart + [string length $match] chars"]
      $widget tag add link $matchStart $matchEnd
    }
    set startIndex $matchEnd
  }
}

# Function to add Markdown syntax highlighting
proc addMarkdownSyntaxHighlighting {widget} {
  $widget tag configure header1 -font {TkDefaultFont 24 bold}
  $widget tag configure header2 -font {TkDefaultFont 24}
  $widget tag configure header3 -font {TkDefaultFont 22 bold}
  $widget tag configure header4 -font {TkDefaultFont 22}
  $widget tag configure header5 -font {TkDefaultFont 20 bold}
  $widget tag configure header6 -font {TkDefaultFont 20}
  $widget tag configure bold -font {TkDefaultFont 18 bold}
  $widget tag configure bold2 -font {TkDefaultFont 18 bold}
  $widget tag configure italic -font {TkDefaultFont 18 italic}
  $widget tag configure italic2 -font {TkDefaultFont 18 italic}
  $widget tag configure code -font customFixedFont
  $widget tag configure codeblock -font customFixedFont
  $widget tag configure list -lmargin1 36 -lmargin2 66

  set header1Pattern {^# [^\n]+\n}
  set header2Pattern {^## [^\n]+\n}
  set header3Pattern {^### [^\n]+\n}
  set header4Pattern {^#### [^\n]+\n}
  set header5Pattern {^##### [^\n]+\n}
  set header6Pattern {^###### [^\n]+\n}
  set boldPattern {\*\*\w([^*\n]*)\*\*}
  set boldPattern2 {__\w([^_\n]*)__}
  set italicPattern {\*\w([^*]+)\*(?!\*)}
  set italicPattern2 {_\w([^_]+)_(?!_)}
  set codePattern {`[^`\n]+`}
  set codeBlockPattern {(?s)```.*?```}
  set listPattern {^\s*[\*\-\+]\s+}

  # Function to apply tags based on patterns
  proc applyTagsForPattern {widget pattern tag} {
    $widget tag remove $tag 1.0 end
    set startIndex "1.0"
    while {$startIndex != "end"} {
      set matchStart [$widget search -regexp $pattern $startIndex end]
      if {$matchStart == ""} break
      set textAfterMatchStart [$widget get $matchStart end]
      if {[regexp $pattern $textAfterMatchStart match]} {
        set matchEnd [$widget index "$matchStart + [string length $match] chars"]
        $widget tag add $tag $matchStart $matchEnd
      }
      set startIndex $matchEnd
    }
  }

  applyTagsForPattern $widget $header1Pattern header1
  applyTagsForPattern $widget $header2Pattern header2
  applyTagsForPattern $widget $header3Pattern header3
  applyTagsForPattern $widget $header4Pattern header4
  applyTagsForPattern $widget $header5Pattern header5
  applyTagsForPattern $widget $header6Pattern header6
  applyTagsForPattern $widget $boldPattern bold
  applyTagsForPattern $widget $boldPattern2 bold2
  applyTagsForPattern $widget $italicPattern italic
  applyTagsForPattern $widget $italicPattern2 italic2
  applyTagsForPattern $widget $codePattern code
  applyTagsForPattern $widget $codeBlockPattern codeblock
  applyTagsForPattern $widget $listPattern list
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

