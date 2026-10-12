import Foundation
import UIKit

struct RGBColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = red.clamped(to: 0...1)
        self.green = green.clamped(to: 0...1)
        self.blue = blue.clamped(to: 0...1)
    }

    init?(hex: String) {
        let value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard value.count == 6, let integer = UInt64(value, radix: 16) else { return nil }
        self.init(
            red: Double((integer >> 16) & 0xFF) / 255,
            green: Double((integer >> 8) & 0xFF) / 255,
            blue: Double(integer & 0xFF) / 255
        )
    }

    var hex: String {
        String(
            format: "%02X%02X%02X",
            Int((red * 255).rounded()),
            Int((green * 255).rounded()),
            Int((blue * 255).rounded())
        )
    }

    var relativeLuminance: Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    var hueSaturationLightness: (hue: Double, saturation: Double, lightness: Double) {
        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        let delta = maximum - minimum
        let lightness = (maximum + minimum) / 2
        guard delta > 0 else { return (0, 0, lightness) }

        let saturation = delta / (1 - abs(2 * lightness - 1))
        var hue: Double
        if maximum == red {
            hue = (green - blue) / delta
        } else if maximum == green {
            hue = (blue - red) / delta + 2
        } else {
            hue = (red - green) / delta + 4
        }
        hue = (hue * 60).truncatingRemainder(dividingBy: 360)
        if hue < 0 { hue += 360 }
        return (hue, saturation, lightness)
    }

    init(hue: Double, saturation: Double, lightness: Double) {
        let normalizedHue = (hue.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360) / 60
        let saturation = saturation.clamped(to: 0...1)
        let lightness = lightness.clamped(to: 0...1)
        let chroma = (1 - abs(2 * lightness - 1)) * saturation
        let secondary = chroma * (1 - abs(normalizedHue.truncatingRemainder(dividingBy: 2) - 1))
        let components: (Double, Double, Double)
        switch Int(floor(normalizedHue)) {
        case 0: components = (chroma, secondary, 0)
        case 1: components = (secondary, chroma, 0)
        case 2: components = (0, chroma, secondary)
        case 3: components = (0, secondary, chroma)
        case 4: components = (secondary, 0, chroma)
        default: components = (chroma, 0, secondary)
        }
        let offset = lightness - chroma / 2
        self.init(red: components.0 + offset, green: components.1 + offset, blue: components.2 + offset)
    }
}

enum DominantColorExtractor {
    private struct Bucket {
        var count = 0
        var red = 0
        var green = 0
        var blue = 0
    }

    static func dominantColor(in image: UIImage) -> RGBColor? {
        let source = image.cgImage ?? UIGraphicsImageRenderer(size: image.size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }.cgImage
        guard let source else { return nil }

        let dimension = 32
        let bytesPerRow = dimension * 4
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.union(
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        )
        guard let context = CGContext(
            data: nil,
            width: dimension,
            height: dimension,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo.rawValue
        ) else { return nil }

        context.interpolationQuality = .low
        context.draw(source, in: CGRect(x: 0, y: 0, width: dimension, height: dimension))
        guard let bytes = context.data?.bindMemory(to: UInt8.self, capacity: dimension * dimension * 4) else {
            return nil
        }

        var buckets: [Int: Bucket] = [:]
        for index in 0..<(dimension * dimension) {
            let offset = index * 4
            let alpha = Int(bytes[offset + 3])
            guard alpha >= 32 else { continue }
            let red = min(255, Int(bytes[offset]) * 255 / alpha)
            let green = min(255, Int(bytes[offset + 1]) * 255 / alpha)
            let blue = min(255, Int(bytes[offset + 2]) * 255 / alpha)
            let key = ((red >> 4) << 8) | ((green >> 4) << 4) | (blue >> 4)
            var bucket = buckets[key, default: Bucket()]
            bucket.count += 1
            bucket.red += red
            bucket.green += green
            bucket.blue += blue
            buckets[key] = bucket
        }
        guard let dominant = buckets.sorted(by: {
            $0.value.count == $1.value.count
                ? $0.key < $1.key
                : $0.value.count > $1.value.count
        }).first?.value, dominant.count > 0 else {
            return nil
        }
        return RGBColor(
            red: Double(dominant.red) / Double(dominant.count * 255),
            green: Double(dominant.green) / Double(dominant.count * 255),
            blue: Double(dominant.blue) / Double(dominant.count * 255)
        )
    }

