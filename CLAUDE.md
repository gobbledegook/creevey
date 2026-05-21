# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Phoenix Slides (originally codenamed "creevey") is a fast macOS image browser and slideshow application written in Objective-C. The application has been in development since 2005 and uses Cocoa/AppKit frameworks.

## Build Commands

```bash
# Build application
scripts/build       # debug
scripts/build d     # debug
scripts/build r     # release

# Run the
scripts/run         # debug
scripts/run d       # debug
scripts/run r       # release

# Open xcode
scripts/ide
```

## Architecture

### Core Components

**Main Window & Browser**
- `CreeveyMainWindowController`: Central controller managing the main window, containing both the directory browser and thumbnail grid
- `DYCreeveyBrowser`: Custom NSBrowser subclass for directory navigation with typing support and drag/drop
- `DirBrowserDelegate`: Handles directory browser logic and path management

**Image Display & Caching**
- `DYImageView`: Custom view handling image display with zoom, rotation, and flip capabilities
- `DYImageCache`: Manages thumbnail caching for performance
- `DYWrappingMatrix`: Custom matrix view for thumbnail grid display

**Slideshow**
- `SlideshowWindow`: Full-screen or windowed slideshow presentation
- Supports random, loop, and auto-advance modes

**File Management**
- `DYFileWatcher`: Monitors file system changes using VDKQueue
- `DYRandomizableArray`: Array with randomization support for slideshow ordering

### External Dependencies

The project includes embedded libraries:
- `libjpeg`: For JPEG manipulation
- `exiftags`: For EXIF metadata extraction
- `DYjpegtran`: Wrapper for lossless JPEG transformations

### Key Features Implementation

- **Fast thumbnailing**: Uses embedded EXIF/JPEG previews when available, falls back to macOS Image I/O
- **EXIF sorting**: Custom comparator implementation in `CreeveyMainWindowController`
- **Animated GIF/WebP**: Handled through CGImageSource in `DYImageView`

## Interface Files

- `Base.lproj/CreeveyWindow.xib`: Main window layout
- `Base.lproj/MainMenu.xib`: Application menu
- `Base.lproj/PrefsWin.xib`: Preferences window
- `Base.lproj/DYJpegtranPanel.xib`: JPEG transformation panel
- `Base.lproj/ThumbnailContextMenu.xib`: Right-click menu for thumbnails

## Development Notes

- The project requires the latest version of Xcode to build from the master branch
- Code uses modern Objective-C with ARC (Automatic Reference Counting)
- The application supports macOS 10.14+ features when available
- Localization support exists but translations are managed through Google Translate
