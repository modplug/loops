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
    float borderWidth;
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
    float borderWidth;
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
    out.borderWidth = inst.borderWidth;
    return out;
}

fragment float4 pg_rect_fragment(RectVertexOut in [[stage_in]]) {
    float4 color = in.color;
    float2 halfSize = in.rectSize * 0.5;

    if (in.cornerRadius > 0.0) {
        float maxRadius = max(0.0, min(halfSize.x, halfSize.y) - 0.001);
        float radius = min(in.cornerRadius, maxRadius);
        if (radius <= 0.0) {
            return color;
        }
        float2 center = halfSize;
        float2 d = abs(in.localPos - center) - halfSize + radius;
        float dist = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - radius;
        float outerAlpha = 1.0 - smoothstep(-0.5, 0.5, dist);

        if (in.borderWidth > 0.0) {
            float innerAlpha = smoothstep(-(in.borderWidth + 0.5), -(in.borderWidth - 0.5), dist);
            color.a *= outerAlpha * innerAlpha;
        } else {
            color.a *= outerAlpha;
        }
    } else if (in.borderWidth > 0.0) {
        float2 center = halfSize;
        float2 d = abs(in.localPos - center) - halfSize;
        float dist = max(d.x, d.y);
        float outerAlpha = 1.0 - smoothstep(-0.5, 0.5, dist);
        float innerAlpha = smoothstep(-(in.borderWidth + 0.5), -(in.borderWidth - 0.5), dist);
        color.a *= outerAlpha * innerAlpha;
    }

    return color;
}

struct LineVertexOut {
    float4 position [[position]];
    float4 color;
    float2 localPos;
    float halfWidth;
    float lineLength;
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
    float2 localPositions[4] = {
        float2(0.0, halfW),
        float2(0.0, -halfW),
        float2(len, halfW),
        float2(len, -halfW)
    };

    LineVertexOut out;
    out.position = uniforms.projectionMatrix * float4(positions[vertexID], 0, 1);
    out.color = inst.color;
    out.localPos = localPositions[vertexID];
    out.halfWidth = max(halfW, 0.5);
    out.lineLength = max(len, 0.001);
    return out;
}

fragment float4 pg_line_fragment(LineVertexOut in [[stage_in]]) {
    float sideDist = abs(in.localPos.y) - max(in.halfWidth - 0.5, 0.0);
    float capDist = max(-in.localPos.x, in.localPos.x - in.lineLength);
    float edgeDist = max(sideDist, capDist);
    float aa = max(fwidth(edgeDist), 0.35);
    float alpha = 1.0 - smoothstep(0.0, aa, edgeDist);
    float4 color = in.color;
    color.a *= alpha;
    return color;
}

struct WaveformVertexOut {
    float4 position [[position]];
    float4 color;
    float2 waveformUV;
    float amplitude;
    float asymmetry;
};

vertex WaveformVertexOut pg_waveform_vertex(
    uint vertexID [[vertex_id]],
    constant PlaybackGridUniforms &uniforms [[buffer(0)]],
    constant PlaybackGridWaveformParams &params [[buffer(1)]],
    constant float2 *allExtrema [[buffer(2)]]
) {
    uint peakCount = params.peakCount;
    uint peakIndex = vertexID / 2;
    bool isTop = (vertexID % 2) == 0;

    float t = peakCount > 0 ? (float(peakIndex) + 0.5) / float(peakCount) : 0.5;
    float x = params.containerOrigin.x + t * params.containerSize.x;
    float midY = params.containerOrigin.y + params.containerSize.y * 0.5;
    float halfHeight = params.containerSize.y * 0.5 * params.amplitude;

    float2 extrema = allExtrema[params.peakOffset + min(peakIndex, peakCount - 1)];
    float minValue = clamp(extrema.x, -1.0, 1.0);
    float maxValue = clamp(extrema.y, -1.0, 1.0);
    float amplitude = max(abs(minValue), abs(maxValue));
    float asymmetry = clamp((maxValue + minValue) * 0.5 + 0.5, 0.0, 1.0);
    float y = isTop ? midY - maxValue * halfHeight : midY - minValue * halfHeight;

    WaveformVertexOut out;
    out.position = uniforms.projectionMatrix * float4(x, y, 0, 1);
    out.color = params.fillColor;
    out.waveformUV = float2(t, isTop ? 0.0 : 1.0);
    out.amplitude = amplitude;
    out.asymmetry = asymmetry;
    return out;
}

fragment float4 pg_waveform_fragment(WaveformVertexOut in [[stage_in]]) {
    float centerDist = abs(in.waveformUV.y - 0.5) * 2.0;
    float center = 1.0 - centerDist;
    float amplitude = sqrt(clamp(in.amplitude, 0.0, 1.0));

    float edgeAA = max(fwidth(centerDist) * 1.2, 0.02);
    float bodyMask = 1.0 - smoothstep(1.0 - edgeAA, 1.0, centerDist);
    float innerLift = pow(max(center, 0.0), 1.15);
    float edgeShade = smoothstep(0.58, 0.98, centerDist) * bodyMask;

    float horizontalFade = smoothstep(0.0, 0.018, in.waveformUV.x)
        * smoothstep(0.0, 0.018, 1.0 - in.waveformUV.x);

    float3 base = in.color.rgb;
    float3 lifted = min(base + float3(0.03, 0.03, 0.035) + (0.03 * amplitude), float3(1.0));
    float3 shaded = max(base - float3(0.04, 0.04, 0.04), float3(0.0));

    float3 rgb = mix(shaded, lifted, 0.68 + (0.12 * innerLift));
    rgb = mix(rgb, base, 0.10 * edgeShade);

    float alpha = in.color.a;
    alpha *= bodyMask;
    alpha *= horizontalFade;
    alpha *= 0.90 + (0.10 * innerLift) + (0.05 * amplitude);

    return float4(rgb, alpha);
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
    float bodyMask = 1.0;
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
        bodyMask = 1.0 - smoothstep(-0.5, 0.5, dist);
        color.a *= bodyMask;
    }

    float width = max(in.rectSize.x, 1.0);
    float height = max(in.rectSize.y, 1.0);
    float2 uv = float2(in.localPos.x / width, in.localPos.y / height);
    float gloss = pow(max(1.0 - uv.y, 0.0), 1.7) * smoothstep(0.02, 0.3, uv.y);
    float centerLift = pow(max(1.0 - abs(uv.x - 0.5) * 2.0, 0.0), 1.25);
    float edgeShade = smoothstep(0.0, 0.12, uv.x) * smoothstep(0.0, 0.12, 1.0 - uv.x);

    float3 lifted = min(color.rgb + float3(0.05, 0.05, 0.06), float3(1.0));
    float3 glossColor = min(color.rgb + float3(0.14, 0.12, 0.14), float3(1.0));
    color.rgb = mix(color.rgb, lifted, 0.18 * centerLift);
    color.rgb = mix(color.rgb, glossColor, 0.18 * gloss * centerLift);
    color.a *= 0.92 + (0.08 * edgeShade);
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
