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

