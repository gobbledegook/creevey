# Phoenix Slides

Official web site: <https://blyt.net/phxslides/>

Phoenix Slides aims to be the fastest way to browse and view the image files
on your disk. Features include the following:

- Fast thumbnailing. Uses embedded EXIF (for jpeg and heic) or JPEG (for raw) previews when appropriate. Otherwise uses macOS's Image I/O framework to scale down images quickly.
- Slideshows (full screen or in a window) with random, loop, and/or auto-advance options
- Special support for sorting files by EXIF (creation) date
- Support for animated GIF and WebP files
- Support for viewing EXIF metadata

And of course, it is open source! After a major code overhaul the source should be
fairly readable now. It's not Swift (this app was started in 2005 when macOS was
called OS X 10.3 and the system frameworks still had very basic bugs in them),
but it's modern!

Enjoy!

## Localization

If anyone wants to help translate to any currently supported or new languages,
let me know. Lately I've been just plugging new strings into google translate
and massaging those results. (I don't actually speak Italian!)

## Compiling

The master branch will generally require the latest version of Xcode.

Commit 7d0cc7e should compile for 10.6+. https://github.com/gobbledegook/creevey/releases/tag/v1.3.1i

Branch xcode326 will compile a universal binary with PPC support but requires Xcode 3.2.6. https://github.com/gobbledegook/creevey/tree/xcode326

## Etymology

`creevey` was the code name for Phoenix Slides when I first started developing it
and code names were cool.
Colin Creevey is the kid in Harry Potter who keeps taking pictures.
