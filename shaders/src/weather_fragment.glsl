/*
 * Water-like rain shading.
 *
 * The source texture remains the coverage mask, so resource packs and
 * Minecraft's precipitation density still work.  Blue source texels identify
 * rain; white snow texels retain the shader's original snow treatment.
 */

float rainParticleMask = smoothstep(
    0.18,
    0.38,
    weatherTexel.b - weatherTexel.r
);

vec2 rainLocalUV = fract(texcoord);
float rainAcross = abs(rainLocalUV.x * 2.0 - 1.0);
float rainCore = pow(max(1.0 - rainAcross, 0.0), 2.4);
float rainRim = pow(rainAcross, 5.0);

// The moving vanilla UVs carry these small beads down each long streak.
float rainBeadWave =
    0.5 + 0.5 * sin((rainLocalUV.y * 5.0 + rainLocalUV.x * 1.7) * 6.2831853);
float rainBead = 0.76 + 0.24 * rainBeadWave * rainBeadWave;

float rainNearFade = smoothstep(0.75, 3.5, gl_FogFragCoord);
float rainFarFade = 1.0 - smoothstep(42.0, 78.0, gl_FogFragCoord);
float rainVisibility = mix(
    0.50,
    RAIN_OPACITY * rainBead *
        mix(0.62, 1.0, rainCore) *
        mix(0.82, 1.0, rainNearFade) *
        mix(1.0, 0.72, 1.0 - rainFarFade),
    rainParticleMask
);

blockColor.a *= rainVisibility;

vec2 rainScreenUV =
    gl_FragCoord.xy * vec2(pixelSizeX, pixelSizeY);
vec2 rainRefractionOffset =
    vec2(
        (rainLocalUV.x - 0.5) * pixelSizeX * 5.0,
        weatherWindView.x * pixelSizeY * 2.0
    );
vec3 rainEnvironment = texture2D(
    gaux1,
    clamp(rainScreenUV + rainRefractionOffset, vec2(0.002), vec2(0.998))
).rgb;

float rainMirrorBand = pow(
    max(1.0 - abs(rainLocalUV.x - 0.34) * 11.0, 0.0),
    3.0
);
float rainGlint =
    rainMirrorBand * (0.72 + weatherCameraResponse * 0.28) +
    rainRim * 0.22;

vec3 rainWaterBody = mix(
    vec3(0.105, 0.165, 0.225),
    max(rainEnvironment, vec3(0.035, 0.055, 0.080)),
    0.58
);
vec3 rainMirrorColor =
    rainWaterBody * (0.78 + rainCore * 0.32) +
    mix(vec3(0.38, 0.52, 0.68), vec3(0.78, 0.90, 1.00), dayNightMix) *
    rainGlint * RAIN_REFLECTION;

vec4 rainScreenReflection = vec4(0.0);
#if RAIN_SSR == 1 && REFLECTION == 1 && SSR_TYPE > 0
    if (weatherTexel.a > 0.015 && rainParticleMask > 0.5) {
        float rainCurve = clamp(
            (rainLocalUV.x - 0.5) * 1.72,
            -0.86,
            0.86
        );
        vec3 rainReflectionNormal = normalize(vec3(
            rainCurve,
            -weatherWindView.x * 0.26,
            sqrt(max(1.0 - rainCurve * rainCurve, 0.02))
        ));
        vec3 rainViewDirection = normalize(weatherViewPosition);

        if (dot(rainReflectionNormal, -rainViewDirection) < 0.0) {
            rainReflectionNormal = -rainReflectionNormal;
        }

        vec3 rainReflectionDirection = reflect(
            rainViewDirection,
            rainReflectionNormal
        );
        float rainSSRJitter = fract(
            sin(dot(
                gl_FragCoord.xy + float(frameCounter),
                vec2(12.9898, 78.233)
            )) * 43758.5453
        );

        rainScreenReflection = traceRainSSR(
            weatherViewPosition + rainReflectionNormal * 0.025,
            rainReflectionDirection,
            rainSSRJitter
        );
    }
#endif

rainMirrorColor = mix(
    rainMirrorColor,
    rainScreenReflection.rgb * 1.18,
    rainScreenReflection.a * RAIN_REFLECTION
);
rainMirrorColor *= RAIN_BRIGHTNESS;
rainMirrorColor +=
    vec3(0.12, 0.19, 0.28) *
    rainCore *
    (0.35 + rainScreenReflection.a * 0.65);

blockColor.rgb = mix(
    blockColor.rgb,
    rainMirrorColor,
    rainParticleMask * (0.72 + RAIN_REFLECTION * 0.24)
);
