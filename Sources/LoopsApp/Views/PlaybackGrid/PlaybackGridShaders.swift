let playbackGridShaderSource = """
#include <metal_stdlib>
using namespace metal;

struct PlaybackGridUniforms {
    float4x4 projectionMatrix;
    float pixelsPerBar;
    float canvasHeight;
    float viewportMinX;
    float viewportMaxX;
};

struct PlaybackGridRectInstance {
    float2 origin;
    float2 size;
    float4 color;
    float cornerRadius;
};

struct PlaybackGridLineInstance {
    float2 start;
    float2 end;
    float4 color;
    float width;
};

struct PlaybackGridWaveformParams {
    float2 containerOrigin;
    float2 containerSize;
    float4 fillColor;
    uint peakOffset;
    uint peakCount;
    float amplitude;
};

struct PlaybackGridMIDINoteInstance {
    float2 origin;
    float2 size;
    float4 color;
    float cornerRadius;
};

struct PlaybackGridFadeVertex {
    float2 position;
    float4 color;
};

struct RectVertexOut {
    float4 position [[position]];
    float4 color;
    float2 localPos;
    float2 rectSize;
    float cornerRadius;
};

vertex RectVertexOut pg_rect_vertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    constant PlaybackGridUniforms &uniforms [[buffer(0)]],
    constant PlaybackGridRectInstance *instances [[buffer(1)]]
) {
    float2 unitQuad[4] = {
        float2(0, 0), float2(1, 0),
        float2(0, 1), float2(1, 1)
    };

    PlaybackGridRectInstance inst = instances[instanceID];
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

fragment float4 pg_rect_fragment(RectVertexOut in [[stage_in]]) {
    float4 color = in.color;

    if (in.cornerRadius > 0.0) {
        float2 halfSize = in.rectSize * 0.5;
        float maxRadius = max(0.0, min(halfSize.x, halfSize.y) - 0.001);
        float radius = min(in.cornerRadius, maxRadius);
        if (radius <= 0.0) {
            return color;
        }
        float2 center = halfSize;
        float2 d = abs(in.localPos - center) - halfSize + radius;
        float dist = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - radius;
        float alpha = 1.0 - smoothstep(-0.5, 0.5, dist);
        color.a *= alpha;
    }

    return color;
}

struct LineVertexOut {
    float4 position [[position]];
    float4 color;
};

vertex LineVertexOut pg_line_vertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    constant PlaybackGridUniforms &uniforms [[buffer(0)]],
    constant PlaybackGridLineInstance *instances [[buffer(1)]]
) {
    PlaybackGridLineInstance inst = instances[instanceID];
    float2 dir = inst.end - inst.start;
    float len = length(dir);
    float2 norm = len > 0.0001 ? float2(-dir.y, dir.x) / len : float2(0, 1);
    float halfW = inst.width * 0.5;

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

fragment float4 pg_line_fragment(LineVertexOut in [[stage_in]]) {
    return in.color;
}

struct WaveformVertexOut {
    float4 position [[position]];
    float4 color;
};

vertex WaveformVertexOut pg_waveform_vertex(
    uint vertexID [[vertex_id]],
    constant PlaybackGridUniforms &uniforms [[buffer(0)]],
    constant PlaybackGridWaveformParams &params [[buffer(1)]],
    constant float *allPeaks [[buffer(2)]]
) {
    uint peakCount = params.peakCount;
    uint peakIndex = vertexID / 2;
    bool isTop = (vertexID % 2) == 0;

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

fragment float4 pg_waveform_fragment(WaveformVertexOut in [[stage_in]]) {
    return in.color;
}

struct MIDIVertexOut {
    float4 position [[position]];
    float4 color;
    float2 localPos;
    float2 rectSize;
    float cornerRadius;
};

vertex MIDIVertexOut pg_midi_vertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    constant PlaybackGridUniforms &uniforms [[buffer(0)]],
    constant PlaybackGridMIDINoteInstance *instances [[buffer(1)]]
) {
    PlaybackGridMIDINoteInstance inst = instances[instanceID];
    float2 unitQuad[4] = {
        float2(0, 0), float2(1, 0),
        float2(0, 1), float2(1, 1)
    };
    float2 uv = unitQuad[vertexID];
    float2 worldPos = inst.origin + uv * inst.size;

    MIDIVertexOut out;
    out.position = uniforms.projectionMatrix * float4(worldPos, 0, 1);
    out.color = inst.color;
    out.localPos = uv * inst.size;
    out.rectSize = inst.size;
    out.cornerRadius = inst.cornerRadius;
    return out;
}

fragment float4 pg_midi_fragment(MIDIVertexOut in [[stage_in]]) {
    float4 color = in.color;
    if (in.cornerRadius > 0.0) {
        float2 halfSize = in.rectSize * 0.5;
        float maxRadius = max(0.0, min(halfSize.x, halfSize.y) - 0.001);
        float radius = min(in.cornerRadius, maxRadius);
        if (radius <= 0.0) {
            return color;
        }
        float2 center = halfSize;
        float2 d = abs(in.localPos - center) - halfSize + radius;
        float dist = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - radius;
        float alpha = 1.0 - smoothstep(-0.5, 0.5, dist);
        color.a *= alpha;
    }
    return color;
}

struct FadeVertexOut {
    float4 position [[position]];
    float4 color;
};

vertex FadeVertexOut pg_fade_vertex(
    uint vertexID [[vertex_id]],
    constant PlaybackGridUniforms &uniforms [[buffer(0)]],
    constant PlaybackGridFadeVertex *vertices [[buffer(1)]]
) {
    PlaybackGridFadeVertex v = vertices[vertexID];
    FadeVertexOut out;
    out.position = uniforms.projectionMatrix * float4(v.position, 0, 1);
    out.color = v.color;
    return out;
}

fragment float4 pg_fade_fragment(FadeVertexOut in [[stage_in]]) {
    return in.color;
}
"""
