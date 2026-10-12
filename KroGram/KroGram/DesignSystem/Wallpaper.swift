import Foundation

enum BackgroundKind: String, Codable, CaseIterable, Identifiable {
    case solid, gradient, aurora, mesh, pattern, photo
    var id: String { rawValue }
}

enum BackgroundGradientKind: String, Codable, CaseIterable, Identifiable {
    case linear, radial, angular
    var id: String { rawValue }
}

enum BackgroundPatternKind: String, Codable, CaseIterable, Identifiable {
    case dots, lines, grid, geometric
    var id: String { rawValue }
}

struct MeshColorPoint: Codable, Equatable, Identifiable {
    var id: UUID
    var x: Double
    var y: Double
    var hex: String

    init(id: UUID = UUID(), x: Double, y: Double, hex: String) {
        self.id = id
        self.x = x
        self.y = y
        self.hex = hex
    }
}

struct BackgroundConfiguration: Codable, Equatable {
    var kind: BackgroundKind
    var solidHex: String
    var gradientHexes: [String]
    var gradientKind: BackgroundGradientKind
    var angle: Double
    var auroraBlobCount: Int
    var auroraSpeed: Double
    var auroraSize: Double
    var auroraBlur: Double
    var meshPoints: [MeshColorPoint]
    var pattern: BackgroundPatternKind
    var patternDensity: Double
    var patternOpacity: Double
    var photoID: UUID?
    var photoScale: Double
    var photoOffsetX: Double
    var photoOffsetY: Double
    var photoBlur: Double
    var photoDim: Double
    var photoSaturation: Double
    var parallaxEnabled: Bool

    init(
        kind: BackgroundKind = .gradient,
        solidHex: String = "F4F7FF",
        gradientHexes: [String] = ["192C59", "3B5D9A", "B8DDF0"],
        gradientKind: BackgroundGradientKind = .linear,
        angle: Double = 135,
        auroraBlobCount: Int = 4,
        auroraSpeed: Double = 0.25,
        auroraSize: Double = 0.8,
        auroraBlur: Double = 48,
        meshPoints: [MeshColorPoint] = [
            MeshColorPoint(x: 0.1, y: 0.15, hex: "203A73"),
            MeshColorPoint(x: 0.9, y: 0.1, hex: "673AB7"),
            MeshColorPoint(x: 0.15, y: 0.9, hex: "00A896"),
            MeshColorPoint(x: 0.9, y: 0.85, hex: "E76F51")
        ],
        pattern: BackgroundPatternKind = .dots,
        patternDensity: Double = 0.5,
        patternOpacity: Double = 0.16,
        photoID: UUID? = nil,
        photoScale: Double = 1,
        photoOffsetX: Double = 0,
        photoOffsetY: Double = 0,
        photoBlur: Double = 0,
        photoDim: Double = 0,
        photoSaturation: Double = 1,
        parallaxEnabled: Bool = false
    ) {
        self.kind = kind
        self.solidHex = solidHex
        self.gradientHexes = gradientHexes
        self.gradientKind = gradientKind
        self.angle = angle
        self.auroraBlobCount = auroraBlobCount
        self.auroraSpeed = auroraSpeed
        self.auroraSize = auroraSize
        self.auroraBlur = auroraBlur
        self.meshPoints = meshPoints
        self.pattern = pattern
        self.patternDensity = patternDensity
        self.patternOpacity = patternOpacity
        self.photoID = photoID
        self.photoScale = photoScale
        self.photoOffsetX = photoOffsetX
        self.photoOffsetY = photoOffsetY
        self.photoBlur = photoBlur
        self.photoDim = photoDim
        self.photoSaturation = photoSaturation
        self.parallaxEnabled = parallaxEnabled
    }

    static func migrated(from style: WallpaperStyle, accentHex: String) -> Self {
        switch style {
        case .plain:
            return Self(kind: .solid, solidHex: "F4F7FF")
        case .gradient:
            return Self(kind: .gradient, gradientHexes: [accentHex, "F4F7FF"])
        case .dots:
            return Self(kind: .pattern, solidHex: "F4F7FF", pattern: .dots)
        }
    }

    func validated() -> Self {
        var copy = self
        if !ThemeStore.isValidHex(copy.solidHex) { copy.solidHex = "F4F7FF" }
        copy.gradientHexes = Array(copy.gradientHexes.filter(ThemeStore.isValidHex).prefix(5))
        if copy.gradientHexes.count < 2 {
            copy.gradientHexes = ["192C59", "B8DDF0"]
        }
        copy.angle = angle.clamped(to: 0...360)
        copy.auroraBlobCount = auroraBlobCount.clamped(to: 2...8)
        copy.auroraSpeed = auroraSpeed.clamped(to: 0.05...1.0)
        copy.auroraSize = auroraSize.clamped(to: 0.25...1.5)
        copy.auroraBlur = auroraBlur.clamped(to: 0...120)
        copy.meshPoints = Array(meshPoints.prefix(16)).map { point in
            MeshColorPoint(
                id: point.id,
                x: point.x.clamped(to: 0...1),
                y: point.y.clamped(to: 0...1),
                hex: ThemeStore.isValidHex(point.hex) ? point.hex : "2F6BFF"
            )
        }
        copy.patternDensity = patternDensity.clamped(to: 0.1...1)
        copy.patternOpacity = patternOpacity.clamped(to: 0...0.5)
        copy.photoScale = photoScale.clamped(to: 1...3)
        copy.photoOffsetX = photoOffsetX.clamped(to: -1...1)
        copy.photoOffsetY = photoOffsetY.clamped(to: -1...1)
        copy.photoBlur = photoBlur.clamped(to: 0...100)
        copy.photoDim = photoDim.clamped(to: 0...0.8)
        copy.photoSaturation = photoSaturation.clamped(to: 0...2)
        return copy
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
