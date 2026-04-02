import SwiftUI

#if os(iOS)
import UIKit
typealias PlatformColor = UIColor
#elseif os(macOS)
import AppKit

enum PlatformColor {
    static var systemBackground: NSColor { .windowBackgroundColor }
    static var systemGray5: NSColor { .separatorColor }
}
#endif
