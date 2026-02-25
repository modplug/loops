/// Metal shader source compiled at runtime via `device.makeLibrary(source:options:)`.
/// SPM doesn't compile `.metal` files, so we embed shaders as a Swift string constant.
/// One-time compilation cost (~50ms) at init, cached thereafter.
let timelineShaderSource = """
#include <metal_stdlib>
using namespace metal;

// ─────────────────────────────────────────────
// Shared types (must match Swift-side structs)
// ─────────────────────────────────────────────

struct TimelineUniforms {
    float4x4 projectionMatrix;
    float pixelsPerBar;
    float canvasHeight;
    float viewportMinX;
    float viewportMaxX;
};

struct RectInstance {
    float2 origin;
    float2 size;
    float4 color;
    float cornerRadius;
};

struct LineInstance {
    float2 start;
    float2 end;
    float4 color;
    float width;
};

struct WaveformParams {
    float2 containerOrigin;
    float2 containerSize;
    float4 fillColor;
    uint peakOffset;
    uint peakCount;
    float amplitude;
};

struct MIDINoteInstance {
    float2 center;
    float halfSize;
    float4 color;
};

struct FadeVertex {
    float2 position;
    float4 color;
};

// ─────────────────────────────────────────────
// Rect Shader (instanced unit quad)
// ─────────────────────────────────────────────

struct RectVertexOut {
    float4 position [[position]];
    float4 color;
    float2 localPos;   // position within the rect (0,0)-(size.x,size.y)
    float2 rectSize;
    float cornerRadius;
};

vertex RectVertexOut rect_vertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    constant TimelineUniforms &uniforms [[buffer(0)]],
    constant RectInstance *instances [[buffer(1)]]
) {
    // Unit quad: 0-TL, 1-TR, 2-BL, 3-BR (used with index buffer: 0,1,2, 2,1,3)
    float2 unitQuad[4] = {
        float2(0, 0), float2(1, 0),
        float2(0, 1), float2(1, 1)
    };

    RectInstance inst = instances[instanceID];
    float2 uv = unitQuad[vertexID];
    float2 worldPos = inst.origin + uv * inst.size;

    RectVertexOut out;
    out.position = uniforms.projectionMatrix * float4(worldPos, 0, 1);
    out.color = inst.color;
    out.localPos = uv * inst.size;
    out.rectSize = inst.size;
    out.cornerRadius = inst.cornerRadius;
    return out;
}

fragment float4 rect_fragment(RectVertexOut in [[stage_in]]) {
    float4 color = in.color;

    if (in.cornerRadius > 0.0) {
        // SDF-based rounded rect
        float2 halfSize = in.rectSize * 0.5;
        float2 center = halfSize;
        float2 d = abs(in.localPos - center) - halfSize + in.cornerRadius;
        float dist = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - in.cornerRadius;
        // Soft edge anti-aliasing
        float alpha = 1.0 - smoothstep(-0.5, 0.5, dist);
        color.a *= alpha;
    }

    return color;
}

// ─────────────────────────────────────────────
// Line Shader (instanced quad extrusion)
// ─────────────────────────────────────────────

struct LineVertexOut {
    float4 position [[position]];
    float4 color;
};

vertex LineVertexOut line_vertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    constant TimelineUniforms &uniforms [[buffer(0)]],
    constant LineInstance *instances [[buffer(1)]]
) {
    LineInstance inst = instances[instanceID];
    float2 dir = inst.end - inst.start;
    float len = length(dir);
    float2 norm = len > 0.0001 ? float2(-dir.y, dir.x) / len : float2(0, 1);
    float halfW = inst.width * 0.5;

    // 4 vertices: 0=start-left, 1=start-right, 2=end-left, 3=end-right
    float2 positions[4] = {
        inst.start + norm * halfW,
        inst.start - norm * halfW,
        inst.end   + norm * halfW,
        inst.end   - norm * halfW
    };

    LineVertexOut out;
    out.position = uniforms.projectionMatrix * float4(positions[vertexID], 0, 1);
    out.color = inst.color;
    return out;
}

fragment float4 line_fragment(LineVertexOut in [[stage_in]]) {
    return in.color;
}

// ─────────────────────────────────────────────
// Waveform Shader (triangle strip from peaks)
// ─────────────────────────────────────────────

struct WaveformVertexOut {
    float4 position [[position]];
    float4 color;
};

vertex WaveformVertexOut waveform_vertex(
    uint vertexID [[vertex_id]],
    constant TimelineUniforms &uniforms [[buffer(0)]],
    constant WaveformParams &params [[buffer(1)]],
    constant float *allPeaks [[buffer(2)]]
) {
    uint peakCount = params.peakCount;
    // Triangle strip: even vertices = top, odd vertices = bottom
    uint peakIndex = vertexID / 2;
    bool isTop = (vertexID % 2) == 0;

    // Map each peak to the CENTER of its cell (cell width = 1/peakCount of container).
    // This matches the CG path: peak i is at (i + 0.5) / N * width.
    // Using i/(N-1) would stretch peaks edge-to-edge, causing cumulative drift
    // between the visual waveform and audio playback position towards the end.
    float t = peakCount > 0 ? (float(peakIndex) + 0.5) / float(peakCount) : 0.5;
    float x = params.containerOrigin.x + t * params.containerSize.x;
    float midY = params.containerOrigin.y + params.containerSize.y * 0.5;
    float halfHeight = params.containerSize.y * 0.5 * params.amplitude;

    float peak = abs(allPeaks[params.peakOffset + min(peakIndex, peakCount - 1)]);
    float y = isTop ? midY - peak * halfHeight : midY + peak * halfHeight;

    WaveformVertexOut out;
    out.position = uniforms.projectionMatrix * float4(x, y, 0, 1);
    out.color = params.fillColor;
    return out;
}

fragment float4 waveform_fragment(WaveformVertexOut in [[stage_in]]) {
    return in.color;
}

// ─────────────────────────────────────────────
// MIDI Diamond Shader (instanced)
// ─────────────────────────────────────────────

struct MIDIVertexOut {
    float4 position [[position]];
    float4 color;
};

vertex MIDIVertexOut midi_vertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    constant TimelineUniforms &uniforms [[buffer(0)]],
    constant MIDINoteInstance *instances [[buffer(1)]]
) {
    MIDINoteInstance inst = instances[instanceID];

    // Diamond: top, right, bottom, left
    float2 offsets[4] = {
        float2(0, -inst.halfSize),
        float2(inst.halfSize, 0),
        float2(0, inst.halfSize),
        float2(-inst.halfSize, 0)
    };

    float2 worldPos = inst.center + offsets[vertexID];

    MIDIVertexOut out;
    out.position = uniforms.projectionMatrix * float4(worldPos, 0, 1);
    out.color = inst.color;
    return out;
}

fragment float4 midi_fragment(MIDIVertexOut in [[stage_in]]) {
    return in.color;
}

// ─────────────────────────────────────────────
// Fade Overlay Shader (pre-computed vertices)
// ─────────────────────────────────────────────

struct FadeVertexOut {
    float4 position [[position]];
    float4 color;
};

vertex FadeVertexOut fade_vertex(
    uint vertexID [[vertex_id]],
    constant TimelineUniforms &uniforms [[buffer(0)]],
    constant FadeVertex *vertices [[buffer(1)]]
) {
    FadeVertex v = vertices[vertexID];
    FadeVertexOut out;
    out.position = uniforms.projectionMatrix * float4(v.position, 0, 1);
    out.color = v.color;
    return out;
}

fragment float4 fade_fragment(FadeVertexOut in [[stage_in]]) {
    return in.color;
}
"""
