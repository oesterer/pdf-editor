import AppKit
import PDFKit

final class PDFEditorWindowController: NSWindowController {
    private enum ToolbarItemIdentifier {
        static let open = NSToolbarItem.Identifier("com.codex.pdfeditor.toolbar.open")
        static let addText = NSToolbarItem.Identifier("com.codex.pdfeditor.toolbar.addText")
        static let addImage = NSToolbarItem.Identifier("com.codex.pdfeditor.toolbar.addImage")
        static let decreaseFont = NSToolbarItem.Identifier("com.codex.pdfeditor.toolbar.decreaseFont")
        static let increaseFont = NSToolbarItem.Identifier("com.codex.pdfeditor.toolbar.increaseFont")
        static let print = NSToolbarItem.Identifier("com.codex.pdfeditor.toolbar.print")
        static let save = NSToolbarItem.Identifier("com.codex.pdfeditor.toolbar.save")
        static let flexible = NSToolbarItem.Identifier.flexibleSpace
    }

    private let pdfView = AnnotationPDFView()
    private var currentDocumentURL: URL?
    private let fontAdjustmentStep: CGFloat = 2

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "PDF Editor"
        window.center()

        super.init(window: window)
        setupContent()
        setupToolbar()

        pdfView.pendingPlacementDidChange = { [weak self] pending in
            self?.updateWindowSubtitle(for: pending)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupContent() {
        guard let contentView = window?.contentView else { return }

        pdfView.translatesAutoresizingMaskIntoConstraints = false
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = .windowBackgroundColor

        contentView.addSubview(pdfView)

        NSLayoutConstraint.activate([
            pdfView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            pdfView.topAnchor.constraint(equalTo: contentView.topAnchor),
            pdfView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    private func setupToolbar() {
        let toolbar = NSToolbar(identifier: "com.codex.pdfeditor.toolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        window?.toolbar = toolbar
    }

    @objc
    private func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Open PDF"

        panel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.loadDocument(from: url)
        }
    }

    private func loadDocument(from url: URL) {
        guard let document = PDFDocument(url: url) else {
            presentErrorAlert(message: "Couldn't open the selected PDF.")
            return
        }

        pdfView.document = document
        pdfView.pendingPlacement = nil
        currentDocumentURL = url
        window?.title = "PDF Editor — \(url.lastPathComponent)"
        window?.subtitle = ""
    }

    @objc
    private func requestTextAnnotation(_ sender: Any?) {
        guard pdfView.document != nil else {
            presentErrorAlert(message: "Open a PDF before adding annotations.")
            return
        }

        let alert = NSAlert()
        alert.messageText = "Add Text Annotation"
        alert.informativeText = "Enter the text you want to place, then click on the page." 
        alert.alertStyle = .informational

        let textField = NSTextField(string: "")
        textField.placeholderString = "Annotation text"
        textField.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = textField
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        let content = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }

        let pending = PendingTextAnnotation(
            content: content,
            font: NSFont.systemFont(ofSize: 18, weight: .regular),
            textColor: .labelColor,
            backgroundColor: .clear
        )
        pdfView.pendingPlacement = .text(pending)
    }

    @objc
    private func requestImageAnnotation(_ sender: Any?) {
        guard pdfView.document != nil else {
            presentErrorAlert(message: "Open a PDF before adding annotations.")
            return
        }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Choose Image"

        panel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK, let url = panel.url, let image = NSImage(contentsOf: url) else { return }
            self?.pdfView.pendingPlacement = .image(image)
        }
    }

    @objc
    private func decreaseSelectedTextFont(_ sender: Any?) {
        adjustSelectedTextFont(by: -fontAdjustmentStep)
    }

    @objc
    private func increaseSelectedTextFont(_ sender: Any?) {
        adjustSelectedTextFont(by: fontAdjustmentStep)
    }

    @objc
    private func saveDocument(_ sender: Any?) {
        guard let document = pdfView.document else {
            presentErrorAlert(message: "Open a PDF before saving.")
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = currentDocumentURL?.lastPathComponent ?? "Edited.pdf"
        panel.title = "Save Edited PDF"
        panel.canCreateDirectories = true

        panel.beginSheetModal(for: window!) { response in
            guard response == .OK, let url = panel.url else { return }
            if !document.write(to: url) {
                self.presentErrorAlert(message: "Failed to save the PDF.")
            }
        }
    }

    @objc
    private func printDocument(_ sender: Any?) {
        guard pdfView.document != nil else {
            presentErrorAlert(message: "Open a PDF before printing.")
            return
        }

        let printInfo = NSPrintInfo.shared
        printInfo.horizontalPagination = .automatic
        printInfo.verticalPagination = .automatic
        printInfo.isHorizontallyCentered = true
        printInfo.isVerticallyCentered = true

        pdfView.print(with: printInfo, autoRotate: true)
    }

    private func presentErrorAlert(message: String) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "PDF Editor"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.beginSheetModal(for: window)
    }

    private func adjustSelectedTextFont(by delta: CGFloat) {
        guard pdfView.adjustSelectedTextFont(by: delta) else {
            presentErrorAlert(message: "Select a text annotation to adjust its font size.")
            return
        }
    }

    private func updateWindowSubtitle(for pending: PendingPlacement?) {
        switch pending {
        case .text:
            window?.subtitle = "Click on the PDF to place the text."
        case .image:
            window?.subtitle = "Click on the PDF to place the image."
        case .none:
            window?.subtitle = ""
        }
    }
}

extension PDFEditorWindowController: NSToolbarDelegate {
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            ToolbarItemIdentifier.open,
            ToolbarItemIdentifier.addText,
            ToolbarItemIdentifier.addImage,
            ToolbarItemIdentifier.decreaseFont,
            ToolbarItemIdentifier.increaseFont,
            ToolbarItemIdentifier.print,
            ToolbarItemIdentifier.save,
            ToolbarItemIdentifier.flexible
        ]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            ToolbarItemIdentifier.open,
            ToolbarItemIdentifier.addText,
            ToolbarItemIdentifier.addImage,
            ToolbarItemIdentifier.decreaseFont,
            ToolbarItemIdentifier.increaseFont,
            ToolbarItemIdentifier.print,
            ToolbarItemIdentifier.flexible,
            ToolbarItemIdentifier.save
        ]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)

        switch itemIdentifier {
        case ToolbarItemIdentifier.open:
            item.label = "Open"
            item.paletteLabel = "Open PDF"
            item.toolTip = "Open a PDF document"
            item.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
            item.target = self
            item.action = #selector(openDocument(_:))
        case ToolbarItemIdentifier.addText:
            item.label = "Add Text"
            item.paletteLabel = "Add Text"
            item.toolTip = "Add a text annotation"
            item.image = NSImage(systemSymbolName: "character.cursor.ibeam", accessibilityDescription: nil)
            item.target = self
            item.action = #selector(requestTextAnnotation(_:))
        case ToolbarItemIdentifier.addImage:
            item.label = "Add Image"
            item.paletteLabel = "Add Image"
            item.toolTip = "Overlay an image"
            item.image = NSImage(systemSymbolName: "photo.on.rectangle", accessibilityDescription: nil)
            item.target = self
            item.action = #selector(requestImageAnnotation(_:))
        case ToolbarItemIdentifier.decreaseFont:
            item.label = "A−"
            item.paletteLabel = "Decrease Font Size"
            item.toolTip = "Make the selected text annotation smaller"
            item.image = NSImage(systemSymbolName: "textformat.size.smaller", accessibilityDescription: nil)
            item.target = self
            item.action = #selector(decreaseSelectedTextFont(_:))
        case ToolbarItemIdentifier.increaseFont:
            item.label = "A+"
            item.paletteLabel = "Increase Font Size"
            item.toolTip = "Make the selected text annotation larger"
            item.image = NSImage(systemSymbolName: "textformat.size.larger", accessibilityDescription: nil)
            item.target = self
            item.action = #selector(increaseSelectedTextFont(_:))
        case ToolbarItemIdentifier.print:
            item.label = "Print"
            item.paletteLabel = "Print PDF"
            item.toolTip = "Print the current PDF"
            item.image = NSImage(systemSymbolName: "printer", accessibilityDescription: nil)
            item.target = self
            item.action = #selector(printDocument(_:))
        case ToolbarItemIdentifier.save:
            item.label = "Save"
            item.paletteLabel = "Save PDF"
            item.toolTip = "Save the edited PDF"
            item.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: nil)
            item.target = self
            item.action = #selector(saveDocument(_:))
        default:
            return nil
        }

        return item
    }
}
