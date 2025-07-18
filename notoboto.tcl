#!/usr/bin/wish

# SPDX-FileCopyrightText: 2024 John Colagioia <jcolag@colagioia.net>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

# Notoboto:  A note-taking application that can work with but migrates
# away from Boost Note.

package require Img
package require Markdown
package require Tclx
package require json
package require uuid
package require yaml

set configfile "~/.config/Miniboost.json"
set stopword_dict {}

source "ulid.tcl"
source "stopwords.tcl"

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
set imagesList []

set nextSearchStart "1.0"
set caseSearch false
set wordSearch false
set regexSearch false
set repeatReplace false

set titleText ""
set posText ""
set wdText ""
set chText ""

set color_theme [exec gsettings get org.gnome.desktop.interface gtk-theme]
set fixedFontAttrs [font actual TkFixedFont]

set bg [dict get $config backgroundColor]
set fg [dict get $config foregroundColor]

close $confp
close $mapp

foreach word $stopwords {
    dict set stopword_dict $word 1
}

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
image create photo icon48 -file img/notoboto-48.png
image create photo icon512 -file img/notoboto-512.png
image create photo newcat -file img/library-add-material.png
image create photo newnote -file img/note-add-material.png
image create photo browse -file img/open-in-browser-material.png
image create photo reload -file img/sync-material.png
image create photo yprev -file img/check-circle-material.png
image create photo nprev -file img/cancel-material.png
image create photo logout -file img/logout-material.png
image create photo cut -file img/content-cut-material.png
image create photo copy -file img/content-copy-material.png
image create photo paste -file img/content-paste-material.png
image create photo search -file img/search-material.png
image create photo repeat -file img/repeat-material.png
image create photo outline -file img/list-material.png
image create photo markdown -file img/markdown-material.png

ttk::style configure Treeview -background $bg -foreground $fg -font uifont -fill both -expand 1
ttk::style configure Treeview.Heading -background $fg -foreground $bg -font uifont

frame .fr -background $bg
pack .fr -side top -fill both -expand 1

frame .fr.pnl -relief raised -borderwidth 1 -background $bg
pack .fr.pnl -fill both -expand 1

frame .fr.pnl.choose -width [expr {$width / 5 }] -background $bg
pack .fr.pnl.choose -side left -fill y

frame .fr.status -borderwidth 1 -background $bg
pack .fr.status -side bottom -fill x

label .fr.status.title -background $bg -borderwidth 1 -font uifont -foreground $fg -relief raised -textvariable titleText
label .fr.status.words -background $bg -borderwidth 1 -font uifont -foreground $fg -relief raised -textvariable wdText
label .fr.status.chars -background $bg -borderwidth 1 -font uifont -foreground $fg -relief raised -textvariable chText
label .fr.status.position -background $bg -borderwidth 1 -font uifont -foreground $fg -relief raised -textvariable posText
pack .fr.status.position .fr.status.chars .fr.status.words .fr.status.title .fr.status -side right

menu .mbar -background $bg -foreground $fg
. configure -menu .mbar

menu .mbar.fl -tearoff 0 -background $bg -foreground $fg
menu .mbar.ed -tearoff 0 -background $bg -foreground $fg
.mbar add cascade -menu .mbar.fl -label Notoboto -underline 0
.mbar add cascade -menu .mbar.ed -label Edit -underline 0

.mbar.fl add command -label "New Note" -image newnote -compound left -command { newNote } -background $bg -foreground $fg
.mbar.fl add command -label "Auto-Preview" -image nprev -compound left -command { autoUpdate } -background $bg -foreground $fg
.mbar.fl add command -label "View in Browser" -image browse -compound left -command { previewNote } -background $bg -foreground $fg
.mbar.fl add command -label "Reload File" -image reload -compound left -command { reloadNote } -background $bg -foreground $fg
.mbar.fl add separator
.mbar.fl add command -label "Show Outline" -image outline -compound left -command { createOutlineWindow } -background $bg -foreground $fg
.mbar.fl add command -label "Upgrade Note Format" -image markdown -compound left -command { replaceWithMarkdown } -background $bg -foreground $fg -state disabled
.mbar.fl add separator
.mbar.fl add command -label Exit -image logout -compound left -command { exit } -background $bg -foreground $fg
.mbar.ed add command -label Cut -image cut -compound left -command { cutText .fr.pnl.notearea } -background $bg -foreground $fg
.mbar.ed add command -label Copy -image copy -compound left -command { copyText .fr.pnl.notearea } -background $bg -foreground $fg
.mbar.ed add command -label Paste -image paste -compound left -command { pasteText .fr.pnl.notearea } -background $bg -foreground $fg
.mbar.ed add separator
.mbar.ed add command -label Search -image search -compound left -command { createSearchWindow } -background $bg -foreground $fg

