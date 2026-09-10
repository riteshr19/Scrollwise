import AppKit
import SwiftUI

// Generates Resources/Scrollwise.icns.
//
// Run:  swiftc -parse-as-library Scripts/make-icon.swift -o /tmp/make-icon && /tmp/make-icon
//
// ## Why the arrows are drawn here rather than taken from SF Symbols
// The app's UI uses the `arrow.up.arrow.down` SF Symbol, which is exactly what
// Apple's licence allows: symbols may be used inside an app's interface. The
// same licence prohibits using them in app icons. So the icon reproduces the
// mark with plain Bezier strokes — visually the same idea, no licensed glyph.
//
// ## Geometry
// Apple's macOS icon grid: an 824 x 824 body centred in a 1024 canvas, with a
// continuous (squircle) corner. Everything below is expressed as a fraction of
// the canvas so each size is drawn natively rather than downscaled from one
// master, which keeps the 16 px and 32 px renderings crisp.

private let bodyFraction: CGFloat = 824.0 / 1024.0
private let cornerFraction: CGFloat = 0.2245        // of the body's width
private let glyphFraction: CGFloat = 0.52           // of the body's width

/// The up/down pair, drawn as strokes in a unit box.
struct UpDownArrows: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        // left arrow, pointing up
        p.move(to: CGPoint(x: 0.30 * w, y: 0.90 * h))
        p.addLine(to: CGPoint(x: 0.30 * w, y: 0.10 * h))
        p.move(to: CGPoint(x: 0.12 * w, y: 0.30 * h))
        p.addLine(to: CGPoint(x: 0.30 * w, y: 0.10 * h))
        p.addLine(to: CGPoint(x: 0.48 * w, y: 0.30 * h))
        // right arrow, pointing down
        p.move(to: CGPoint(x: 0.70 * w, y: 0.10 * h))
        p.addLine(to: CGPoint(x: 0.70 * w, y: 0.90 * h))
        p.move(to: CGPoint(x: 0.52 * w, y: 0.70 * h))
        p.addLine(to: CGPoint(x: 0.70 * w, y: 0.90 * h))
        p.addLine(to: CGPoint(x: 0.88 * w, y: 0.70 * h))
        return p
    }
}

struct IconArt: View {
    let side: CGFloat

    var body: some View {
        let body = side * bodyFraction
        let glyph = body * glyphFraction

        ZStack {
            RoundedRectangle(cornerRadius: body * cornerFraction, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(red: 0.24, green: 0.62, blue: 1.00),
                             Color(red: 0.00, green: 0.38, blue: 0.87)],
                    startPoint: .top, endPoint: .bottom))
                .frame(width: body, height: body)
                .shadow(color: .black.opacity(0.22), radius: side * 0.018, y: side * 0.012)

            UpDownArrows()
                .stroke(.white, style: StrokeStyle(lineWidth: glyph * 0.135,
                                                  lineCap: .round, lineJoin: .round))
                .frame(width: glyph, height: glyph)
        }
        .frame(width: side, height: side)
    }
}

@main
struct MakeIcon {
    // (filename, pixel size) — the ten renditions `iconutil` expects.
    static let renditions: [(String, CGFloat)] = [
        ("icon_16x16.png", 16),      ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32),      ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128),   ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256),   ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512),   ("icon_512x512@2x.png", 1024),
    ]

    @MainActor
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let iconset = root.appendingPathComponent("build/Scrollwise.iconset")
        try? FileManager.default.removeItem(at: iconset)
        try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

        for (name, side) in renditions {
            let renderer = ImageRenderer(content: IconArt(side: side))
            renderer.scale = 1
            guard let cg = renderer.cgImage else {
                throw NSError(domain: "make-icon", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "render failed at \(side)"])
            }
            let rep = NSBitmapImageRep(cgImage: cg)
            rep.size = NSSize(width: side, height: side)
            guard let png = rep.representation(using: .png, properties: [:]) else {
                throw NSError(domain: "make-icon", code: 2)
            }
            try png.write(to: iconset.appendingPathComponent(name))
            print("  \(name)  \(cg.width)x\(cg.height)")
        }
        print("iconset written to \(iconset.path)")
    }
}
