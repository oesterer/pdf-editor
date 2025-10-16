import AppKit
import PDFKit

struct PendingTextAnnotation {
    let content: String
    let font: NSFont
    let textColor: NSColor
    let backgroundColor: NSColor
}

enum PendingPlacement {
    case text(PendingTextAnnotation)
    case image(NSImage)
}

final class AnnotationPDFView: PDFView, NSTextViewDelegate {
    var pendingPlacement: PendingPlacement? {
        didSet { pendingPlacementDidChange?(pendingPlacement) }
    }

    var pendingPlacementDidChange: ((PendingPlacement?) -> Void)?

    private let selectionOverlay = AnnotationSelectionOverlay()
    private var selectedAnnotation: PDFAnnotation?
    private var selectedAnnotationPage: PDFPage?
    private var dragOperation: DragOperation?

    private var textEditor: AnnotationTextEditor?
    private var editingAnnotation: PDFAnnotation?
    private var editingPage: PDFPage?
    private var editingOriginalContents: String = ""
    private var editingOriginalBounds: CGRect = .zero

    private let minimumAnnotationSize = CGSize(width: 48, height: 32)
    private let minimumFontSize: CGFloat = 8
    private let maximumFontSize: CGFloat = 96

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func layout() {
        super.layout()
        selectionOverlay.frame = bounds
        refreshSelectionOverlay()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard let annotation = selectedAnnotation, let page = selectedAnnotationPage else { return }
        let viewRect = convert(annotation.bounds, from: page)
        addCursorRect(viewRect, cursor: .openHand)

        for (_, frame) in handleFrames(for: viewRect) {
            addCursorRect(frame, cursor: .crosshair)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        if cancelTextEditingIfNeeded() {
            return
        }
        super.cancelOperation(sender)
    }

    override func mouseDown(with event: NSEvent) {
        if commitTextEditingIfNeeded() {
            // committing the edit consumes the click; proceed with selection though
        }

        if let pendingPlacement {
            handlePendingPlacement(pendingPlacement, with: event)
            return
        }

        let locationInView = convert(event.locationInWindow, from: nil)
        if let currentAnnotation = selectedAnnotation,
           let currentPage = selectedAnnotationPage,
           let handle = selectionOverlay.handle(at: locationInView) {
            dragOperation = .resize(annotation: currentAnnotation, page: currentPage, handle: handle, initialBounds: currentAnnotation.bounds)
            return
        }

        guard let page = page(for: locationInView, nearest: true) else {
            deselectAnnotation()
            super.mouseDown(with: event)
            return
        }

        let pagePoint = convert(locationInView, to: page)

        guard let annotation = annotation(at: pagePoint, on: page) else {
            deselectAnnotation()
            super.mouseDown(with: event)
            return
        }

        select(annotation: annotation, on: page)

        if event.clickCount >= 2, isTextAnnotation(annotation) {
            beginEditing(annotation: annotation, on: page)
            return
        }

        dragOperation = .move(annotation: annotation, page: page, startPoint: pagePoint, initialBounds: annotation.bounds)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragOperation else {
            super.mouseDragged(with: event)
            return
        }

        let locationInView = convert(event.locationInWindow, from: nil)

        switch dragOperation {
        case let .move(annotation, page, startPoint, initialBounds):
            let pagePoint = convert(locationInView, to: page)
            let deltaX = pagePoint.x - startPoint.x
            let deltaY = pagePoint.y - startPoint.y

            var newBounds = initialBounds
            newBounds.origin.x += deltaX
            newBounds.origin.y += deltaY
            annotation.bounds = constrainedBounds(newBounds, on: page)
            refreshSelectionOverlay()
        case let .resize(annotation, page, handle, initialBounds):
            let pagePoint = convert(locationInView, to: page)
            var newBounds = bounds(byResizing: initialBounds, towards: handle, with: pagePoint)
            newBounds = constrainedBounds(newBounds, on: page)
            annotation.bounds = newBounds
            refreshSelectionOverlay()
        }
    }

    override func mouseUp(with event: NSEvent) {
        dragOperation = nil
        super.mouseUp(with: event)
    }

    func textDidChange(_ notification: Notification) {
        guard let editor = textEditor else { return }
        editor.adjustHeight(minHeight: minimumAnnotationSize.height)
    }

    @discardableResult
    func adjustSelectedTextFont(by delta: CGFloat) -> Bool {
        if let editor = textEditor {
            let baseFont = editor.font ?? editingAnnotation?.font ?? NSFont.systemFont(ofSize: 18, weight: .regular)
            let targetSize = clampedFontSize(baseFont.pointSize + delta)
            guard abs(targetSize - baseFont.pointSize) > .ulpOfOne else { return true }

            editor.font = baseFont.withSize(targetSize)

            editor.adjustHeight(minHeight: minimumAnnotationSize.height)
            return true
        }

        guard
            let annotation = selectedAnnotation,
            let page = selectedAnnotationPage,
            isTextAnnotation(annotation)
        else {
            return false
        }

        let baseFont = annotation.font ?? NSFont.systemFont(ofSize: 18, weight: .regular)
        let targetSize = clampedFontSize(baseFont.pointSize + delta)
        guard abs(targetSize - baseFont.pointSize) > .ulpOfOne else { return true }

        annotation.font = baseFont.withSize(targetSize)

        let oldBounds = annotation.bounds
        let center = CGPoint(x: oldBounds.midX, y: oldBounds.midY)
        var newBounds = oldBounds
        if baseFont.pointSize > 0 {
            let scale = targetSize / baseFont.pointSize
            newBounds.size.width = max(minimumAnnotationSize.width, oldBounds.width * scale)
            newBounds.size.height = max(minimumAnnotationSize.height, oldBounds.height * scale)
            newBounds.origin.x = center.x - newBounds.size.width / 2
            newBounds.origin.y = center.y - newBounds.size.height / 2
        }

        annotation.bounds = constrainedBounds(newBounds, on: page)
        refreshSelectionOverlay()
        window?.invalidateCursorRects(for: self)
        return true
    }

    private func configure() {
        selectionOverlay.frame = bounds
        selectionOverlay.autoresizingMask = [.width, .height]
        addSubview(selectionOverlay, positioned: .above, relativeTo: nil)
        selectionOverlay.isHidden = true

        NotificationCenter.default.addObserver(self, selector: #selector(handleViewChanges), name: Notification.Name.PDFViewScaleChanged, object: self)
        NotificationCenter.default.addObserver(self, selector: #selector(handleViewChanges), name: Notification.Name.PDFViewPageChanged, object: self)
        NotificationCenter.default.addObserver(self, selector: #selector(handleViewChanges), name: Notification.Name.PDFViewDocumentChanged, object: self)
    }

    @objc
    private func handleViewChanges(_ notification: Notification) {
        refreshSelectionOverlay()
    }

    private func handlePendingPlacement(_ placement: PendingPlacement, with event: NSEvent) {
        guard
            let page = pageFor(event: event),
            let pagePoint = pagePoint(for: event, page: page)
        else {
            super.mouseDown(with: event)
            return
        }

        switch placement {
        case .text(let pendingText):
            let annotation = addTextAnnotation(pendingText, at: pagePoint, on: page)
            select(annotation: annotation, on: page)
        case .image(let image):
            let annotation = addImageAnnotation(image, at: pagePoint, on: page)
            select(annotation: annotation, on: page)
        }

        pendingPlacement = nil
    }

    private func pageFor(event: NSEvent) -> PDFPage? {
        let location = convert(event.locationInWindow, from: nil)
        return page(for: location, nearest: true)
    }

    private func pagePoint(for event: NSEvent, page: PDFPage) -> CGPoint? {
        let location = convert(event.locationInWindow, from: nil)
        return convert(location, to: page)
    }

    private func addTextAnnotation(_ pending: PendingTextAnnotation, at point: CGPoint, on page: PDFPage) -> PDFAnnotation {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: pending.font,
            .foregroundColor: pending.textColor
        ]
        let attributedString = NSAttributedString(string: pending.content, attributes: attributes)
        var size = attributedString.size()
        size.width += 16
        size.height += 12

        let origin = CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2)
        let bounds = CGRect(origin: origin, size: size)

        let annotation = PDFAnnotation(bounds: bounds, forType: .freeText, withProperties: nil)
        annotation.contents = pending.content
        annotation.font = pending.font
        annotation.fontColor = pending.textColor
        annotation.color = pending.backgroundColor
        annotation.alignment = .left
        annotation.isMultiline = true
        annotation.shouldDisplay = true
        annotation.shouldPrint = true

        page.addAnnotation(annotation)
        return annotation
    }

    private func addImageAnnotation(_ image: NSImage, at point: CGPoint, on page: PDFPage) -> PDFAnnotation {
        var imageSize = image.size
        let maxDimension: CGFloat = 240
        let largestSide = max(imageSize.width, imageSize.height)
        if largestSide > 0 {
            let scale = min(1.0, maxDimension / largestSide)
            imageSize = NSSize(width: imageSize.width * scale, height: imageSize.height * scale)
        }

        let origin = CGPoint(x: point.x - imageSize.width / 2, y: point.y - imageSize.height / 2)
        let bounds = CGRect(origin: origin, size: imageSize)

        let annotation = ImageStampAnnotation(image: image, bounds: bounds)
        annotation.shouldDisplay = true
        annotation.shouldPrint = true

        page.addAnnotation(annotation)
        return annotation
    }

    private func annotation(at point: CGPoint, on page: PDFPage) -> PDFAnnotation? {
        let annotations = page.annotations.reversed()
        return annotations.first { $0.bounds.contains(point) }
    }

    private func select(annotation: PDFAnnotation, on page: PDFPage) {
        if editingAnnotation != nil {
            commitTextEditingIfNeeded()
        }

        selectedAnnotation = annotation
        selectedAnnotationPage = page
        refreshSelectionOverlay()
        window?.invalidateCursorRects(for: self)
    }

    private func deselectAnnotation() {
        selectedAnnotation = nil
        selectedAnnotationPage = nil
        selectionOverlay.clear()
        window?.invalidateCursorRects(for: self)
    }

    private func refreshSelectionOverlay() {
        guard let annotation = selectedAnnotation, let page = selectedAnnotationPage, annotation.page === page else {
            selectionOverlay.clear()
            return
        }

        let viewRect = convert(annotation.bounds, from: page)
        let handles = handleFrames(for: viewRect)
        selectionOverlay.update(selectionRect: viewRect, handleRects: handles)
    }

    private func handleFrames(for selectionRect: CGRect) -> [ResizeHandle: CGRect] {
        let handleSize: CGFloat = 10
        let half = handleSize / 2

        var frames: [ResizeHandle: CGRect] = [:]
        frames[.topLeft] = CGRect(x: selectionRect.minX - half, y: selectionRect.maxY - half, width: handleSize, height: handleSize)
        frames[.topRight] = CGRect(x: selectionRect.maxX - half, y: selectionRect.maxY - half, width: handleSize, height: handleSize)
        frames[.bottomLeft] = CGRect(x: selectionRect.minX - half, y: selectionRect.minY - half, width: handleSize, height: handleSize)
        frames[.bottomRight] = CGRect(x: selectionRect.maxX - half, y: selectionRect.minY - half, width: handleSize, height: handleSize)
        return frames
    }

    private func constrainedBounds(_ bounds: CGRect, on page: PDFPage) -> CGRect {
        let pageBounds = page.bounds(for: self.displayBox)
        var clamped = bounds
        clamped.size.width = max(clamped.size.width, minimumAnnotationSize.width)
        clamped.size.height = max(clamped.size.height, minimumAnnotationSize.height)

        if clamped.minX < pageBounds.minX {
            clamped.origin.x = pageBounds.minX
        }
        if clamped.maxX > pageBounds.maxX {
            clamped.origin.x = pageBounds.maxX - clamped.width
        }
        if clamped.minY < pageBounds.minY {
            clamped.origin.y = pageBounds.minY
        }
        if clamped.maxY > pageBounds.maxY {
            clamped.origin.y = pageBounds.maxY - clamped.height
        }

        return clamped
    }

    private func bounds(byResizing initial: CGRect, towards handle: ResizeHandle, with point: CGPoint) -> CGRect {
        var minX = initial.minX
        var maxX = initial.maxX
        var minY = initial.minY
        var maxY = initial.maxY

        switch handle {
        case .topLeft:
            minX = min(point.x, initial.maxX - minimumAnnotationSize.width)
            maxY = max(point.y, initial.minY + minimumAnnotationSize.height)
        case .topRight:
            maxX = max(point.x, initial.minX + minimumAnnotationSize.width)
            maxY = max(point.y, initial.minY + minimumAnnotationSize.height)
        case .bottomLeft:
            minX = min(point.x, initial.maxX - minimumAnnotationSize.width)
            minY = min(point.y, initial.maxY - minimumAnnotationSize.height)
        case .bottomRight:
            maxX = max(point.x, initial.minX + minimumAnnotationSize.width)
            minY = min(point.y, initial.maxY - minimumAnnotationSize.height)
        }

        let newWidth = maxX - minX
        let newHeight = maxY - minY
        return CGRect(x: minX, y: minY, width: newWidth, height: newHeight)
    }

    private func beginEditing(annotation: PDFAnnotation, on page: PDFPage) {
        guard textEditor == nil else { return }

        editingAnnotation = annotation
        editingPage = page
        editingOriginalContents = annotation.contents ?? ""
        editingOriginalBounds = annotation.bounds

        let viewRect = convert(annotation.bounds, from: page)
        let font = annotation.font ?? NSFont.systemFont(ofSize: 18, weight: .regular)
        let textColor = annotation.fontColor ?? NSColor.labelColor
        let annotationBackground = annotation.color
        let backgroundColor: NSColor = annotationBackground.alphaComponent > 0 ? annotationBackground : .clear

        let editor = AnnotationTextEditor(frame: viewRect, font: font, textColor: textColor, backgroundColor: backgroundColor)
        editor.string = annotation.contents ?? ""
        editor.delegate = self
        addSubview(editor, positioned: .above, relativeTo: nil)
        window?.makeFirstResponder(editor)

        editor.adjustHeight(minHeight: minimumAnnotationSize.height)

        selectionOverlay.clear()
        textEditor = editor
    }

    @discardableResult
    private func commitTextEditingIfNeeded() -> Bool {
        guard let editor = textEditor, let annotation = editingAnnotation, let page = editingPage else {
            return false
        }

        let newContents = editor.string
        let trimmed = newContents.trimmingCharacters(in: .whitespacesAndNewlines)

        let editorFrame = editor.frame
        let editorFont = editor.font
        let editorTextColor = editor.textColor

        endEditingSession()

        if trimmed.isEmpty {
            page.removeAnnotation(annotation)
            deselectAnnotation()
        } else {
            annotation.contents = newContents
            if let editorFont {
                annotation.font = editorFont
            }
            if let editorTextColor {
                annotation.fontColor = editorTextColor
            }

            var newBounds = convert(editorFrame, to: page)
            newBounds.size.width = max(newBounds.size.width, minimumAnnotationSize.width)
            newBounds.size.height = max(newBounds.size.height, minimumAnnotationSize.height)
            annotation.bounds = newBounds
            select(annotation: annotation, on: page)
        }

        return true
    }

    @discardableResult
    private func cancelTextEditingIfNeeded() -> Bool {
        guard let annotation = editingAnnotation, let page = editingPage else { return false }
        let originalContents = editingOriginalContents
        let originalBounds = editingOriginalBounds
        endEditingSession()
        annotation.contents = originalContents
        annotation.bounds = originalBounds
        select(annotation: annotation, on: page)
        return true
    }

    private func endEditingSession() {
        textEditor?.removeFromSuperview()
        textEditor = nil
        editingAnnotation = nil
        editingPage = nil
        editingOriginalContents = ""
        editingOriginalBounds = .zero
    }

    private func isTextAnnotation(_ annotation: PDFAnnotation) -> Bool {
        if annotation is ImageStampAnnotation { return false }
        let rawType = annotation.type ?? ""
        let type = rawType.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        return type == "freetext"
    }

    private func clampedFontSize(_ proposed: CGFloat) -> CGFloat {
        min(max(proposed, minimumFontSize), maximumFontSize)
    }
}

private enum ResizeHandle: CaseIterable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
}

private enum DragOperation {
    case move(annotation: PDFAnnotation, page: PDFPage, startPoint: CGPoint, initialBounds: CGRect)
    case resize(annotation: PDFAnnotation, page: PDFPage, handle: ResizeHandle, initialBounds: CGRect)
}

private final class AnnotationSelectionOverlay: NSView {
    private var selectionRect: CGRect = .zero
    private var handleRects: [ResizeHandle: CGRect] = [:]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isHidden = true
        wantsLayer = true
        layer?.isOpaque = false
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isHidden = true
        wantsLayer = true
        layer?.isOpaque = false
    }