frame .fr.pnl.choose.topics -background $bg
pack .fr.pnl.choose.topics -side top

scrollbar .fr.pnl.choose.topics.topicscroll -orient vertical -background $bg -command ".fr.pnl.choose.topics.topic yview"
pack .fr.pnl.choose.topics.topicscroll -side right -fill y -expand 1

listbox .fr.pnl.choose.topics.topic -background $bg -foreground $fg -font uifont -yscrollcommand ".fr.pnl.choose.topics.topicscroll set" -exportselection false
pack .fr.pnl.choose.topics.topic -side left

frame .fr.pnl.choose.category -background $bg
pack .fr.pnl.choose.category -side top

button .fr.pnl.choose.category.addtopic -text "New Category" -image newcat -compound right -background $bg -foreground $fg -font uifont -command newCategory
pack .fr.pnl.choose.category.addtopic -side left -fill y

entry .fr.pnl.choose.category.catname -background $bg -foreground $fg -font uifont

frame .fr.pnl.choose.notes -background $bg

scrollbar .fr.pnl.choose.notes.notescroll -orient vertical -background $bg -command ".fr.pnl.choose.notes.note yview"
pack .fr.pnl.choose.notes.notescroll -side right -fill y -expand 1

listbox .fr.pnl.choose.notes.note -background $bg -foreground $fg -font uifont -yscrollcommand ".fr.pnl.choose.notes.notescroll set" -exportselection false
pack .fr.pnl.choose.notes.note -side top -expand 1 -fill y

button .fr.pnl.choose.view -text "View in Browser" -image browse -compound right -background $bg -foreground $fg -font uifont -command previewNote

button .fr.pnl.choose.auto -text "Auto-Preview" -image nprev -compound right -background $bg -foreground $fg -font uifont -command autoUpdate

button .fr.pnl.choose.new -text "New Note" -image newnote -compound right -background $bg -foreground $fg -font uifont -command newNote

button .fr.pnl.choose.reload -text "Reload File" -image reload -compound right -background $bg -foreground $fg -font uifont -command reloadNote

scrollbar .fr.pnl.textscroll -orient vertical -background $bg -command ".fr.pnl.notearea yview"
pack .fr.pnl.textscroll -side right -fill y -expand 1

text .fr.pnl.notearea -background $bg -foreground [dict get $config "textColor"] -font txfont -wrap word -undo true -padx 5 -pady 5 -yscrollcommand ".fr.pnl.textscroll set"
pack .fr.pnl.notearea -side left -fill y -expand 1

menu .editorContext -background $bg -foreground $fg -font uifont
.editorContext add command -label "Undo" -state disabled
.editorContext add command -label "Redo" -state disabled
.editorContext add separator
.editorContext add command -label "Cut" -command { cutText .fr.pnl.notearea }
.editorContext add command -label "Copy" -command { copyText .fr.pnl.notearea }
.editorContext add command -label "Paste" -command { pasteText .fr.pnl.notearea }

wm title . Notoboto
wm geometry . ${width}x${height}+${x}+${y}
wm iconphoto . -default icon48 icon512

.fr.pnl.notearea configure -insertbackground [dict get $config "textColor"]
focus .fr.pnl.choose.topics.topic

foreach {folder} $folders {
  .fr.pnl.choose.topics.topic insert end [dict get $folder "name"]
  .fr.pnl.choose.topics.topic itemconfigure end -foreground [dict get $folder "color"]
}

.fr.pnl.notearea tag bind link <Button-1> {openLink .fr.pnl.notearea %x %y}

