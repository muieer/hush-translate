import AppKit

// Run from the repository root: swift scripts/make-menu-bar-icon.swift
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let source = root.appendingPathComponent("design/icons/menu-bar-master.png")
guard let bitmap = NSBitmapImageRep(data: try Data(contentsOf: source)), bitmap.hasAlpha else {
    fatalError("The menu bar master must be a transparent PNG")
}
var minX = bitmap.pixelsWide, minY = bitmap.pixelsHigh, maxX = -1, maxY = -1
for y in 0..<bitmap.pixelsHigh {
    for x in 0..<bitmap.pixelsWide {
        if (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.1 {
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
        }
    }
}
guard maxX >= minX, maxY >= minY,
      let cropped = bitmap.cgImage?.cropping(to: CGRect(
        x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1
      )) else { fatalError("The menu bar master is empty") }
let image = NSImage(cgImage: cropped, size: .zero)

// 2x Retina resource; keep the source aspect ratio inside a 22 x 18 pt canvas.
let width = 44, height = 36
let output = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width,
    pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
    isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: output)
NSGraphicsContext.current?.imageInterpolation = .high
let scale = min(CGFloat(width) / CGFloat(cropped.width), CGFloat(height) / CGFloat(cropped.height))
let size = NSSize(width: CGFloat(cropped.width) * scale, height: CGFloat(cropped.height) * scale)
image.draw(in: NSRect(x: (CGFloat(width) - size.width) / 2,
    y: (CGFloat(height) - size.height) / 2, width: size.width, height: size.height))
NSGraphicsContext.restoreGraphicsState()
let png = output.representation(using: .png, properties: [:])!
for path in ["design/icons/menu-bar-template.png", "Sources/Translate/Resources/MenuBarTemplate.png"] {
    try png.write(to: root.appendingPathComponent(path))
}
print("Generated 44 x 36 template; source bounds: \(cropped.width) x \(cropped.height)")
