import UIKit

// One description of a menu, turned into UIKit's each time the menu opens.
struct InspectorMenuItem {
    var title: String
    // Shown under the title.
    var value: String?
    var symbolName: String?
    var isOn = false
    var isDestructive = false
    var isDisabled = false
    // A non-empty list makes this a submenu; `handler` is then unused.
    var children: [InspectorMenuItem] = []
    var handler: () -> Void = {}
}

struct InspectorMenu {
    // Each inner list is one group, separated from the next by a divider.
    var sections: [[InspectorMenuItem]]

    fileprivate var elements: [UIMenuElement] {
        // A lone group needs no inline wrapper around it.
        if sections.count == 1 {
            return sections[0].map(Self.element(from:))
        }
        return sections.map { section in
            UIMenu(title: "", options: .displayInline, children: section.map(Self.element(from:)))
        }
    }

    private static func element(from item: InspectorMenuItem) -> UIMenuElement {
        let image = item.symbolName.flatMap { UIImage(systemName: $0) }
        let element: UIMenuElement
        if item.children.isEmpty {
            var attributes: UIMenuElement.Attributes = []
            if item.isDestructive { attributes.insert(.destructive) }
            if item.isDisabled { attributes.insert(.disabled) }
            element = UIAction(
                title: item.title,
                image: image,
                attributes: attributes,
                state: item.isOn ? .on : .off
            ) { _ in item.handler() }
        } else {
            element = UIMenu(title: item.title, image: image, children: item.children.map(element(from:)))
        }
        // Set on the element, whose subtitle is there from iOS 15. Spelled on
        // a UIAction it resolves to UIMenuLeaf's, which only starts at 16.
        element.subtitle = item.value
        return element
    }
}

extension UIBarButtonItem {
    /// A bar item that opens a menu: a system item with a title and a symbol,
    /// never a custom view. The bar draws the symbol; VoiceOver, the large
    /// content viewer and an overflow menu use the title; and on iPhone Duo
    /// the item moves into the vertical bar beside the content with the rest.
    ///
    /// The menu is asked for every time it opens, never stored: what it shows
    /// (live stats, checkmarks, progress) is current at the moment of the tap,
    /// and an open menu is not rebuilt underneath the person by the next sample.
    convenience init(menuTitle title: String, symbolName: String, provider: @escaping () -> InspectorMenu) {
        let menu = UIMenu(children: [
            UIDeferredMenuElement.uncached { completion in
                completion(provider().elements)
            },
        ])
        self.init(title: title, image: UIImage(systemName: symbolName), primaryAction: nil, menu: menu)
        accessibilityLabel = title
        // A tap opens a menu instead of doing something at once, and a lone
        // glyph says nothing about that. VoiceOver reads the hint after the
        // title, so the name still comes first.
        accessibilityHint = String(localized: "Opens a menu")
    }

    /// Lets a custom view into iPhone Duo's vertical bar. The system can't see
    /// inside a custom view, so it keeps one in a horizontal bar: on iPhone
    /// Duo that is a bar across the top, under the status bar, while every
    /// other item has moved to the side. Only for a view that fits the
    /// vertical bar's fixed width as it is.
    @discardableResult
    func preferringVerticalBar() -> UIBarButtonItem {
        #if canImport(UIKit, _version: 9127.0.85)
        if #available(iOS 27.1, *) {
            axisBehavior = .verticalPreferred
        }
        #endif
        return self
    }
}
