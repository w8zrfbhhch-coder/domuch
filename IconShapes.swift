// IconShapes.swift
// Target membership: Drinkstand
//
// Native SwiftUI versions of the icons from Icons_etc.zip (plus,
// minus, checkmark) — traced from the same proportions as the
// original SVGs, so no image assets to import and they stay crisp
// at any size.

import SwiftUI

struct PlusShape: Shape {
    func path(in rect: CGRect) -> Path {
        let t: CGFloat = 18.0 / 53.0 // bar thickness, from the original 53x53 icon
        var p = Path()
        let hBar = CGRect(x: rect.minX,
                           y: rect.minY + rect.height * (1 - t) / 2,
                           width: rect.width,
                           height: rect.height * t)
        let vBar = CGRect(x: rect.minX + rect.width * (1 - t) / 2,
                           y: rect.minY,
                           width: rect.width * t,
                           height: rect.height)
        p.addRect(hBar)
        p.addRect(vBar)
        return p
    }
}

struct MinusShape: Shape {
    // Traced from your SVG: the whole 53×18 viewBox IS the bar —
    // no internal padding, unlike the plus/menu bars.
    func path(in rect: CGRect) -> Path {
        Path(rect)
    }
}

struct CheckShape: Shape {
    // Traced from your new checkmark SVG (63×63 viewBox), built from
    // two rotated rectangles — reproduced here as two exact polygons
    // rather than a rotation, since the source transform includes a
    // mirror and isn't a plain rotation angle.
    private let strokeA: [(CGFloat, CGFloat)] = [
        (0.5949, 0.7857), (0.2020, 0.3928), (0.0000, 0.5949), (0.3928, 0.9877)
    ]
    private let strokeB: [(CGFloat, CGFloat)] = [
        (0.7913, 0.1964), (0.1964, 0.7913), (0.3984, 0.9933), (0.9933, 0.3984)
    ]

    func path(in rect: CGRect) -> Path {
        var p = Path()
        func addPoly(_ pts: [(CGFloat, CGFloat)]) {
            let scaled = pts.map {
                CGPoint(x: rect.minX + $0.0 * rect.width, y: rect.minY + $0.1 * rect.height)
            }
            p.move(to: scaled[0])
            for pt in scaled.dropFirst() { p.addLine(to: pt) }
            p.closeSubpath()
        }
        addPoly(strokeA)
        addPoly(strokeB)
        return p
    }
}
