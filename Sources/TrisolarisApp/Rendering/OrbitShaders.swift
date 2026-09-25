enum OrbitShaders {
    // Compiled by Metal at runtime, so a SwiftPM executable needs no metallib bundle lookup.
    static let source = #"""
    #include <metal_stdlib>
    using namespace metal;

    struct SceneUniforms {
        float4x4 viewProjection;
        float4x4 view;
        float4x4 projection;
        float4 viewport; // width, height, backing scale, time
    };
    struct LineVertex { float4 position; float4 color; };
    struct BodyInstance { float4 centerRadius; float4 colorKind; float4 lightSelected; };
    struct VertexOut { float4 position [[position]]; float4 color; };
    struct BackgroundOut { float4 position [[position]]; float2 uv; };
    struct BodyOut {
        float4 position [[position]];
        float2 uv;
        float3 center [[flat]];
        float radius [[flat]];
        float4 colorKind [[flat]];
        float4 lightSelected [[flat]];
        float pixelRadius [[flat]];
    };
    struct SphereFragment { float4 color [[color(0)]]; float depth [[depth(any)]]; };

    float hash21(float2 p) {
        p = fract(p * float2(123.34, 456.21));
        p += dot(p, p + 45.32);
        return fract(p.x * p.y);
    }

    vertex BackgroundOut background_vertex(uint index [[vertex_id]]) {
        const float2 positions[3] = { float2(-1,-1), float2(3,-1), float2(-1,3) };
        BackgroundOut out;
        out.position = float4(positions[index], 0.999999, 1);
        out.uv = positions[index] * 0.5 + 0.5;
        return out;
    }

    fragment float4 background_fragment(BackgroundOut in [[stage_in]],
                                        constant SceneUniforms& u [[buffer(1)]]) {
        float2 uv = in.uv;
        float aspect = u.viewport.x / max(u.viewport.y, 1.0f);
        float2 p = (uv - 0.5) * float2(aspect, 1);
        float3 color = mix(float3(0.008,0.014,0.036), float3(0.024,0.037,0.074), uv.y);
        float mist = exp(-length(p - float2(-0.34,0.15)) * 2.6);
        color += float3(0.016,0.027,0.041) * mist;
        // Two deterministic star layers, independent of simulation coordinates and time.
        for (int layer = 0; layer < 2; ++layer) {
            float spacing = layer == 0 ? 75.0 : 41.0;
            float2 cellCoord = uv * u.viewport.xy / spacing;
            float2 cell = floor(cellCoord);
            float seed = hash21(cell + float(layer) * 131.0);
            float2 offset = float2(hash21(cell + 3.0), hash21(cell + 9.0));
            float distance = length((fract(cellCoord) - offset) * spacing);
            float strength = step(0.57, seed) * pow(seed, 6.0);
            float star = exp(-distance * distance / (layer == 0 ? 1.0 : 0.42));
            color += mix(float3(0.31,0.44,0.64), float3(0.74,0.80,0.92), seed) * star * strength;
        }
        color *= 1.0 - 0.22 * smoothstep(0.25, 1.0, length(p));
        return float4(color, 1);
    }

    vertex VertexOut line_vertex(uint id [[vertex_id]],
                                  const device LineVertex* vertices [[buffer(0)]],
                                  constant SceneUniforms& u [[buffer(1)]]) {
        VertexOut out;
        out.position = u.viewProjection * vertices[id].position;
        out.color = vertices[id].color;
        return out;
    }
    fragment float4 line_fragment(VertexOut in [[stage_in]]) { return in.color; }

    BodyOut make_body(uint id, uint instance, const device BodyInstance* bodies,
                      constant SceneUniforms& u, float expansion, bool selection) {
        const float2 corners[6] = { float2(-1,-1), float2(1,-1), float2(-1,1),
                                    float2(-1,1), float2(1,-1), float2(1,1) };
        BodyInstance body = bodies[instance];
        float4 center = u.view * float4(body.centerRadius.xyz,1);
        float radius = body.centerRadius.w;
        float4 centerClip = u.projection * center;
        float unitsPerPixel = 2.0 * max(abs(centerClip.w), 0.000001f) /
                              max(u.projection[1][1] * u.viewport.y, 1.0f);
        float actualPixelRadius = radius / unitsPerPixel;
        float renderedRadius = radius * expansion;
        if (selection) renderedRadius = max(radius, unitsPerPixel * 5.0 * u.viewport.z) +
                                        unitsPerPixel * 8.0 * u.viewport.z;
        else if (expansion > 1.0) renderedRadius = max(renderedRadius, unitsPerPixel * 6.0 * u.viewport.z);
        BodyOut out;
        float2 corner = corners[id];
        out.position = u.projection * (center + float4(corner * renderedRadius,0,0));
        out.uv = corner;
        out.center = center.xyz;
        out.radius = radius;
        out.colorKind = body.colorKind;
        out.lightSelected = float4((u.view * float4(body.lightSelected.xyz,0)).xyz, body.lightSelected.w);
        out.pixelRadius = selection ? renderedRadius / unitsPerPixel : actualPixelRadius;
        return out;
    }
    vertex BodyOut sphere_vertex(uint id [[vertex_id]], uint instance [[instance_id]],
                                  const device BodyInstance* bodies [[buffer(0)]],
                                  constant SceneUniforms& u [[buffer(1)]]) {
        return make_body(id, instance, bodies, u, 1.0, false);
    }
    vertex BodyOut halo_vertex(uint id [[vertex_id]], uint instance [[instance_id]],
                                const device BodyInstance* bodies [[buffer(0)]],
                                constant SceneUniforms& u [[buffer(1)]]) {
        return make_body(id, instance, bodies, u, 4.0, false);
    }
    vertex BodyOut selection_vertex(uint id [[vertex_id]], uint instance [[instance_id]],
                                     const device BodyInstance* bodies [[buffer(0)]],
                                     constant SceneUniforms& u [[buffer(1)]]) {
        return make_body(id, instance, bodies, u, 1.0, true);
    }

    fragment SphereFragment sphere_fragment(BodyOut in [[stage_in]],
                                            constant SceneUniforms& u [[buffer(1)]]) {
        float r2 = dot(in.uv, in.uv);
        if (r2 > 1.0) discard_fragment();
        float3 normal = float3(in.uv, sqrt(max(0.0f, 1.0 - r2)));
        float3 base = in.colorKind.rgb;
        float3 color;
        if (in.colorKind.w > 0.5) {
            float granulation = sin(in.uv.x * 39.0 + sin(in.uv.y * 27.0)) *
                                sin(in.uv.y * 45.0 + cos(in.uv.x * 31.0));
            float limb = 0.60 + 0.40 * pow(normal.z, 0.6);
            color = mix(base, float3(1.0,0.98,0.90), 0.47 * pow(normal.z, 2.0));
            color *= limb * (0.985 + 0.015 * granulation);
        } else {
            float3 light = normalize(in.lightSelected.xyz + float3(0.00001,0,0));
            float diffuse = max(dot(normal, light), 0.0f);
            float longitude = atan2(normal.x, normal.z);
            float latitude = asin(normal.y);
            float terrain = sin(longitude * 7.0 + sin(latitude * 9.0)) *
                            sin(latitude * 12.0 + cos(longitude * 4.0));
            float3 surface = mix(base * 0.56, base, smoothstep(-0.3,0.45,terrain));
            float cloud = smoothstep(0.64,0.95, sin(longitude * 18.0 + latitude * 26.0) *
                                     sin(latitude * 16.0 - longitude * 3.0));
            surface = mix(surface, float3(0.72,0.86,0.91), cloud * 0.55);
            color = surface * (0.15 + diffuse * 0.85);
            color += float3(0.16,0.48,0.76) * pow(1.0-normal.z, 3.0) * 0.35;
        }
        float3 surface = in.center + normal * in.radius;
        float4 clip = u.projection * float4(surface,1);
        SphereFragment out;
        out.color = float4(color,1);
        out.depth = clip.z / clip.w;
        return out;
    }

    fragment float4 halo_fragment(BodyOut in [[stage_in]]) {
        float r = length(in.uv);
        if (r > 1.0) discard_fragment();
        float falloff = exp(-r * r * 7.0) * smoothstep(1.0,0.68,r);
        float strength = in.colorKind.w > 0.5 ? 0.33 : 0.055;
        return float4(in.colorKind.rgb, falloff * strength);
    }

    fragment float4 selection_fragment(BodyOut in [[stage_in]],
                                       constant SceneUniforms& u [[buffer(1)]]) {
        if (in.lightSelected.w < 0.5) discard_fragment();
        float r = length(in.uv);
        float width = 1.15 * u.viewport.z / max(in.pixelRadius,1.0f);
        float alpha = 1.0 - smoothstep(width * 0.5, width * 1.5, abs(r - 0.84));
        if (alpha < 0.01) discard_fragment();
        return float4(mix(in.colorKind.rgb,float3(0.82,0.94,1),0.62), alpha * 0.85);
    }
    """#
}
