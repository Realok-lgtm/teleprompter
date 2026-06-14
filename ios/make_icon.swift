import AppKit

let size = 1024.0
let rect = NSRect(x: 0, y: 0, width: size, height: size)

let img = NSImage(size: rect.size)
img.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else { exit(1) }

// Background: vertical gradient (deep indigo -> violet)
let colors = [
    CGColor(red: 0.36, green: 0.20, blue: 0.92, alpha: 1.0),  // indigo
    CGColor(red: 0.55, green: 0.16, blue: 0.86, alpha: 1.0),  // violet
] as CFArray
let space = CGColorSpaceCreateDeviceRGB()
if let grad = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) {
    ctx.drawLinearGradient(grad,
        start: CGPoint(x: 0, y: size),
        end: CGPoint(x: 0, y: 0),
        options: [])
}

// Letter "T" — bold, white, centered
let letter = "T"
let fontSize = size * 0.62
let font = NSFont.systemFont(ofSize: fontSize, weight: .heavy)
let attrs: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: NSColor.white,
]
let str = NSAttributedString(string: letter, attributes: attrs)
let textSize = str.size()
let pt = NSPoint(x: (size - textSize.width) / 2,
                 y: (size - textSize.height) / 2)
str.draw(at: pt)

img.unlockFocus()

guard let tiff = img.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { exit(1) }

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
try! png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
