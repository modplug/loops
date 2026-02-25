import simd

// MARK: - Per-Frame Uniforms

/// Passed to all shaders each frame. Provides the orthographic projection
/// and viewport bounds for vertex-stage culling.
struct TimelineUniforms {
    var projectionMatrix: simd_float4x4
    var pixelsPerBar: Float
    var canvasHeight: Float
    var viewportMinX: Float
    var viewportMaxX: Float
}

// MARK: - Instanced Rect

/// A single filled rectangle — used for grid bar shading, track backgrounds,
/// container fills, range selection overlays, and crossfade backgrounds.
struct RectInstance {
    var origin: SIMD2<Float>
    var size: SIMD2<Float>
    var color: SIMD4<Float>
    var cornerRadius: Float

    init(origin: SIMD2<Float>, size: SIMD2<Float>, color: SIMD4<Float>, cornerRadius: Float = 0) {
        self.origin = origin
        self.size = size
        self.color = color
        self.cornerRadius = cornerRadius
    }
}

// MARK: - Instanced Line

/// A single line segment — used for grid bar lines, beat lines, track separators,
/// crossfade X-patterns, and range selection edges.
struct LineInstance {
    var start: SIMD2<Float>
    var end: SIMD2<Float>
    var color: SIMD4<Float>
    var width: Float
}

// MARK: - Waveform Parameters

/// Per-container waveform draw parameters. Points into the shared peak buffer.
struct WaveformParams {
    var containerOrigin: SIMD2<Float>
    var containerSize: SIMD2<Float>
    var fillColor: SIMD4<Float>
    var peakOffset: UInt32
    var peakCount: UInt32
    var amplitude: Float
}

// MARK: - MIDI Diamond Instance

/// A single MIDI note rendered as a diamond shape.
struct MIDINoteInstance {
    var center: SIMD2<Float>
    var halfSize: Float
    var color: SIMD4<Float>
}

// MARK: - Fade Vertex

/// A vertex in a fade overlay polygon (generated on CPU).
struct FadeVertex {
    var position: SIMD2<Float>
    var color: SIMD4<Float>
}

// MARK: - Orthographic Projection

extension TimelineUniforms {
    /// Creates an orthographic projection matrix mapping an arbitrary rect to NDC.
    /// For a flipped coordinate system (isFlipped=true), pass top < bottom
    /// so that Y=top maps to NDC +1 (top of screen) and Y=bottom maps to NDC -1.
    static func orthographic(left: Float, right: Float, top: Float, bottom: Float) -> simd_float4x4 {
        let invWidth = 1.0 / (right - left)
        let invHeight = 1.0 / (top - bottom)
        return simd_float4x4(columns: (
            SIMD4<Float>(2.0 * invWidth, 0, 0, 0),
            SIMD4<Float>(0, 2.0 * invHeight, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(-(right + left) * invWidth, -(top + bottom) * invHeight, 0, 1)
        ))
    }
}