bind .fr.pnl.notearea <Button-3> {
  .editorContext post %X %Y

  # Check clipboard contents
  if {[catch {clipboard get} clipboardContent]} {
    .editorContext entryconfigure "Paste" -state disabled
  } else {
    .editorContext entryconfigure "Paste" -state normal
  }

  # Check current text selection
  if {[expr {[.fr.pnl.notearea tag ranges sel] == ""}]} {
    .editorContext entryconfigure "Cut" -state disabled
    .editorContext entryconfigure "Copy" -state disabled
  } else {
    .editorContext entryconfigure "Cut" -state normal
    .editorContext entryconfigure "Copy" -state normal
  }
}

bind . <Control-f> {createSearchWindow}
bind . <Control-m> {createOutlineWindow}
bind . <Control-g> {
  if {![winfo exists .searchWin]} {
    createSearchWindow
    return
  }

  set searchTerm [.searchWin.fr.entSearch get]

  if {$searchTerm == ""} {
    createSearchWindow
    return
  }

  searchText .fr.pnl.notearea $searchTerm
}

bind .fr.pnl.notearea <KeyPress> {
  .fr.pnl.notearea tag remove sel 1.0 end
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
  pack .fr.pnl.choose.new -side top -fill x
  pack forget .fr.pnl.choose.view
  pack forget .fr.pnl.choose.auto
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
  .fr.pnl.notearea edit reset
  .fr.pnl.notearea edit modified 0
  pack .fr.pnl.choose.view -side top -fill x
  pack .fr.pnl.choose.auto -side top -fill x
  detectLinks .fr.pnl.notearea
  addMarkdownSyntaxHighlighting .fr.pnl.notearea 

  set title [dict get $current_note title]
  set pos [.fr.pnl.notearea index insert]
  set lens [countText .fr.pnl.notearea]
  set titleText "Title: $title"
  set posText "Position: $pos"
  set wdText "~[lindex $lens 0] words"
  set chText "[lindex $lens 1] characters"

  if {[dict get $current_note "format"] == "md"} {
    .mbar.fl entryconfigure "Upgrade Note Format" -state disabled
  } else {
    .mbar.fl entryconfigure "Upgrade Note Format" -state normal
  }
}

# Bind a timeout to keystrokes.
bind .fr.pnl.notearea <Key> {
  after idle resetTimer
}

# Open a window to search main text.
proc createSearchWindow {} {
  global bg
  global fg
  global caseSearch
  global wordSearch
  global regexSearch
  global repeatReplace

  if {[winfo exists .searchWin]} {
    raise .searchWin
    focus .searchWin.fr.entSearch
    return
  }

  toplevel .searchWin
  wm title .searchWin "Search/Replace"
  wm geometry .searchWin +0-0
  wm transient .searchWin .fr
  wm attributes .searchWin -topmost 1

  image create photo regex -file img/regular-expression-material.png
  image create photo mcase -file img/match-case-material.png
  image create photo mword -file img/match-word-material.png

  frame .searchWin.fr -background $bg
  pack .searchWin.fr -fill both -expand 1

  entry .searchWin.fr.entSearch -background $bg -foreground $fg -font uifont
  pack .searchWin.fr.entSearch -side top -fill x

  frame .searchWin.fr.options -background $bg
  checkbutton .searchWin.fr.options.ocase -image mcase -variable caseSearch
  checkbutton .searchWin.fr.options.oword -image mword -variable wordSearch
  checkbutton .searchWin.fr.options.oregex -image regex -variable regexSearch
  button .searchWin.fr.options.btnSearch -text "Search" -command {searchText .fr.pnl.notearea [.searchWin.fr.entSearch get]} -background $bg -foreground $fg -font uifont
  pack .searchWin.fr.options
  pack .searchWin.fr.options.ocase .searchWin.fr.options.oword .searchWin.fr.options.oregex .searchWin.fr.options.btnSearch -in .searchWin.fr.options -side left

  entry .searchWin.fr.entReplace -background $bg -foreground $fg -font uifont
  pack .searchWin.fr.entReplace -side top -fill x

  frame .searchWin.fr.roptions -background $bg
  checkbutton .searchWin.fr.roptions.repeat -image repeat -variable repeatReplace
  button .searchWin.fr.roptions.btnReplace -text "Replace" -command {replaceText .fr.pnl.notearea [.searchWin.fr.entSearch get] [.searchWin.fr.entReplace get]} -background $bg -foreground $fg -font uifont
  pack .searchWin.fr.roptions
  pack .searchWin.fr.roptions.repeat .searchWin.fr.roptions.btnReplace -in .searchWin.fr.roptions -side left

  focus .searchWin.fr.entSearch
}