    func update(selectionRect: CGRect, handleRects: [ResizeHandle: CGRect]) {
        self.selectionRect = selectionRect
        self.handleRects = handleRects
        isHidden = false
        needsDisplay = true
    }

    func clear() {
        selectionRect = .zero
        handleRects = [:]
        isHidden = true
        needsDisplay = true
    }

    func handle(at point: CGPoint) -> ResizeHandle? {
        for (handle, rect) in handleRects {
            if rect.insetBy(dx: -4, dy: -4).contains(point) {
                return handle
            }
        }
        return nil
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !isHidden else { return }

        let borderColor = NSColor.controlAccentColor.withAlphaComponent(0.85)
        borderColor.setStroke()

        let borderPath = NSBezierPath(rect: selectionRect)
        borderPath.setLineDash([4, 2], count: 2, phase: 0)
        borderPath.lineWidth = 1
        borderPath.stroke()

        let handleColor = NSColor.controlAccentColor
        handleColor.setFill()
        for rect in handleRects.values {
            let path = NSBezierPath(ovalIn: rect)
            path.fill()
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

private final class AnnotationTextEditor: NSTextView {
    private let inset = NSSize(width: 8, height: 6)

    override init(frame frameRect: NSRect, textContainer: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: textContainer)
        commonInit()
    }

    convenience init(frame frameRect: NSRect, font: NSFont, textColor: NSColor, backgroundColor: NSColor) {
        self.init(frame: frameRect, textContainer: nil)
        self.font = font
        self.textColor = textColor
        configureBackground(with: backgroundColor)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        drawsBackground = false
        isRichText = false
        allowsUndo = true
        textContainerInset = inset
        textContainer?.lineFragmentPadding = 0
        isVerticallyResizable = true
        isHorizontallyResizable = false
        textContainer?.widthTracksTextView = true
        wantsLayer = true
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        layer?.borderWidth = 1
        layer?.cornerRadius = 4
    }

    private func configureBackground(with color: NSColor) {
        let fallback = NSColor.windowBackgroundColor.withAlphaComponent(0.3)
        let cgColor = (color.alphaComponent > 0 ? color.withAlphaComponent(min(0.85, color.alphaComponent + 0.2)) : fallback).cgColor
        layer?.backgroundColor = cgColor
    }

    func adjustHeight(minHeight: CGFloat) {
        guard let textContainer, let layoutManager = layoutManager else { return }
        let width = bounds.width - inset.width * 2
        textContainer.containerSize = NSSize(width: max(width, 10), height: .greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let newHeight = max(usedRect.height + inset.height * 2, minHeight)
        if abs(frame.height - newHeight) > 0.5 {
            frame.size.height = newHeight
        }
    }
}

private final class ImageStampAnnotation: PDFAnnotation {
    private let image: NSImage

    init(image: NSImage, bounds: CGRect) {
        self.image = image
        super.init(bounds: bounds, forType: .stamp, withProperties: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            super.draw(with: box, in: context)
            return
        }

        context.saveGState()
        context.draw(cgImage, in: bounds)
        context.restoreGState()
    }
}
