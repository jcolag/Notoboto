#!/usr/bin/wish

# Notoboto:  A note-taking application that can work with but migrates
# away from Boost Note.

package require Img
package require json

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
set saving false

set folders_unsorted [dict get $map "folders"]
set folders [lsort -index 5 $folders_unsorted]
set matches [list]
set current_note [dict create]

set bg [dict get $config "backgroundColor"]
set fg [dict get $config "foregroundColor"]

close $confp
close $mapp

