#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float paddedX;
    float paddedY;
    float paddedW;
    float paddedH;
    float smoothFactor;
    int rectCount;
    int myIndex;
    vec4 color;
    int hasInverted;
    float invertedRadius;
    int cutoutIndex;
    float fieldPadding;
    vec4 invertedOuter;
    vec4 invertedInner;
    vec4 rectData[80];
    vec4 shadowColor;
    vec4 shadowData;
};

float sdRoundedBox(vec2 p, vec2 center, vec2 halfSize, float radius) {
    vec2 d = abs(p - center) - halfSize + vec2(radius);
    return length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0) - radius;
}

float sdRoundedBox4(vec2 p, vec2 center, vec2 halfSize, vec4 r) {
    // r = (topRight, bottomRight, bottomLeft, topLeft)
    p -= center;
    r.xy = (p.x > 0.0) ? r.xy : r.wz;
    r.x  = (p.y > 0.0) ? r.y : r.x;
    vec2 q = abs(p) - halfSize + r.x;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r.x;
}

float sdBox(vec2 p, vec2 center, vec2 halfSize) {
    vec2 d = abs(p - center) - halfSize;
    return length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0);
}

float liquidDistance(vec2 p, vec2 halfSize, vec4 radii, float kind) {
    if (kind > 1.5) {
        // Union of circles whose radius changes linearly along the filament.
        // Minimise distance-to-circle along the segment analytically.
        float span = max(radii.z, 0.0001);
        float slope = clamp((radii.y - radii.x) / span, -0.9999, 0.9999);
        vec2 q = p + vec2(0.0, span * 0.5);
        float t = clamp(q.y + slope * abs(q.x) / sqrt(1.0 - slope * slope), 0.0, span);
        return length(q - vec2(0.0, t)) - mix(radii.x, radii.y, t / span);
    }
    if (kind > 0.5) {
        // Gradient-corrected ellipse distance preserves its curved silhouette
        // while the falling drop stretches without changing its area.
        vec2 axes = max(halfSize, vec2(0.001));
        float k0 = length(p / axes);
        float k1 = length(p / (axes * axes));
        return k1 > 0.00001 ? k0 * (k0 - 1.0) / k1 : -min(axes.x, axes.y);
    }
    return sdRoundedBox4(p, vec2(0.0), halfSize, radii);
}

float liquidMin(float a, float b, float k) {
    float h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * h * k / 6.0;
}

float smin(float a, float b, float k) {
    // Circular smooth min — the blend fillet is a true circular arc of radius k,
    // tangent to both surfaces (not a polynomial/squircle curve). Deviates from
    // min(a, b) only in the corner region where BOTH a < k and b < k (unlike the
    // cubic it replaced, which deviated over the whole band |a - b| < k). Always
    // <= min(a, b); max blend depth at a == b is (sqrt(2) - 1) * k. It is C1 but
    // not C2 at the support boundary, so a circular-arc fillet shows the usual
    // line-meets-arc curvature step — by design, that is the "circular" look.
    return max(k, min(a, b)) - length(max(vec2(k) - vec2(a, b), vec2(0.0)));
}

float smax(float a, float b, float k) {
    // Circular smooth max — dual of smin: -smin(-a, -b, k). Always >= max(a, b).
    return min(-k, max(a, b)) + length(max(vec2(a, b) + vec2(k), vec2(0.0)));
}

float smaxSharpA(float a, float b, float k) {
    // Circular smax variant that keeps a's boundary sharp (no inward rounding at
    // a = 0). Used for the frame outer edge so it always fills to the edges.
    float sm = min(-k, max(a, b)) + length(max(vec2(a, b) + vec2(k), vec2(0.0)));
    float blend = (sm - max(a, b)) * smoothstep(0.0, k * 0.5, -a);
    return max(a, b) + blend;
}

