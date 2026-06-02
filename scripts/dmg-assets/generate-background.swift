#!/usr/bin/env swift
// Generates the DMG background image with an arrow between app and Applications icons.
// Usage: swift scripts/dmg-assets/generate-background.swift

import AppKit

let width: CGFloat = 600
let height: CGFloat = 400
let img = NSImage(size: NSSize(width: width, height: height))
img.lockFocus()

NSColor(calibratedWhite: 0.96, alpha: 1.0).setFill()
NSRect(origin: .zero, size: img.size).fill()

let midX: CGFloat = 300
let midY: CGFloat = 215 + 15

let arrowColor = NSColor(calibratedWhite: 0.68, alpha: 0.9)

let path = NSBezierPath()

let shaftLeft: CGFloat = midX - 40
let shaftRight: CGFloat = midX + 20
let tipX: CGFloat = midX + 45
let shaftHalfH: CGFloat = 8
let headHalfH: CGFloat = 20

path.move(to: NSPoint(x: shaftLeft, y: midY + shaftHalfH))
path.line(to: NSPoint(x: shaftRight, y: midY + shaftHalfH))
path.line(to: NSPoint(x: shaftRight, y: midY + headHalfH))
path.line(to: NSPoint(x: tipX, y: midY))
path.line(to: NSPoint(x: shaftRight, y: midY - headHalfH))
path.line(to: NSPoint(x: shaftRight, y: midY - shaftHalfH))
path.line(to: NSPoint(x: shaftLeft, y: midY - shaftHalfH))
path.close()

arrowColor.setStroke()
path.lineWidth = 2.0
path.lineJoinStyle = .round
path.lineCapStyle = .round
path.stroke()

NSColor(calibratedWhite: 0.82, alpha: 0.4).setFill()
path.fill()

img.unlockFocus()

let tiff = img.tiffRepresentation!
let bitmap = NSBitmapImageRep(data: tiff)!
let png = bitmap.representation(using: .png, properties: [:])!
let outputPath = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("background.png")
try! png.write(to: outputPath)
print("Generated: \(outputPath.path)")
