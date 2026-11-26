import SwiftUI
import UIKit

enum Theme {
    static let rose = Color(red: 196 / 255, green: 122 / 255, blue: 134 / 255)
    static let sage = Color(red: 127 / 255, green: 163 / 255, blue: 138 / 255)
    static let fixedInk = Color(red: 46 / 255, green: 42 / 255, blue: 43 / 255)
    static let paper = adaptive(0xF7F5F1, 0x211D1E)
    static let surface = adaptive(0xFFFFFF, 0x2D2628)
    static let ink = adaptive(0x2E2A2B, 0xFFF1EC)
    static let muted = adaptive(0x6A5453, 0xCEB9B5)
    static let boundary = adaptive(0xE8DDD7, 0x524347)
    static let blush = adaptive(0xF5E7E7, 0x453036)
    static let link = adaptive(0x78424C, 0xF2AFBA)
    static let mean = adaptive(0x4E6D56, 0x9EC4A6)
    static let primary = Color(red: 152 / 255, green: 80 / 255, blue: 96 / 255)
    static let heroRose = adaptive(0xF1D5DA, 0x51343C)
    static let heroIvory = adaptive(0xFFF9F3, 0x332A2C)
    static let sageWash = adaptive(0xE7F0E9, 0x324339)
    static let amberWash = adaptive(0xFAECD4, 0x4A3825)
    static let amberInk = adaptive(0x78521D, 0xF3CC8E)
    static let blueWash = adaptive(0xE7EFF3, 0x2D4049)
    static let blueInk = adaptive(0x3D6274, 0xB3D4E4)

    static let cardRadius: CGFloat = 18
    static let sectionSpacing: CGFloat = 22

    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { trait in
            let hex = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat(hex >> 16) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                           blue: CGFloat(hex & 255) / 255, alpha: 1)
        })
    }
}
