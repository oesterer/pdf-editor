# PDF Editor

A lightweight macOS PDF editor built with AppKit and PDFKit. Open any PDF, overlay text or images, and save the annotated document back to disk.

## Browser version

Open the root-level `index.html` in a modern browser. No build step or backend is required. The app loads pinned PDF.js and pdf-lib libraries from CDNs, so internet access is needed to load those dependencies; documents are processed locally and are never uploaded.

Open or drop a PDF, add text or PNG/JPEG images, and click a page to place them. Drag overlays to move them, use the bottom-right handle to resize, and double-click text to edit it. Select an overlay and use Delete to remove it. Save PDF downloads a new copy. Print opens a generated PDF in a new tab; use the viewer’s print command.

Exports include the original PDF and overlay data in a compressed custom PDF stream so reopening in this app preserves editable overlays. Other PDF viewers display the finished edits as page content. This increases file size and retains the original content: this tool is not a redaction tool. Existing annotations from other applications are displayed but cannot be edited. Text export uses Helvetica and its standard character set; unsupported characters produce an export error. Password-protected PDFs are not supported.

## Requirements

- macOS 13 or newer
- Xcode 15 (or the matching Command Line Tools) so that `swift build` can target the bundled PDFKit framework

## Building & Running

```bash
swift run
```

`swift run` launches the editor. If you prefer using Xcode, open the package by running `open Package.swift` and build the generated app target from there.

> **Note**: When running from Terminal, macOS may prompt for permissions the first time the app writes a PDF to disk.

## Using the Editor

- **Open PDF** – Click the *Open* toolbar button and choose the document you want to edit.
- **Add Text** – Click *Add Text*, enter the desired string, then click anywhere on the page to place it. Text annotations remain editable and printable.
- **Add Image** – Click *Add Image*, pick a PNG/JPEG, and click on the page to place it. The image scales to fit within 240 points while preserving aspect ratio.
- **Select & Move** – Click an annotation to show its handles, then drag inside the box to reposition it across the page.
- **Resize** – Drag any of the corner handles to change an annotation’s size. Both text and image overlays support resizing.
- **Edit Text** – Double-click a text annotation to edit its contents inline. Press `Esc` to cancel or click elsewhere to commit the changes.
- **Font Size** – With a text annotation selected (or while editing), use the *A−*/*A+* toolbar buttons to shrink or grow its type.
- **Print** – Hit *Print* in the toolbar to bring up the system print dialog for the current PDF.
- **Save** – Use the *Save* button to export the modified PDF to a new file (the original stays untouched unless you overwrite it explicitly).

All annotations are stored inside the PDF, so any standards-compliant viewer (Preview, Acrobat, etc.) will display them.

## Packaging an App Bundle

Run the packaging helper to build a Release binary and wrap it in a self-contained `.app` bundle. The script converts the root-level `PdfEditorIcon.png` into the `.icns` format using the macOS `sips` and `iconutil` tools, so keep that file handy (or replace it with your own artwork before running the script):

```bash
bash scripts/package.sh
```

The finished bundle is written to `dist/PDF Editor.app`; double-click it (or run `open dist/PDF\ Editor.app`) to launch like any other macOS application. Customize the `Info.plist` inside `scripts/package.sh` if you need a different bundle identifier, version, or metadata.

To install the packaged app into `/Applications`, run:

```bash
bash scripts/install.sh
```

Use `bash scripts/install.sh --force` to overwrite an existing install. The script invokes the packager automatically if the bundle is missing and then deploys the resulting app bundle (including the generated icon) into `/Applications`.
