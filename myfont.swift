import Foundation
import CoreGraphics
import CoreText
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

public struct MyFont {
    private static var didRegister = false

    public static func registerFonts() {
        guard !didRegister else { return }
        didRegister = true
        let fonts = [
            "OpenSans-Bold.ttf",
            "OpenSans-SemiboldItalic.ttf",
            "Lato-Regular.ttf",
            "lato-heavy.ttf",
            "Ubuntu-Medium.ttf",
            "Ubuntu-Bold.ttf",
            "Ubuntu-Semibold.ttf",
            "UbuntuSans-Bold.ttf"
        ]

        for font in fonts {
            registerFont(fileName: font)
        }
    }

    /// Maps CCBI/Cocos2d font path strings to registered PostScript font names
    /// without silently substituting `"OpenSans-Bold"`.
    public static func normalizedPostScriptName(for rawName: String) -> String {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Helvetica" }
        let base = URL(fileURLWithPath: trimmed).deletingPathExtension().lastPathComponent
        guard !base.isEmpty else { return "Helvetica" }
        switch base.lowercased() {
        case "lato-heavy": return "Lato-Heavy"
        case "lato-regular": return "Lato-Regular"
        case "opensans-bold": return "OpenSans-Bold"
        case "opensans-semibolditalic": return "OpenSans-SemiboldItalic"
        case "ubuntu-bold": return "Ubuntu-Bold"
        case "ubuntu-medium": return "Ubuntu-Medium"
        case "ubuntu-semibold": return "UbuntuSans-SemiBold"
        case "ubuntusans-bold": return "UbuntuSans-Bold"
        default: return base
        }
    }

    #if canImport(UIKit)
    public static func uiFont(named rawName: String, size: CGFloat) -> UIFont {
        registerFonts()
        let clamped = max(1, size)
        let psName = normalizedPostScriptName(for: rawName)
        if let f = UIFont(name: psName, size: clamped) {
            return f
        }
        if psName.lowercased() == "ubuntu-semibold",
           let f = UIFont(name: "UbuntuSans-SemiBold", size: clamped) ?? UIFont(name: "Ubuntu-Medium", size: clamped) {
            return f
        }
        if let f = UIFont(name: "Helvetica", size: clamped) {
            return f
        }
        return UIFont.systemFont(ofSize: clamped)
    }

    public static func requireCustomFont(named exactName: String, size: CGFloat) -> UIFont {
        registerFonts()
        let psName = normalizedPostScriptName(for: exactName)
        guard let font = UIFont(name: psName, size: max(1, size)) else {
            assertionFailure("Bundled font '\(psName)' failed to resolve via UIFont(name:size:)")
            return UIFont(name: "Helvetica", size: max(1, size)) ?? UIFont.systemFont(ofSize: max(1, size))
        }
        return font
    }
    #endif

    fileprivate static func registerFont(fileName: String) {
        let stem = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        guard let url = Bundle.main.url(forResource: fileName, withExtension: nil)
                ?? Bundle.main.url(forResource: stem, withExtension: ext.isEmpty ? nil : ext, subdirectory: "Fonts") else {
            print("Could not find font \(fileName)")
            return
        }

        var error: Unmanaged<CFError>?
        guard CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) else {
            print("Failed to register font \(fileName)")
            return
        }
    }
}
