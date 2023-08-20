# Notoboto

I apparently needed to take another pass at a note-taking application, this time using the best technology that *1988* has to offer.

## History (of the Project, Not in General)

Once upon a time, I used the original version of [**Boost Note**](https://boostnote.io/) to manage my notes.  It didn't do too much, and despite the overhead of an Electron app, it generally worked, which kept me happy.

When the **Boost Note** team decided to form a service business and overhaul their application, I wished them well, but decided that I didn't fit the target audience for that.  I wanted something lighter-weight, with no worries about somebody else's security.  But I also want to work with my existing notes, which **Boost Note** stored as Markdown-embedded-in-CSON, where CSON comes from CoffeeScript's object notation model comparable to JSON, and where Microsoft tried to push CoffeeScript as the natural evolution to JavaScript, because Microsoft either has no sense of irony or has forgotten about the [Microsoft Coffee](https://microsoft-coffee.medium.com/) debacle.

Anyway, as a result, I wrote [**Miniboost**](https://github.com/jcolag/Miniboost), using an up-and-coming React.js-like framework for desktop, [Proton Native](https://github.com/kusti8/proton-native/issues).  I didn't really do my research, though, and so didn't realize that the team behind Proton Native included one student, building on top of an incomplete library that nobody had updated.

As such, **Miniboost** has served me well for a while, but Node.js still takes a shocking amount of resources, and the fact that I'll probably never have the ability to set a window title in my application bothers me.  That has left me looking for an alternative solution, something that takes even less memory and processing power to run, but also has a mature understanding of how a desktop application should look.

And *that* led me to [Tcl](https://en.wikipedia.org/wiki/Tcl)/[Tk](https://en.wikipedia.org/wiki/Tk_%28software%29), launched in 1988 and 1991, respectively.  Do I *like* the programming environment?  Not really.  Does it have everything that I need to process my existing notes ready to go?  No, I need(ed) to write custom code to manage CSON files.  However, I shouldn't ever have a performance problem, using technology designed to run on computers from more than thirty years ago.

Oh, and why did I use Tcl and not some more modern language that has a Tk library?  Heh.  It turns out that everybody has decided that you "write a Tk library" by bundling up a Tcl/Tk interpreter, and sending it Tcl code.  Therefore, all you Tkinter (and similar) people still use Tcl...

## The Name

I settled on calling this third note-taking application **Notoboto**.  It started as rearranging the letters in the word *boost*, and then I dropped the *s* when I found that the word [botos](https://en.wikipedia.org/wiki/Boto) refers to certain South American river dolphins.  With three out of four syllables ending in a long-*o* sound, it then seemed natural to shift the silent-*e* to another *o*.

And I intended the application icon to look like a stylized version of the boto photograph in the Wikipedia article, swimming in front of the letter *B*.

## Usage

You'll need Tcl/Tk on your system to run this, until I can figure out the current approach to bundling applications.  And at least on Ubuntu, you'll need to install `libtk-img` unless you change the icon to something "native" to Tk.

After that, run the script, and I'll try to keep it working as much like **Miniboost** as I can, with notes auto-saving when you stop typing and making themselves available on a least-recently-used basis.

Over time, I might add features, because Tk's `text` widget can apparently support searching, formatting, and many other features that Proton Native couldn't and even Electron would've required work.  I would also like to migrate the notes away from CSON, at some point, so that I don't need to rely on my shaky custom code.