    static func dominantColor(in samples: [RGBColor]) -> RGBColor? {
        guard !samples.isEmpty else { return nil }
        var buckets: [Int: Bucket] = [:]
        for sample in samples {
            let red = Int((sample.red * 255).rounded())
            let green = Int((sample.green * 255).rounded())
            let blue = Int((sample.blue * 255).rounded())
            let key = ((red >> 4) << 8) | ((green >> 4) << 4) | (blue >> 4)
            var bucket = buckets[key, default: Bucket()]
            bucket.count += 1
            bucket.red += red
            bucket.green += green
            bucket.blue += blue
            buckets[key] = bucket
        }
        guard let dominant = buckets.sorted(by: {
            $0.value.count == $1.value.count
                ? $0.key < $1.key
                : $0.value.count > $1.value.count
        }).first?.value else { return nil }
        return RGBColor(
            red: Double(dominant.red) / Double(dominant.count * 255),
            green: Double(dominant.green) / Double(dominant.count * 255),
            blue: Double(dominant.blue) / Double(dominant.count * 255)
        )
    }
}

struct NeonColorVariants: Equatable {
    var base: RGBColor
    var light: RGBColor
    var dark: RGBColor
}

enum NeonColorEngine {
    static func contrastRatio(_ first: RGBColor, _ second: RGBColor) -> Double {
        let luminances = [first.relativeLuminance, second.relativeLuminance].sorted(by: >)
        return (luminances[0] + 0.05) / (luminances[1] + 0.05)
    }

    static func ensureContrast(
        _ foreground: RGBColor,
        against background: RGBColor,
        minimumRatio: Double = 4.5
    ) -> RGBColor {
        let minimumRatio = minimumRatio.clamped(to: 1...21)
        guard contrastRatio(foreground, background) < minimumRatio else { return foreground }
        let hsl = foreground.hueSaturationLightness
        var best: RGBColor?
        var bestDistance = Double.infinity
        for step in 0...100 {
            for lightness in [Double(step) / 100, 1 - Double(step) / 100] {
                let candidate = RGBColor(hue: hsl.hue, saturation: hsl.saturation, lightness: lightness)
                guard contrastRatio(candidate, background) >= minimumRatio else { continue }
                let distance = abs(lightness - hsl.lightness)
                if distance < bestDistance {
                    best = candidate
                    bestDistance = distance
                }
            }
        }
        if let best { return best }
        let black = RGBColor(red: 0, green: 0, blue: 0)
        let white = RGBColor(red: 1, green: 1, blue: 1)
        return contrastRatio(black, background) >= contrastRatio(white, background) ? black : white
    }

    static func variants(
        dominant: RGBColor?,
        configuration: NeonConfiguration,
        lightBackground: RGBColor = RGBColor(red: 1, green: 1, blue: 1),
        darkBackground: RGBColor = RGBColor(red: 0.055, green: 0.063, blue: 0.078)
    ) -> NeonColorVariants? {
        guard let manual = RGBColor(hex: configuration.manualHex) else { return nil }
        let source: RGBColor
        switch configuration.mode {
        case .manual:
            source = manual
        case .automatic:
            source = dominant ?? manual
        case .hybrid:
            source = dominant ?? manual
        }
        var hsl = source.hueSaturationLightness
        if configuration.mode != .manual {
            let hueShift = configuration.mode == .automatic ? configuration.offsets.hue.clamped(to: 24...42) : configuration.offsets.hue
            hsl.hue += hueShift
            hsl.saturation = (hsl.saturation + configuration.offsets.saturation).clamped(to: 0.35...0.9)
            hsl.lightness = (hsl.lightness + configuration.offsets.brightness).clamped(to: 0.35...0.72)
        }
        let base = RGBColor(hue: hsl.hue, saturation: hsl.saturation, lightness: hsl.lightness)
        return NeonColorVariants(
            base: base,
            light: ensureContrast(base, against: lightBackground),
            dark: ensureContrast(base, against: darkBackground)
        )
    }

    static func applyingVariants(
        to configuration: NeonConfiguration,
        dominant: RGBColor?
    ) -> NeonConfiguration {
        guard let result = variants(dominant: dominant, configuration: configuration) else {
            return configuration.validated()
        }
        var copy = configuration.validated()
        copy.lightHex = result.light.hex
        copy.darkHex = result.dark.hex
        if copy.mode != .manual { copy.manualHex = result.base.hex }
        return copy
    }
}
