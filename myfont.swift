import Foundation
import CoreGraphics
import CoreText
import SwiftUI

public struct MyFont {
    
    public static func registerFonts() {
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
    
    fileprivate static func registerFont(fileName: String) {
        
        guard let url = Bundle.main.url(forResource: fileName, withExtension: nil) else {
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
