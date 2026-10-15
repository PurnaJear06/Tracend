import CoreText
import SwiftUI

/// Tracend's graphite + signal lime colors and number face for the Live
/// Activity (docs/DESIGN_SYSTEM.md §2, §3.1). The activity always draws on
/// graphite, in light and dark mode alike, so its text and lime keep the
/// contrast of the app's dark theme.
enum TracendStyle {
  /// `surface` (dark): the Lock Screen card.
  static let graphite = Color(hex: 0x18191B)
  /// `textPrimary` (dark).
  static let textPrimary = Color(hex: 0xF4F4F1)
  /// `textSecondary` (dark).
  static let textSecondary = Color(hex: 0x9C9D98)
  /// `accentSignal`: the one thing that is now, the running rest.
  static let lime = Color(hex: 0xC8F05A)
  /// `surfaceRaised` (dark): the +30s and Skip buttons.
  static let raised = Color(hex: 0x232427)
  /// `onAccentSignal`: text and icons on a lime fill (the Done button).
  static let onLime = Color(hex: 0x141A05)

  /// Archivo SemiCondensed ExtraBold, the app's number face, bundled with the
  /// extension and listed in its `UIAppFonts`. The file's internal font name
  /// is "Archivo-SemiBold" (the app's Archivo cuts share it), so the name is
  /// read from the file instead of being written here. Registering it again
  /// by URL is a no-op when `UIAppFonts` already did. Nil when the file is
  /// missing.
  private static let numericFontName: String? = {
    guard
      let url = Bundle.main.url(
        forResource: "ArchivoSemiCondensed-ExtraBold",
        withExtension: "ttf"
      ),
      let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL)
        as? [CTFontDescriptor],
      let descriptor = descriptors.first,
      let name = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String
    else { return nil }
    CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    return name
  }()

  /// The number face at `size` points, with tabular figures so a countdown
  /// never jitters. Falls back to the condensed system face.
  static func numeric(_ size: CGFloat) -> Font {
    guard let name = numericFontName else {
      return .system(size: size, weight: .heavy).width(.condensed).monospacedDigit()
    }
    return .custom(name, fixedSize: size).monospacedDigit()
  }
}

extension Color {
  fileprivate init(hex: UInt32) {
    self.init(
      .sRGB,
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255
    )
  }
}
