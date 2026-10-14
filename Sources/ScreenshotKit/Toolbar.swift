import AppKit

/// The toolbar of the box (D8): Select, the seven tools, Undo, Cancel and Done. A second row with
/// the three sizes and the six colours shows while a tool is selected, and with Select while a
/// mark is selected.
///
/// A thin adapter: a click calls `CaptureInteraction`, and `refresh()` shows the state that it reads there.
final class Toolbar: NSView {
    private static let buttonSide: CGFloat = 28
    private static let padding: CGFloat = 4
    private static let spacing: CGFloat = 2
    private static let groupGap: CGFloat = 9
    static let rowHeight = buttonSide + 2 * padding
    /// The height with the row of the sizes and the colours.
    static let tallestHeight = 2 * rowHeight

    private let interaction: CaptureInteraction
    private var selectButton: ToolbarButton?
    private var toolButtons: [Tool: ToolbarButton] = [:]
    private var sizeButtons: [MarkSize: ToolbarButton] = [:]
    private var colorButtons: [MarkColor: ToolbarButton] = [:]
    private var undoButton: ToolbarButton?
    private let optionsRow = NSView()
    private let tip = NSTextField(labelWithString: "")
    private var width: CGFloat = 0

    init(interaction: CaptureInteraction) {
        self.interaction = interaction
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = CGColor(gray: 0.13, alpha: 0.96)
        layer?.cornerRadius = 8
        layer?.borderColor = CGColor(gray: 1, alpha: 0.18)
        layer?.borderWidth = 0.5

        // "Select" is the first button (D15 on YAZ-2782). It is not a `Tool`: it draws no mark.
        let select = makeButton("Select", image: Toolbar.symbol("cursorarrow", name: "Select")) {
            [interaction] in interaction.toggleSelecting()
        }
        selectButton = select
        let tools = Tool.allCases.map { tool -> ToolbarButton in
            let button = makeButton(tool.name, image: Toolbar.symbol(Toolbar.symbolName(for: tool), name: tool.name)) {
                [interaction] in interaction.selectTool(tool)
            }
            toolButtons[tool] = button
            return button
        }
        let undo = makeButton("Undo", image: Toolbar.symbol("arrow.uturn.backward", name: "Undo")) {
            [interaction] in interaction.undo()
        }
        undoButton = undo
        let cancel = makeButton("Cancel", image: Toolbar.symbol("xmark", name: "Cancel")) {
            [interaction] in interaction.cancel()
        }
        let done = makeButton(
            "Done", tip: Toolbar.doneTip(for: interaction.hotKey), image: Toolbar.symbol("checkmark", name: "Done")
        ) {
            [interaction] in interaction.done()
        }
        done.contentTintColor = NSColor(srgbRed: 0.35, green: 0.85, blue: 0.45, alpha: 1)
        width = layOut([[select] + tools, [undo], [cancel, done]], in: self)

        let sizes = MarkSize.allCases.map { size -> ToolbarButton in
            let button = makeButton(size.name, image: Toolbar.dot(for: size)) { [interaction] in interaction.setSize(size) }
            sizeButtons[size] = button
            return button
        }
        let colors = MarkColor.allCases.map { color -> ToolbarButton in
            let button = makeButton(color.name, image: Toolbar.swatch(for: color)) { [interaction] in interaction.setColor(color) }
            colorButtons[color] = button
            return button
        }
        layOut([sizes, colors], in: optionsRow)
        optionsRow.frame = CGRect(x: 0, y: Toolbar.rowHeight, width: width, height: Toolbar.rowHeight)
        addSubview(optionsRow)

        // The name of the button below the pointer. The toolbar shows it by itself: a tooltip of
        // AppKit is not sure to show above a window of this level when the app is not active.
        tip.font = .systemFont(ofSize: 11)
        tip.textColor = .white
        tip.alignment = .center
        tip.wantsLayer = true
        tip.layer?.backgroundColor = CGColor(gray: 0, alpha: 0.85)
        tip.layer?.cornerRadius = 4
        tip.isHidden = true
        addSubview(tip)

        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    // The main row is at the top, and the row of sizes and colours is below it.
    override var isFlipped: Bool { true }

    /// Shows the state of the interaction: the selected tool, its size and colour, and the second row.
    func refresh() {
        let style = interaction.style
        selectButton?.isOn = interaction.isSelecting
        for (tool, button) in toolButtons { button.isOn = tool == interaction.tool }
        for (size, button) in sizeButtons { button.isOn = size == style?.size }
        for (color, button) in colorButtons { button.isOn = color == style?.color }
        if undoButton?.isEnabled != interaction.canUndo {
            undoButton?.isEnabled = interaction.canUndo
        }
        if optionsRow.isHidden != (style == nil) {
            optionsRow.isHidden = style == nil
            tip.isHidden = true
        }
        let size = CGSize(width: width, height: style == nil ? Toolbar.rowHeight : Toolbar.tallestHeight)
        if frame.size != size { setFrameSize(size) }
    }

    // MARK: The buttons

    /// The tip of Done tells the two keys that do the same as a click: "Done  ↩ or ⇧⌘D".
    static func doneTip(for hotKey: HotKeyCombo?) -> String {
        hotKey.map { "Done  ↩ or \($0.text)" } ?? "Done  ↩"
    }

    private func makeButton(
        _ name: String, tip: String? = nil, image: NSImage, onClick: @escaping () -> Void
    ) -> ToolbarButton {
        let button = ToolbarButton(name: name, tip: tip ?? name, image: image, onClick: onClick)
        button.onHover = { [weak self] button, isInside in
            self?.showTip(isInside ? button : nil)
        }
        return button
    }

    /// Puts the groups of buttons in one row, from the left. Returns the width of the row.
    @discardableResult
    private func layOut(_ groups: [[ToolbarButton]], in row: NSView) -> CGFloat {
        var x = Toolbar.padding
        for (index, group) in groups.enumerated() {
            if index > 0 { x += Toolbar.groupGap - Toolbar.spacing }
            for button in group {
                button.frame = CGRect(x: x, y: Toolbar.padding, width: Toolbar.buttonSide, height: Toolbar.buttonSide)
                row.addSubview(button)
                x += Toolbar.buttonSide + Toolbar.spacing
            }
        }
        return x - Toolbar.spacing + Toolbar.padding
    }

    private func showTip(_ button: ToolbarButton?) {
        guard let button = button else {
            tip.isHidden = true
            return
        }
        tip.stringValue = button.tip
        let textSize = tip.intrinsicContentSize
        let size = CGSize(width: ceil(textSize.width) + 8, height: ceil(textSize.height) + 4)
        let anchor = convert(button.bounds, from: button)
        // Below the toolbar. At the bottom of the screen there is no room, so above the toolbar.
        let hasRoomBelow = superview.map { frame.minY - size.height - 6 >= $0.bounds.minY } ?? true
        // The tip stays inside the width of the toolbar, and the toolbar is inside the screen.
        // The tip of Done is wider than Done, and Done is at the right end.
        let x = min(max(anchor.midX - size.width / 2, bounds.minX), bounds.maxX - size.width)
        tip.frame = CGRect(
            x: x.rounded(),
            y: hasRoomBelow ? bounds.maxY + 4 : -size.height - 4,
            width: size.width,
            height: size.height
        )
        tip.isHidden = false
    }

    // MARK: The pictures of the buttons

    private static func symbolName(for tool: Tool) -> String {
        switch tool {
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .arrow: return "arrow.up.right"
        case .pen: return "pencil"
        case .highlight: return "highlighter"
        case .text: return "textformat"
        case .number: return "1.circle.fill"
        }
    }

    private static func symbol(_ symbolName: String, name: String) -> NSImage {
        // Each symbol of the toolbar is in macOS 11 and later, and the app needs macOS 14.
        NSImage(systemSymbolName: symbolName, accessibilityDescription: name)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)) ?? NSImage()
    }

    /// The picture of a size: a dot that grows with the size.
    private static func dot(for size: MarkSize) -> NSImage {
        let diameter = MarkStyle(color: .black, size: size).lineWidth(for: .pen) + 2
        let image = NSImage(size: CGSize(width: 14, height: 14), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(ovalIn: CGRect(
                x: rect.midX - diameter / 2, y: rect.midY - diameter / 2, width: diameter, height: diameter
            )).fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    /// The picture of a colour: a disc with a grey edge, so black and white show on the dark toolbar.
    private static func swatch(for color: MarkColor) -> NSImage {
        NSImage(size: CGSize(width: 16, height: 16), flipped: false) { rect in
            let disc = NSBezierPath(ovalIn: rect.insetBy(dx: 1.5, dy: 1.5))
            (NSColor(cgColor: MarkRenderer.color(color)) ?? .red).setFill()
            disc.fill()
            NSColor(white: 0.6, alpha: 1).setStroke()
            disc.lineWidth = 1
            disc.stroke()
            return true
        }
    }

    // MARK: Events

    // A click between two buttons must not reach the overlay below. It would start a drag there.
    override func mouseDown(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
}

/// One button of the toolbar: a picture, a name, a tip, and a mark when it is selected.
final class ToolbarButton: NSButton {
    let name: String
    /// The text below the toolbar while the pointer is on the button.
    let tip: String
    private let onClick: () -> Void
    /// Called when the pointer enters (`true`) or leaves (`false`) the button.
    var onHover: ((ToolbarButton, Bool) -> Void)?

    var isOn = false {
        didSet {
            guard isOn != oldValue else { return }
            layer?.backgroundColor = isOn ? CGColor(gray: 1, alpha: 0.28) : nil
        }
    }

    init(name: String, tip: String, image: NSImage, onClick: @escaping () -> Void) {
        self.name = name
        self.tip = tip
        self.onClick = onClick
        super.init(frame: .zero)
        self.image = image
        imagePosition = .imageOnly
        imageScaling = .scaleNone
        isBordered = false
        contentTintColor = .white
        // The keyboard stays with the overlay, so Enter and Esc still work after a click.
        refusesFirstResponder = true
        focusRingType = .none
        wantsLayer = true
        layer?.cornerRadius = 5
        target = self
        action = #selector(clicked)
        setAccessibilityLabel(name)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    @objc private func clicked() {
        onClick()
    }

    // The first click on the overlay of a screen must already press the button.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseEntered(with event: NSEvent) {
        onHover?(self, true)
    }

    override func mouseExited(with event: NSEvent) {
        onHover?(self, false)
    }
}
