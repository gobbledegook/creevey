# Known Issues / TODO

Running notes on issues and follow-ups to revisit.

## Done

- **Finder-style multi-file "Rename…" feature.** Done 2026-08-15 — `BatchRename` model +
  `BatchRenameController` sheet with Add Text / Replace Text / Format modes, live example, keep-name
  option, undo-grouped renames. File ▸ Rename… and the thumbnail context menu open it for one or
  more files; configurable `browser.renameItems` (default ⇧E); the quick single-file rename (`e`)
  is unchanged.

- **Go to Folder doesn't follow symlinks.** Fixed 2026-08-15 — `-[CreeveyMainWindowController
  setPath:]` now canonicalizes with `realpath()` (e.g. `/tmp` → `/private/tmp`) before navigating,
  since `stringByResolvingSymlinksInPath` intentionally leaves `/tmp`, `/var`, `/etc` alone.
