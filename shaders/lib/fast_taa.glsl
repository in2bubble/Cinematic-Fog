/* Cinematic Fog - fast_taa.glsl
Temporal antialiasing functions.

Javier Garduño - GNU Lesser General Public License v3.0
*/

vec4 convexHull(
    vec3 c, vec3 previous, vec3 up, vec3 down, vec3 left, vec3 right, 
    vec3 ul, vec3 ur, vec3 dl, vec3 dr) {

    // Variance
    vec3 sum = c + up + down + left + right + ul + ur + dl + dr;
    vec3 sum_sq =
        c * c +
        up * up +
        down * down +
        left * left +
        right * right +
        ul * ul +
        ur * ur +
        dl * dl +
        dr * dr;

    vec3 mean = sum * 0.1111111111111111; // 1 / 9
    vec3 variance = abs(sum_sq * 0.1111111111111111 - mean * mean); // Variance = E[x^2] - E[x]^2

    vec3 stdDev = sqrt(variance);
    vec3 minValid = mean - stdDev;
    vec3 maxValid = mean + stdDev;

    return vec4(clamp(previous, minValid, maxValid), distance(minValid, maxValid));
}

vec3 fastTaa(vec3 currentColor, vec2 texcoordPast) {
    // Skip history when the reprojection falls outside the screen
    if (clamp(texcoordPast, 0.0, 1.0) != texcoordPast) {
        return currentColor;
    } else {
        // Previous color
        vec3 previous = texture2DLod(colortex3, texcoordPast, 0.0).rgb;

        vec3 left = texture2DLod(colortex1, texcoord + vec2(-pixelSizeX, 0.0), 0.0).rgb;
        vec3 right = texture2DLod(colortex1, texcoord + vec2(pixelSizeX, 0.0), 0.0).rgb;
        vec3 down = texture2DLod(colortex1, texcoord + vec2(0.0, -pixelSizeY), 0.0).rgb;
        vec3 up = texture2DLod(colortex1, texcoord + vec2(0.0, pixelSizeY), 0.0).rgb;
        vec3 ul = texture2DLod(colortex1, texcoord + vec2(-pixelSizeX, pixelSizeY), 0.0).rgb;
        vec3 ur = texture2DLod(colortex1, texcoord + vec2(pixelSizeX, pixelSizeY), 0.0).rgb;
        vec3 dl = texture2DLod(colortex1, texcoord + vec2(-pixelSizeX, -pixelSizeY), 0.0).rgb;
        vec3 dr = texture2DLod(colortex1, texcoord + vec2(pixelSizeX, -pixelSizeY), 0.0).rgb;

        vec3 colorMax = max(max(max(left, right), down),max(up, max(ul, max(ur, max(dl, max(dr, currentColor))))));
	    vec3 colorMin = min(min(min(left, right), down),min(up, min(ul, min(ur, min(dl, min(dr, currentColor))))));

        // Clip 3
        vec4 previousClipped = convexHull(
            currentColor,
            previous,
            up,
            down,
            left,
            right,
            ul,
            ur,
            dl,
            dr
        );

        float ponderation = clamp((distance(colorMax, colorMin) - previousClipped.a) / previousClipped.a, 0.0, 1.0);

        #ifdef MOTION_BLUR
            float velocity = length(texcoord - texcoordPast) * 10.0;
            return mix(currentColor, previousClipped.rgb, clamp(0.99 - velocity - (smoothstep(0.0, 1.0, ponderation) * 0.33), 0.0, 1.0));
        #else
            return mix(currentColor, previousClipped.rgb, 0.99 - (smoothstep(0.0, 1.0, ponderation) * 0.33));
        #endif
    }
}

vec4 fastTaaDepth(vec4 currentColor, vec2 texcoordPast) {
    // Skip history when the reprojection falls outside the screen
    if (clamp(texcoordPast, 0.0, 1.0) != texcoordPast) {
        return currentColor;
    } else {
        // History sample
        vec4 previous = texture2DLod(colortex3, texcoordPast, 0.0);

        vec4 left = texture2DLod(colortex1, texcoord + vec2(-pixelSizeX, 0.0), 0.0);
        vec4 right = texture2DLod(colortex1, texcoord + vec2(pixelSizeX, 0.0), 0.0);
        vec4 down = texture2DLod(colortex1, texcoord + vec2(0.0, -pixelSizeY), 0.0);
        vec4 up = texture2DLod(colortex1, texcoord + vec2(0.0, pixelSizeY), 0.0);
        vec4 ul = texture2DLod(colortex1, texcoord + vec2(-pixelSizeX, pixelSizeY), 0.0);
        vec4 ur = texture2DLod(colortex1, texcoord + vec2(pixelSizeX, pixelSizeY), 0.0);
        vec4 dl = texture2DLod(colortex1, texcoord + vec2(-pixelSizeX, -pixelSizeY), 0.0);
        vec4 dr = texture2DLod(colortex1, texcoord + vec2(pixelSizeX, -pixelSizeY), 0.0);

        vec3 colorMax = max(max(max(left.rgb, right.rgb), down.rgb),max(up.rgb, max(ul.rgb, max(ur.rgb, max(dl.rgb, max(dr.rgb, currentColor.rgb))))));
	    vec3 colorMin = min(min(min(left.rgb, right.rgb), down.rgb),min(up.rgb, min(ul.rgb, min(ur.rgb, min(dl.rgb, min(dr.rgb, currentColor.rgb))))));

        // Clip 3
        vec4 previousClipped = convexHull(
            currentColor.rgb,
            previous.rgb,
            up.rgb,
            down.rgb,
            left.rgb,
            right.rgb,
            ul.rgb,
            ur.rgb,
            dl.rgb,
            dr.rgb
        );

        float ponderation = clamp((distance(colorMax, colorMin) - previousClipped.a) / previousClipped.a, 0.0, 1.0);

        #ifdef MOTION_BLUR
            float velocity = length(texcoord - texcoordPast) * 10.0;
            return mix(currentColor, vec4(previousClipped.rgb, previous.a), clamp(0.99 - velocity - (smoothstep(0.0, 1.0, ponderation) * 0.33), 0.0, 1.0));
        #else
            return mix(currentColor, vec4(previousClipped.rgb, previous.a), 0.99 - (smoothstep(0.0, 1.0, ponderation) * 0.33));
        #endif
    }
}