# Open a window allowing navigation by headings
proc createOutlineWindow {} {
  global current_note
  global bg
  set lastLevel -1
  set hlist {{} {} {} {} {} {} {}}
  set searchOptions {}
  set headPattern {^#+ }

  if {$current_note == {}} {
    return;
  }

  if {[winfo exists .mapWin]} {
    raise .mapWin
    focus .mapWin.fr.map
    return
  }

  toplevel .mapWin -background $bg
  wm title .mapWin "Document Map"
  wm geometry .mapWin +0-0
  wm transient .mapWin .fr
  wm attributes .mapWin -topmost 1

  frame .mapWin.fr -background $bg
  pack .mapWin.fr -fill both -expand 1

  ttk::treeview .mapWin.fr.map -columns "Heading Location" -displaycolumns "Heading"
  .mapWin.fr.map column "#0" -width 100
  .mapWin.fr.map heading Heading -text "Heading"
  pack .mapWin.fr.map -side top -fill x
  bind .mapWin.fr.map <<TreeviewSelect>> {
    set curItem [.mapWin.fr.map focus]
    set contents [.mapWin.fr.map item $curItem -values]
    set pos [lindex $contents 1]
    .fr.pnl.notearea see $pos
  }

  lappend searchOptions -regexp
  set cur 0.0
  while 1 {
    set cur [.fr.pnl.notearea search -count length {*}$searchOptions -- $headPattern $cur end]
    if {$cur == ""} {
      break
    }
    set level [expr $length - 1]
    set space [.fr.pnl.notearea search -count length -- " " $cur end]
    set eol [.fr.pnl.notearea search -count length -- "\n" $space end]
    set heading [string trim [.fr.pnl.notearea get $cur $eol]]
    set heading [regsub -all "#" [string range $heading 1 end] "  "]
    set parent [lindex $hlist [expr $level - 1]]
    set item [.mapWin.fr.map insert $parent end -values [list $heading $cur] -open true]
    lset hlist $level $item
    set cur $eol
  }
}

# Create a filename by removing stop-words from the title and hyphenating.
proc slugFromTitle {title stopword_dict} {
  set title [string tolower $title]
  set ulid [::ulid::ulid]
  set words [regexp -all -inline {\w+} $title]
  set filtered {}

  foreach word $words {
    if {![dict exists $stopword_dict $word]} {
      lappend filtered $word
    }
  }

  set slug [join $filtered -]

  regsub -- {^-+} $slug "" slug
  regsub -- {-+$} $slug "" slug

  return "${slug}-${ulid}"
}

# Replace the CSON-based note with a Markdown+Metadata equivalent
proc replaceWithMarkdown {} {
  global current_note
  global stopword_dict
  set key [dict get $current_note key]
  set title [dict get $current_note title]
  set slug [slugFromTitle $title $stopword_dict]

  dict set current_note key "$slug.md"
  dict set current_note format "md"
  .fr.pnl.notearea edit modified true

  set path "${::noteroot}/notes/$key"

  typingTimeout
  file delete $path
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

# Handle the expired typing timer by updating the note display and file.
proc typingTimeout {} {
  global current_note
  global update_preview
  global chText
  global posText
  global stopword_dict
  global titleText
  global wdText

  set pos [.fr.pnl.notearea index insert]
  set posText "Position: $pos"

  if {![.fr.pnl.notearea edit modified]} {
    # Nothing to do, if nothing changed.
    return
  }

  # Update syntax highlighting.
  addMarkdownSyntaxHighlighting .fr.pnl.notearea
  detectLinks .fr.pnl.notearea

  # Update status bar.
  set title [dict get $current_note title]
  set lens [countText .fr.pnl.notearea]
  set titleText "Title: $title"
  set wdText "~[lindex $lens 0] words"
  set chText "[lindex $lens 1] characters"

  if {$::saving} {
    # Don't interfere with an existing action.
    return
  }

  if {![.fr.pnl.notearea edit modified]} {
    # Nothing to save
    return
  }

  after cancel $::typing_timer

  set $::saving true
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
  dict set current_note updatedAt $time

  # Update filename.
  set fmt [dict get $current_note format]
  set fmt [string trim $fmt "'\" "]
  set old_key [string trim [dict get $current_note key]]
  set slug [slugFromTitle $title $stopword_dict]
  set filename "${slug}.${fmt}"
  dict set current_note key $filename

  # Write the file.
  set note_text [stringifyDict $current_note]
  set old_file "${::noteroot}/notes/${old_key}"
  set new_file "${::noteroot}/notes/${filename}"
  set fp [open $old_file w]

  puts $fp $note_text
  close $fp
  set $::saving false
  file rename $old_file $new_file
  .fr.pnl.notearea edit modified 0

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
  global config
  global current_folder
  global folders
  global matches
  set noteType "cson"
  set note [dict create]
  set now [clock seconds]
  set time [clock format $now -gmt true -format "%Y-%m-%dT%H:%M:%S.000Z"]
  set folder [lindex $folders $current_folder]
  set key [uuid::uuid generate]
  set keyExt "cson"

  if {[dict exists $config newNoteType]} {
    set noteType [dict get $config newNoteType]
  }

  dict set note createdAt $time
  dict set note updatedAt $time
  dict set note folder [dict get $folder key]
  dict set note title "Untitled Note"
  dict set note content ""
  dict set note tags {}
  dict set note isStarred false
  dict set note isTrashed false

  if {$noteType eq "cson" || $noteType eq ""} {
  dict set note type "MARKDOWN_NOTE"
  } else {
    set keyExt "md"
  }

  dict set note format $keyExt
  dict set note key "$key.$keyExt"

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
    .fr.pnl.choose.auto configure -text "Auto-Preview" -image nprev -compound right -background $bg -foreground $fg -font uifont
  } else {
    set update_preview true
    .fr.pnl.choose.auto configure -text "Auto-Preview" -image yprev -compound right -background $bg -foreground $fg -font uifont
  }
}

# Find all note files that match the subject's key.
proc openFolder { idx folders root getNote matches } {
  if {$idx == ""} {
    return -1
  }

  set csonPath [file join $root "notes" "*.cson"]
  set mdPath [file join $root "notes" "*.md"]
  set csonFiles [glob -nocomplain $csonPath]
  set mdFiles [glob -nocomplain $mdPath]
  set files [concat $csonFiles $mdFiles]
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
      set obj [parseFile $text]
      set title [dict get $obj title]
      set title [string trim $title '"']

      if {![dict exists $obj key]} {
        set parts [split $file "/"]
        set plen [llength $parts]
        dict set $obj key [lindex $parts [expr $plen - 1]]
      }

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

# Perform a search of the current note.
proc searchText {widget searchTerm} {
  global caseSearch
  global wordSearch
  global regexSearch
  set startIndex ""
  set searchPattern ""
  set searchOptions {}

  if {$regexSearch} {
    set searchPattern $searchTerm
  } else {
    if {$wordSearch} {
      if {!$regexSearch} {
        ::regsub -all {[{$\^.?+*\\|()\[\]}]} $searchTerm {\\&} searchTerm

        # Without any regular expression, use a regular expression search.
        lappend searchOptions -regexp
      }

      # Add (regular expression) word boundaries.
      set searchPattern "\\m$searchTerm\\M"
    } else {
      set searchPattern $searchTerm
    }
  }

  if {!$caseSearch} {
    lappend searchOptions -nocase
  }

  if {$regexSearch} {
    lappend searchOptions -regexp
  }

  # Anything selected?
  if {[$widget tag ranges sel] != {}} {
    set startIndex [$widget index {sel.last + 1 char}]
  }

  # Check the caret.
  if {$startIndex eq ""} {
    set startIndex [$widget index insert]
  }

  # No caret.
  if {$startIndex eq [$widget index {end - 1 char}]} {
    set startIndex "1.0"
  }

  $widget tag remove sel 1.0 end

  set matchIndex [$widget search -count lengthVar {*}$searchOptions -- $searchPattern $startIndex end]

  if {$matchIndex != ""} {
    $widget tag add sel $matchIndex "$matchIndex + $lengthVar chars"
    $widget see $matchIndex
    $widget mark set insert $matchIndex
    focus $widget
  }
}

# Replace text in the current note.
proc replaceText {widget searchTerm replaceTerm} {
  global repeatReplace

  searchText $widget $searchTerm
  if {[$widget tag ranges sel] != ""} {
    $widget delete sel.first sel.last
    $widget insert [$widget index insert] $replaceTerm
    if {$repeatReplace} {
      replaceText $widget $searchTerm $replaceTerm
    }
  }
}

# Procedure to cut selected text from a text widget to the clipboard
proc cutText {widget} {
  if {[$widget tag ranges sel] != ""} {
    set selectedText [$widget get sel.first sel.last]
    clipboard clear
    clipboard append $selectedText
    $widget delete sel.first {sel.last + 1 char}
  }
}

# Procedure to copy selected text from a text widget to the clipboard
proc copyText {widget} {
  if {[$widget tag ranges sel] != ""} {
    set selectedText [$widget get sel.first sel.last]
    clipboard clear
    clipboard append $selectedText
  }
}

# Procedure to paste text from the clipboard into the text widget at the cursor position
proc pasteText {widget} {
  set clipboardText [clipboard get]
  $widget insert insert $clipboardText
}

# Convert a Timestamp to UNIX time.
proc ts2u { timestamp } {
  set ts [string trim $timestamp "'\" "]

  if {[string is double -strict $ts]} {
    return $ts
  }

  regsub -nocase {Z$} $ts { UTC} ts
  regsub {\.\d+} $ts {} ts

  return [clock scan $ts -format "%Y-%m-%dT%H:%M:%S %Z"]
}

# Compare dates for sorting.
proc recency { a b } {
  set date1 [ts2u [dict get $a updatedAt]]
  set date2 [ts2u [dict get $b updatedAt]]

  if {$date2 < $date1} {
    return 1
  }

  return -1
}

# Count words in widget
proc countText {widget} {
  set text [.fr.pnl.notearea get 1.0 end]
  set words [regexp -all -inline {\S+} $text]
  set nw [llength $words]
  set chars [string length $text]
  return [list $nw $chars]
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
    "x11" {
      exec xdg-open $url
    }
    default {
      puts "You may need to open ${url} manually on this system."
    }
  }
}

.fr.pnl.notearea tag configure link -underline true

# Tag links as clickable
proc detectLinks {widget} {
  set urlPattern {(http|https|ftp)://[a-zA-Z0-9,./?=_&:@%+-]*(#[a-zA-Z0-9._-]*)?}

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
  $widget tag configure header1 -font {TkDefaultFont 24 bold} -lmargin2 1c
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
  $widget tag configure strike -font {TkDefaultFont 18 overstrike}
  $widget tag configure codeblock -font customFixedFont
  $widget tag configure listitem -lmargin1 1c -lmargin2 1.5c
  $widget tag configure quote -lmargin1 1c -lmargin2 1.5c -rmargin 1c

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
  set strikePattern {~~\w([^_\n]*)~~}
  set codeBlockPattern {(?s)```.*?```}
  set listPattern {^\s*[\*\-\+]\s+[^\n]*}
  set quotePattern {^\s*>\s+[^\n]*}
  set imagePattern {!\[.*?\]\(([^ )]+)(?: ".*?")?\)}

  # Function to apply tags based on patterns
  proc applyTagsForPattern {widget pattern tag clear} {
    $widget tag remove $tag 1.0 end
    set startIndex "1.0"
    while {$startIndex != "end"} {
      set matchStart [$widget search -regexp $pattern $startIndex end]
      if {$matchStart == ""} break
      set textAfterMatchStart [$widget get $matchStart end]
      if {[regexp $pattern $textAfterMatchStart match]} {
        set matchEnd [$widget index "$matchStart + [string length $match] chars"]
        if {$clear} {
          foreach name [$widget tag names] {
            $widget tag remove $name $matchStart $matchEnd
          }
        }
        $widget tag add $tag $matchStart $matchEnd
      }
      set startIndex $matchEnd
    }
  }

  # Function to embed images based on Markdown image syntax
  proc embedImages {widget pattern} {
    global imagesList
    global noteroot
    set startIndex "1.0"
    set index [$widget index {insert + 1 char}]

    set imagesList []
    set images [$widget image names]
    foreach name $images {
      $widget delete $name
    }

    while {$startIndex != "end"} {
      set matchStart [$widget search -regexp $pattern $startIndex end]
      set imagePath ""
      if {$matchStart == ""} break

      set matchEnd [$widget index "$matchStart lineend"]
      set textAfterMatchStart [$widget get $matchStart $matchEnd]

      if {[regexp $pattern $textAfterMatchStart fullMatch imagePath]} {
        set storage [string first ":storage/" $imagePath]

        if {$storage > -1} {
          set l [expr $storage + 9]
          set x [string range $imagePath $l end]
          set imagePath [string cat $noteroot "/images/" $x]
        } else {
          break
        }

        set image [image create photo -file $imagePath]
        lappend imagesList $image
        lappend imagesList "\n-\n"
        $widget image create $matchEnd -image $image
      }
      set startIndex $matchEnd
    }

    if {!$startIndex eq ""} {
      $widget see $index
    }
  }

  applyTagsForPattern $widget $header1Pattern header1 false
  applyTagsForPattern $widget $header2Pattern header2 false
  applyTagsForPattern $widget $header3Pattern header3 false
  applyTagsForPattern $widget $header4Pattern header4 false
  applyTagsForPattern $widget $header5Pattern header5 false
  applyTagsForPattern $widget $header6Pattern header6 false
  applyTagsForPattern $widget $boldPattern bold false
  applyTagsForPattern $widget $boldPattern2 bold2 false
  applyTagsForPattern $widget $italicPattern italic false
  applyTagsForPattern $widget $italicPattern2 italic2 false
  applyTagsForPattern $widget $codePattern code false
  applyTagsForPattern $widget $strikePattern strike false
  applyTagsForPattern $widget $listPattern listitem false
  applyTagsForPattern $widget $quotePattern quote false
  applyTagsForPattern $widget $codeBlockPattern codeblock true
  embedImages $widget $imagePattern
}

# Transform a note file into a Tcl dictionary
proc parseFile {text} {
  if {[string first "content: '''\n" $text] != -1} {
    return [parseCson $text]
  } elseif {[string first "type: \"SNIPPET_NOTE\"\n" $text] != -1} {
    # Do something useful with the snippet notes, someday.
    return [parseCson $text]
  } else {
    return [parseMarkdown $text]
  }
}

# Transform Markdown into a Tcl dictionary
proc parseMarkdown {markdown_string} {
  regsub -all {\r\n?} $markdown_string "\n" markdown_string
  set lines [split $markdown_string "\n"]
  set segments {}

  foreach line $lines {
    if {$line eq "---"} {
      lappend segments $current_segment
      set current_segment ""
    } else {
      append current_segment "$line\n"
    }
  }

  if {[string length $current_segment] > 0} {
      lappend segments $current_segment
  }

  set o [yaml::yaml2dict [lindex $segments 0]]
  set content [lrange $segments 1 end]
  dict set o "content" [join $content "\n---\n"]

  if {![dict exists o "format"]} {
    dict set o "format" "md"
  }

  return $o
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

  if {![dict exists cson_data "format"]} {
    dict set cson_data "format" "cson"
  }

  return $cson_data
}

# Transform a Tcl dictionary into the appropriate serialization format
proc stringifyDict {obj} {
  set what [dict get $obj "format"]

  if {$what == "md"} {
    return [stringifyMarkdown $obj]
  } elseif {$what == "cson"} {
    return [stringifyCson $obj]
  }
}

# Transform a Tcl dictionary into a Markdown string
proc stringifyMarkdown {obj} {
  set yamlObj [dict remove $obj "content"]
  set result [yaml::dict2yaml $yamlObj]

  append result "---\n"
  append result [dict get $obj "content"]

  set lines [split $result "\n"]
  set lines [lrange $lines 1 end]
  set result [join $lines "\n"]

  return [string trim $result]
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

