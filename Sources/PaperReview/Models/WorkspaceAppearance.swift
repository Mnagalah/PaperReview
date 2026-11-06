import AppKit
import SwiftUI

enum WorkspaceAppearance: String, CaseIterable, Identifiable {
    case dark, light, system
    static let preferenceKey = "workspaceAppearance"
    var id: String { rawValue }
    var title: String { switch self { case .dark: "深色"; case .light: "浅色"; case .system: "跟随系统" } }
    var colorScheme: ColorScheme? { switch self { case .dark: .dark; case .light: .light; case .system: nil } }
}

struct WorkspacePaletteColor {
    let name: String
    let light: UInt32
    let dark: UInt32
    var highContrastLight: UInt32? = nil
    var highContrastDark: UInt32? = nil

    func resolved(dark isDark: Bool, increasedContrast: Bool) -> NSColor {
        let value = isDark ? (increasedContrast ? highContrastDark ?? dark : dark)
                           : (increasedContrast ? highContrastLight ?? light : light)
        return NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
            green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
    }
    var dynamic: NSColor {
        NSColor(name: NSColor.Name("PaperReview.\(name)")) { appearance in
            resolved(dark: appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua,
                increasedContrast: WorkspaceStyle.isHighContrast(appearance))
        }
    }
}

/// One palette owns normal and increased-contrast variants. Native labels,
/// materials and controls still resolve through AppKit's semantic colors.
enum WorkspacePalette {
    static let canvas = WorkspacePaletteColor(name: "canvas", light: 0xf1f2f4, dark: 0x18191b, highContrastLight: 0xe9ebef, highContrastDark: 0x101113)
    static let page = WorkspacePaletteColor(name: "page", light: 0xffffff, dark: 0x18191b)
    static let panel = WorkspacePaletteColor(name: "panel", light: 0xf8f9fa, dark: 0x202226, highContrastLight: 0xffffff, highContrastDark: 0x202226)
    static let sidebar = WorkspacePaletteColor(name: "sidebar", light: 0xeef0f3, dark: 0x24272d)
    static let action = WorkspacePaletteColor(name: "action", light: 0x316fea, dark: 0x316fea, highContrastLight: 0x184fb8, highContrastDark: 0x245fd0)
    static let selection = WorkspacePaletteColor(name: "selection", light: 0xdfe3eb, dark: 0x3c414b)
    static let photoFocus = WorkspacePaletteColor(name: "focus", light: 0x245fca, dark: 0x9abaff, highContrastLight: 0x164cac, highContrastDark: 0xc3d5ff)
    static let spelling = WorkspacePaletteColor(name: "spelling", light: 0xa13c56, dark: 0xe0a1b2, highContrastLight: 0x84253e, highContrastDark: 0xffbdce)
    static let grammar = WorkspacePaletteColor(name: "grammar", light: 0x806125, dark: 0xd2b47c, highContrastLight: 0x62460e, highContrastDark: 0xf2d39a)
    static let border = WorkspacePaletteColor(name: "border", light: 0xdde0e6, dark: 0x35383f, highContrastLight: 0x858b96, highContrastDark: 0x8e949f)
    static let scroller = WorkspacePaletteColor(name: "reviewScroller", light: 0x8a8f98, dark: 0xa1a1a1)
    static let imageFocus = WorkspacePaletteColor(name: "imageFocus", light: 0x316fea, dark: 0x316fea, highContrastLight: 0x164cac, highContrastDark: 0x164cac)
    static let warning = WorkspacePaletteColor(name: "warning", light: 0x8b5700, dark: 0xf0bf63, highContrastLight: 0x694000, highContrastDark: 0xffda96)
}

enum WorkspaceStyle {
    static func isHighContrast(_ appearance: NSAppearance) -> Bool {
        NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            || appearance.name == .accessibilityHighContrastAqua
            || appearance.name == .accessibilityHighContrastDarkAqua
    }
    static let canvasColor = WorkspacePalette.canvas.dynamic
    static let pageColor = WorkspacePalette.page.dynamic
    static let panelColor = WorkspacePalette.panel.dynamic
    static let sidebarColor = WorkspacePalette.sidebar.dynamic
    static let actionColor = WorkspacePalette.action.dynamic
    static let selectionColor = WorkspacePalette.selection.dynamic
    static let photoFocusColor = WorkspacePalette.photoFocus.dynamic
    static let spellingColor = WorkspacePalette.spelling.dynamic
    static let grammarColor = WorkspacePalette.grammar.dynamic
    static let borderColor = WorkspacePalette.border.dynamic
    static let scrollerColor = WorkspacePalette.scroller.dynamic
    static let imageFocusColor = WorkspacePalette.imageFocus.dynamic
    static let warningColor = WorkspacePalette.warning.dynamic
    static func annotationAttributes(color: NSColor, light: Bool, highContrast: Bool = false) -> [NSAttributedString.Key: Any] {
        var result: [NSAttributedString.Key: Any] = [
            .underlineColor: color,
            .underlineStyle: (light || highContrast) ? NSUnderlineStyle.thick.rawValue : NSUnderlineStyle.single.rawValue
        ]
        if light { result[.backgroundColor] = color.withAlphaComponent(0.12) }
        return result
    }
    static var canvas: Color { Color(nsColor: canvasColor) }
    static var page: Color { Color(nsColor: pageColor) }
    static var panel: Color { Color(nsColor: panelColor) }
    static var sidebar: Color { Color(nsColor: sidebarColor) }
    static var action: Color { Color(nsColor: actionColor) }
    static var focus: Color { Color(nsColor: photoFocusColor) }
    static var selection: Color { Color(nsColor: selectionColor) }
    static var border: Color { Color(nsColor: borderColor) }
}

struct WorkspacePrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.colorSchemeContrast) private var contrast
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .medium))
            .foregroundStyle(enabled ? Color.white : Color.secondary)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 7)
                    .fill(enabled ? WorkspaceStyle.action : Color.primary.opacity(0.06))
                    .brightness(enabled && configuration.isPressed ? -0.08 : 0)
            }
            .overlay {
                if contrast == .increased {
                    RoundedRectangle(cornerRadius: 7).strokeBorder(WorkspaceStyle.border, lineWidth: 1)
                }
            }
    }
}