void main() {
    vec2 pixel = vec2(paddedX, paddedY) + qt_TexCoord0 * vec2(paddedW, paddedH);
    float hostCoverage = 0.0;
    if (myIndex == -3 && rectCount > 0) {
        vec4 host = rectData[0];
        vec4 invHost = rectData[2];
        vec2 hostPoint = mat2(invHost.xy, invHost.zw) * (pixel - host.xy);
        float hostSdf = liquidDistance(hostPoint, host.zw, rectData[4], rectData[3].z) * rectData[1].w;
        float hostFw = max(fwidth(hostSdf), 0.001);
        // The real window keeps rendering its interior. Do not spend the
        // liquid pass on pixels wholly inside it, or composite them twice.
        if (hostSdf < -2.0 * hostFw) discard;
        hostCoverage = 1.0 - smoothstep(-hostFw, hostFw, hostSdf);
    }

    // Phase 1: compute per-rect SDF, track owner. We can't smin yet because excluded
    // pairs need to skip the smooth blend, which requires pairwise pass below.
    float dArr[16];
    int owner = -2;
    float minDist = 1e10;

    for (int i = 0; i < rectCount; i++) {
        vec4 rect = rectData[i * 5];         // cx, cy, hw, hh
        vec4 props = rectData[i * 5 + 1];    // excludeMask(int bits), offsetX, offsetY, minEig
        vec4 invDm = rectData[i * 5 + 2];    // inverse deform matrix
        vec4 sh = rectData[i * 5 + 3];       // screenHalfX, screenHalfY, 0, 0
        vec4 radii = rectData[i * 5 + 4];    // effective per-corner radii (tr, br, bl, tl)

        // Offset center for asymmetric deformation
        vec2 center = rect.xy + props.yz;

        // AABB early-out: skip rects far from this pixel
        vec2 extent = sh.xy + vec2(max(smoothFactor * 1.5, shadowData.x + abs(shadowData.y)));
        // A whole field spans the space between the globs. Replacing a
        // distance by infinity there corrupts fwidth and paints AABB-shaped
        // streaks, so that path evaluates the actual continuous distance.
        if (myIndex != -3 && (abs(pixel.x - center.x) > extent.x || abs(pixel.y - center.y) > extent.y)) {
            dArr[i] = 1e10;
            continue;
        }

        // Apply pre-computed inverse deformation to the evaluation point
        mat2 invDeform = mat2(invDm.xy, invDm.zw);
        vec2 transformedPixel = center + invDeform * (pixel - center);

        // Use pre-computed effective per-corner radii
        float d = myIndex == -3 ? liquidDistance(transformedPixel - center, rect.zw, radii, sh.z)
            : sdRoundedBox4(transformedPixel, center, rect.zw, radii);

        // Use pre-computed minimum eigenvalue for SDF correction
        d *= max(props.w, 0.01);

        // Scale SDF on the axis facing a nearby border to narrow the smin blend zone
        // in that direction only, without reducing k (which would cause sharp edges).
        if (hasInverted != 0) {
            vec2 screenHalf = sh.xy;

            float distY0 = (center.y + screenHalf.y) - (invertedInner.y - invertedInner.w);
            float distY1 = (invertedInner.y + invertedInner.w) - (center.y - screenHalf.y);
            float distX0 = (center.x + screenHalf.x) - (invertedInner.x - invertedInner.z);
            float distX1 = (invertedInner.x + invertedInner.z) - (center.x - screenHalf.x);

            // 0 = far from border, 1 = at border (max compression)
            float yProx = 1.0 - min(
                smoothstep(0.0, smoothFactor, distY0),
                smoothstep(0.0, smoothFactor, distY1)
            );
            float xProx = 1.0 - min(
                smoothstep(0.0, smoothFactor, distX0),
                smoothstep(0.0, smoothFactor, distX1)
            );

            // Smooth axis weights: gradient-based at corners, face-based inside.
            vec2 q = abs(pixel - center) - screenHalf;
            vec2 qp = max(q, vec2(0.0));
            float cornerLen = length(qp);

            // Gradient direction in corner region (smooth 90-degree rotation)
            float gradX = qp.x / max(cornerLen, 0.001);
            float gradY = qp.y / max(cornerLen, 0.001);

            // Smooth face weights for inside/edge (no hard branch)
            float faceY = smoothstep(-4.0, 4.0, q.y - q.x);
            float faceX = 1.0 - faceY;

            // Blend: gradient in corner region, face-based inside
            float t = smoothstep(0.0, 2.0, cornerLen);
            float xWeight = mix(faceX, gradX, t);
            float yWeight = mix(faceY, gradY, t);

            float boost = 3.0;
            float scale = 1.0 + (xProx * xWeight + yProx * yWeight) * boost;
            d *= scale;
        }

        dArr[i] = d;
        if (d < max(smoothFactor, shadowData.x + abs(shadowData.y)) && d < minDist) {
            minDist = d;
            owner = i;
        }
    }

    // Phase 2: hard-min baseline over all rects.
    float mergedSdf = 1e10;
    for (int i = 0; i < rectCount; i++) {
        mergedSdf = min(mergedSdf, dArr[i]);
    }

    if (myIndex == -3) {
        // There are no pair exclusions in the liquid field. A fixed-order
        // union is linear in the drop count and keeps the necks continuous.
        mergedSdf = dArr[0];
        for (int i = 1; i < rectCount; i++)
            mergedSdf = liquidMin(mergedSdf, dArr[i], smoothFactor);
    }

    // Phase 3: pair-wise smin contributions, skipping excluded pairs. Pair smin <= min,
    // so taking the min over all non-excluded pair smins gives the smoothly-merged SDF.
    for (int i = 0; myIndex != -3 && i < rectCount; i++) {
        if (dArr[i] >= 1e9)
            continue;
        int excludeMask = floatBitsToInt(rectData[i * 5 + 1].x);
        for (int j = i + 1; j < rectCount; j++) {
            if (dArr[j] >= 1e9)
                continue;
            if ((excludeMask & (1 << j)) != 0)
                continue;
            // Circular smin deviates from min only where BOTH dArr are < smoothFactor.
            if (max(dArr[i], dArr[j]) >= smoothFactor)
                continue;
            mergedSdf = min(mergedSdf, smin(dArr[i], dArr[j], smoothFactor));
        }
    }

    if (hasInverted != 0) {
        float dOuter = sdBox(pixel, invertedOuter.xy, invertedOuter.zw) - 1.0;
        float dInner = sdRoundedBox(pixel, invertedInner.xy, invertedInner.zw, invertedRadius);

        // Border sinks: track the opposite rect edge, clamped to border thickness
        float innerTop = invertedInner.y - invertedInner.w;
        float innerBot = invertedInner.y + invertedInner.w;
        float innerLeft = invertedInner.x - invertedInner.z;
        float innerRight = invertedInner.x + invertedInner.z;
        float outerTop = invertedOuter.y - invertedOuter.w;
        float outerBot = invertedOuter.y + invertedOuter.w;
        float outerLeft = invertedOuter.x - invertedOuter.z;
        float outerRight = invertedOuter.x + invertedOuter.z;

        float sinkValue = 0.0;
        for (int i = 0; i < rectCount; i++) {
            vec4 rect = rectData[i * 5];
            vec4 sinkProps = rectData[i * 5 + 1];
            vec2 sinkSh = rectData[i * 5 + 3].xy;

            // Screen-space center (with offset) and pre-computed AABB half-extents
            vec2 ctr = rect.xy + sinkProps.yz;

            // Sink onset / residual overlap: how far a rect must penetrate the border before
            // the inner wall recedes to form its pocket. Too low and the wall recedes faster
            // than the junction can stay convex, denting the inner edge inward near the rect's
            // (squared) corners; too high and the rect nestles too deep before the wall yields.
            // Tuned between the old cubic blend depth (k/6, too shallow) and the circular blend
            // depth ((sqrt2-1)k): half the circular smin gap-closing distance, (2-sqrt2)k/2.
            float preOff = smoothFactor * (2.0 - sqrt(2.0)) * 0.5;

            // Top border: track rect's BOTTOM edge, only within border thickness
            float topPen = clamp(innerTop - (ctr.y + sinkSh.y) - preOff, 0.0, innerTop - outerTop);

            // Bottom border: track rect's TOP edge
            float botPen = clamp((ctr.y - sinkSh.y) - innerBot - preOff, 0.0, outerBot - innerBot);

            // Left border: track rect's RIGHT edge
            float leftPen = clamp(innerLeft - (ctr.x + sinkSh.x) - preOff, 0.0, innerLeft - outerLeft);

            // Right border: track rect's LEFT edge
            float rightPen = clamp((ctr.x - sinkSh.x) - innerRight - preOff, 0.0, outerRight - innerRight);

            // Lateral distance from pixel to rect's extent along each edge
            float hLat = max(abs(pixel.x - ctr.x) - sinkSh.x, 0.0);
            float vLat = max(abs(pixel.y - ctr.y) - sinkSh.y, 0.0);

            // Perpendicular proximity: full strength in border, fade inside inner area
            float topZone = 1.0 - smoothstep(innerTop, innerTop + smoothFactor, pixel.y);
            float botZone = smoothstep(innerBot - smoothFactor, innerBot, pixel.y);
            float leftZone = 1.0 - smoothstep(innerLeft, innerLeft + smoothFactor, pixel.x);
            float rightZone = smoothstep(innerRight - smoothFactor, innerRight, pixel.x);

            float s = smoothFactor * 2.0;
            float sink = max(
                max(topPen * smoothstep(s, 0.0, hLat) * topZone,
                    botPen * smoothstep(s, 0.0, hLat) * botZone),
                max(leftPen * smoothstep(s, 0.0, vLat) * leftZone,
                    rightPen * smoothstep(s, 0.0, vLat) * rightZone)
            );
            sinkValue = max(sinkValue, sink);
        }

        dInner -= sinkValue;

        // The circular smax fillet has radius kFrame; when it exceeds the border thickness
        // it can't complete inside the border, so the sharp outer-box term bleeds onto the
        // inner edge and bulges the inner corners (worst when thickness < smoothFactor — the
        // default border is thinner than the blend radius). Clamp kFrame to the thinnest side
        // so the inner edge stays a clean constant-radius arc. Each inner corner is bounded by
        // its thinner adjacent side, so the global min is correct for every corner.
        float minThick = min(min(innerTop - outerTop, outerBot - innerBot),
                             min(innerLeft - outerLeft, outerRight - innerRight));
        float kFrame = clamp(min(smoothFactor, minThick - 1.0), 1.0, smoothFactor);
        float dFrame = smaxSharpA(dOuter, -dInner, kFrame);

        mergedSdf = smin(mergedSdf, dFrame, smoothFactor);
        if (dFrame < minDist) {
            owner = -1;
        }
    }

    // Each renderer only outputs pixels it owns, but allow rendering
    // blend zones to prevent gaps (mergedSdf < smoothFactor means in blend)
    // myIndex == -1: inverted rect renders border-owned pixels
    // myIndex >= 0: individual rect renders its owned pixels
    if (myIndex != -3 && owner != myIndex && mergedSdf > smoothFactor)
        discard;

    float fw = fwidth(mergedSdf);
    vec2 gradient = vec2(dFdx(mergedSdf), dFdy(mergedSdf));
    float sceneStep = max(length(vec2(dFdx(pixel.x), dFdy(pixel.x))), 0.001);
    float yDirection = sign(dFdy(pixel.y));
    float alpha = 1.0 - smoothstep(-fw, fw, mergedSdf);
    if (myIndex == -3) {
        // Add only the missing coverage. A simple cutout paints the host's
        // antialiasing fringe a second time and creates a bright outline,
        // especially on translucent surfaces.
        alpha = max(0.0, alpha - hostCoverage) / max(1.0 - hostCoverage * qt_Opacity, 0.0001);
    } else if (cutoutIndex >= 0 && cutoutIndex < rectCount)
        // Overlap the host's antialiasing fringe. Complementary half-alpha
        // edges otherwise leave a dark seam where the fluid meets the control.
        alpha *= smoothstep(-2.0 * fw, -fw, dArr[cutoutIndex]);
    float shadowAlpha = 0.0;
    if (shadowColor.a > 0.0 && shadowData.x > 0.0 && owner == myIndex) {
        // Gaussian edge profile from the already-computed distance field.
        // This avoids rerendering and blurring a fullscreen texture for each
        // moving drawer, especially costly while an idle GPU wakes up.
        float sigma = max(shadowData.x / 3.0, 0.5);
        // Normalize distance where the border blend compresses its gradient.
        // Keep the downward offset consistent across OpenGL/Vulkan Y axes.
        float gradientLength = max(length(gradient), 0.001);
        float distance = mergedSdf * sceneStep / gradientLength
            - shadowData.y * gradient.y * yDirection / gradientLength;
        float x = distance / (sigma * sqrt(2.0));
        float t = 1.0 / (1.0 + 0.3275911 * abs(x));
        float erfc = (((((1.061405429*t - 1.453152027)*t) + 1.421413741)*t
                       - 0.284496736)*t + 0.254829592)*t * exp(-x*x);
        if (x < 0.0) erfc = 2.0 - erfc;
        shadowAlpha = 0.5 * erfc * shadowColor.a * (1.0 - alpha);
    }
    fragColor = vec4(color.rgb * alpha + shadowColor.rgb * shadowAlpha,
                     alpha + shadowAlpha) * qt_Opacity;
}
