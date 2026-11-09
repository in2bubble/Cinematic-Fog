// Modified 2026-08-02: retain subtle volumetric light during rain.
#include "/lib/config.glsl"
const bool colortex1MipmapEnabled = true;

/* Color utils */

#ifdef THE_END
    #include "/lib/color_utils_end.glsl"
#elif defined NETHER
    #include "/lib/color_utils_nether.glsl"
#else
    #include "/lib/color_utils.glsl"
#endif

/* Uniforms */

uniform sampler2D colortex1;
uniform sampler2D colortex2;
uniform float far;
uniform float near;
uniform float blindness;
uniform float rainStrength;
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
uniform sampler2D gaux1;
uniform int isEyeInWater;
uniform ivec2 eyeBrightnessSmooth;
uniform float pixelSizeX;
uniform float pixelSizeY;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferModelView;
uniform vec3 cameraPosition;
uniform float frameTimeCounter;
uniform int frameCounter;
uniform float wetness;

#if defined CINEMATIC_FOG_STYLE && !defined NETHER && !defined THE_END
    uniform sampler2D noisetex;
    uniform vec3 moonPosition;
#endif

#if MC_VERSION >= 11900
    uniform float darknessFactor;
#endif

#if VOL_LIGHT == 1 && !defined NETHER
    uniform vec3 sunPosition;
    uniform float dayNightMix;
    uniform float volumetricDayMixer;
#endif

#if VOL_LIGHT == 2 && defined SHADOW_CASTING && !defined NETHER
    uniform float dayNightMix;
    uniform float volumetricDayMixer;
    uniform vec3 shadowLightPosition;
    uniform mat4 shadowModelView;
    uniform mat4 shadowProjection;
    uniform sampler2DShadow shadowtex1;

    #if defined COLORED_SHADOW
        uniform sampler2DShadow shadowtex0;
        uniform sampler2D shadowcolor0;
    #endif
#endif

/* Ins / Outs */

varying vec2 texcoord;
varying vec3 directLightColor;
varying float exposure;

#if VOL_LIGHT == 1 && !defined NETHER
    varying vec3 volumetricLightColor;
    varying vec2 lightpos;
    varying vec3 astroLightPos;
#endif

#if VOL_LIGHT == 2 && defined SHADOW_CASTING && !defined NETHER
    varying vec3 volumetricLightColor;
#endif

#if (VOL_LIGHT == 1 && !defined NETHER) || (VOL_LIGHT == 2 && defined SHADOW_CASTING && !defined NETHER) || (defined WORLD_ATMOSPHERIC_FOG && !defined NETHER && !defined THE_END)
    varying mat4 modeli_times_projectioni;
#endif

/* Utility functions */

#include "/lib/dh_scene.glsl"
#include "/lib/basic_utils.glsl"
#include "/lib/depth.glsl"

#ifdef THE_END
    #include "/lib/end_storm.glsl"
#endif

#if RAIN_PUDDLES == 1 && !defined NETHER && !defined THE_END
    #include "/lib/rain_ssr.glsl"
    #include "/lib/rain_puddles.glsl"
#endif

#if defined WORLD_ATMOSPHERIC_FOG && !defined NETHER && !defined THE_END
    #define worldFogInverseViewProjection modeli_times_projectioni
    #include "/lib/world_atmospheric_fog.glsl"
#endif

#ifdef BLOOM
    #include "/lib/luma.glsl"
#endif

#if VOL_LIGHT == 1 && !defined NETHER
    #include "/lib/dither.glsl"
    #include "/lib/volumetric_light.glsl"
#endif

#if VOL_LIGHT == 2 && defined SHADOW_CASTING && !defined NETHER
    #include "/lib/dither.glsl"
    #include "/lib/volumetric_light.glsl"
#endif

#if defined CINEMATIC_FOG_STYLE && !defined NETHER && !defined THE_END
    vec3 renderDynamicLunarSystem(
        vec3 backgroundColor,
        vec3 eyeDirection,
        float cloudOcclusion
    ) {
        // moonPosition and eyeDirection are both in view space here, so the
        // texture remains aligned without another matrix conversion.
        vec3 moonDirection = normalize(moonPosition);
        vec3 basisReference =
            abs(moonDirection.y) < 0.98 ?
            vec3(0.0, 1.0, 0.0) :
            vec3(1.0, 0.0, 0.0);
        vec3 moonRight = normalize(cross(basisReference, moonDirection));
        vec3 moonUp = cross(moonDirection, moonRight);

        vec2 moonUv = vec2(
            dot(eyeDirection, moonRight),
            dot(eyeDirection, moonUp)
        ) / 0.205 + 0.5;

        float squareGuard =
            step(0.0, moonUv.x) *
            step(moonUv.x, 1.0) *
            step(0.0, moonUv.y) *
            step(moonUv.y, 1.0);
        float radius = length(moonUv - vec2(0.5));
        float circularGuard = 1.0 - smoothstep(0.352, 0.368, radius);
        float facing = smoothstep(
            0.9865,
            0.9955,
            dot(eyeDirection, moonDirection)
        );

        float nightVisibility = smoothstep(0.49, 0.54, dayMoment);
        float weatherVisibility =
            1.0 - smoothstep(0.18, 1.0, rainStrength) * 0.22;

        // Restore the original deep-blue moonlight family used by the pack's
        // night shafts instead of driving all three channels toward white.
        // Looking directly at the moon lifts its HDR source slightly, allowing
        // the regular bloom pipeline to react in the same way as the sun.
        vec3 centerEyeDirection = normalize(
            (gbufferProjectionInverse * vec4(0.0, 0.0, 1.0, 1.0)).xyz
        );
        float gazeAlignment = smoothstep(
            0.975,
            0.9995,
            dot(centerEyeDirection, moonDirection)
        );

        // Filter the hand-painted 4K albedo before TAA. Its broad illustrated
        // maria and brush-shaped craters survive minification without becoming
        // photographic noise or a low-resolution pasted sprite.
        const float moonFilterRadius = 0.0022;
        vec3 moonTexture = vec3(0.64);
        if(squareGuard * circularGuard * facing > 0.0001) {
            moonTexture =
                texture2DLod(noisetex, moonUv, 0.0).rgb * 4.0;
            moonTexture += texture2DLod(
                noisetex,
                moonUv + vec2(moonFilterRadius, 0.0),
                0.0
            ).rgb;
            moonTexture += texture2DLod(
                noisetex,
                moonUv - vec2(moonFilterRadius, 0.0),
                0.0
            ).rgb;
            moonTexture += texture2DLod(
                noisetex,
                moonUv + vec2(0.0, moonFilterRadius),
                0.0
            ).rgb;
            moonTexture += texture2DLod(
                noisetex,
                moonUv - vec2(0.0, moonFilterRadius),
                0.0
            ).rgb;
            moonTexture *= 0.125;
        }
        float moonTextureLuma = dot(
            moonTexture,
            vec3(0.2126, 0.7152, 0.0722)
        );
        float moonSurfaceDetail = smoothstep(
            0.38,
            0.72,
            moonTextureLuma
        );
        float moonDetailModulation = mix(
            0.76,
            1.18,
            moonSurfaceDetail
        );
        vec3 moonPaintTint = clamp(
            moonTexture / max(moonTextureLuma, 0.001),
            vec3(0.82),
            vec3(1.18)
        );

        // Use a seven-night illustrated cycle tied directly to the world day:
        // waxing crescent, first quarter, waxing gibbous, full, waning
        // gibbous, last quarter and waning crescent. The invisible new-moon
        // frame is intentionally omitted, so every night has a visible body
        // and a clearly different silhouette.
        vec2 lunarSpherePosition =
            (moonUv - vec2(0.5)) / 0.36;
        float lunarRadiusSquared = dot(
            lunarSpherePosition,
            lunarSpherePosition
        );
        float lunarSurfaceDepth = sqrt(
            max(1.0 - lunarRadiusSquared, 0.0)
        );
        // Give the illustrated phase axis a restrained six-degree tilt. This
        // avoids rigid vertical half-moons and gives both crescents a more
        // graceful orientation without rotating the painted surface itself.
        vec2 tiltedLunarSpherePosition = vec2(
            lunarSpherePosition.x * 0.99452189537 -
                lunarSpherePosition.y * 0.10452846327,
            lunarSpherePosition.x * 0.10452846327 +
                lunarSpherePosition.y * 0.99452189537
        );
        vec3 lunarSurfaceNormal = normalize(
            vec3(tiltedLunarSpherePosition, lunarSurfaceDepth)
        );
        float visualMoonStage = mod(float(worldDay), 7.0);
        float lunarPhaseAngle =
            (5.0 + visualMoonStage) * 0.78539816339;
        // Widen both crescents from roughly 15% illumination to roughly 21%.
        // This produces confident, attractive arcs instead of needle-thin
        // slivers while retaining a smooth spherical terminator.
        if(visualMoonStage < 0.5) {
            lunarPhaseAngle += 0.17453292520;
        } else if(visualMoonStage > 5.5) {
            lunarPhaseAngle -= 0.17453292520;
        }
        vec3 lunarLightDirection = normalize(
            vec3(
                -sin(lunarPhaseAngle),
                0.0,
                cos(lunarPhaseAngle)
            )
        );
        float lunarLightingDot = dot(
            lunarSurfaceNormal,
            lunarLightDirection
        );
        float lunarDirectLight = smoothstep(
            0.0,
            0.045,
            lunarLightingDot
        );
        // The illuminated mask controls the actual visible silhouette. The
        // unlit side does not remain as a fixed dark circle, so crescents and
        // quarter moons have their own true shapes against the night sky.
        float lunarPhaseSilhouette = smoothstep(
            0.0,
            0.025,
            lunarLightingDot
        );
        float illuminatedFraction =
            0.5 + 0.5 * cos(lunarPhaseAngle);

        // A lunar eclipse is deliberately rare: one full moon every 28
        // Minecraft days. It remains a luminous copper atmospheric event,
        // rather than another ordinary dark phase.
        float lunarEclipse =
            cinematicFogLunarEclipseAmount(worldDay);

        // Derive the lunar tint from the local atmospheric color instead of a
        // fixed RGB value. Normalizing the tint preserves a stable luminance
        // while the hue follows the current night sky, weather and horizon.
        float localSkyLuma = max(
            dot(
                backgroundColor,
                vec3(0.2126, 0.7152, 0.0722)
            ),
            0.015
        );
        vec3 localSkyTint = clamp(
            backgroundColor / localSkyLuma,
            vec3(0.68),
            vec3(1.45)
        );
        vec3 adaptiveMoonTint = mix(
            vec3(0.96, 0.99, 1.04),
            localSkyTint,
            0.48
        );
        adaptiveMoonTint /= max(
            dot(
                adaptiveMoonTint,
                vec3(0.2126, 0.7152, 0.0722)
            ),
            0.001
        );
        vec3 eclipseTint = vec3(1.22, 0.48, 0.24);
        eclipseTint /= dot(
            eclipseTint,
            vec3(0.2126, 0.7152, 0.0722)
        );
        adaptiveMoonTint = mix(
            adaptiveMoonTint,
            eclipseTint,
            lunarEclipse * 0.82
        );

        // The unlit side retains faint earthshine. The lit side reaches the
        // bloom threshold only in its brighter albedo regions, preserving
        // surface detail instead of turning the whole body white.
        float moonExposureCompensation = max(exposure, 1.0);
        float moonTargetLuma = mix(0.84, 0.96, gazeAlignment);
        float phaseIllumination = mix(
            0.72,
            1.0,
            lunarDirectLight
        );
        float eclipseIllumination =
            0.22 + 0.10 * lunarSurfaceDepth;
        phaseIllumination = mix(
            phaseIllumination,
            eclipseIllumination,
            lunarEclipse
        );
        lunarPhaseSilhouette = mix(
            lunarPhaseSilhouette,
            1.0,
            lunarEclipse
        );
        float lunarLimb =
            0.88 + 0.12 * lunarSurfaceDepth;
        vec3 moonColor =
            adaptiveMoonTint *
            moonTargetLuma *
            moonDetailModulation /
            moonExposureCompensation *
            phaseIllumination *
            lunarLimb *
            mix(vec3(1.0), moonPaintTint, 0.32);

        float opacity =
            squareGuard *
            circularGuard *
            facing *
            nightVisibility *
            weatherVisibility *
            mix(0.82, 0.24, cloudOcclusion) *
            lunarPhaseSilhouette;

        // This is broad atmospheric scattering, not a compact halo ring. It
        // grows gently when the camera faces the moon and remains interrupted
        // by the cloud transmittance stored for the current sky pixel.
        float angularScattering = smoothstep(
            0.900,
            0.9995,
            dot(eyeDirection, moonDirection)
        );
        float scatteringStrength =
            angularScattering *
            nightVisibility *
            weatherVisibility *
            mix(1.0, 0.34, cloudOcclusion) *
            mix(0.020, 0.105, gazeAlignment) *
            mix(0.03, 1.0, sqrt(illuminatedFraction)) *
            mix(
                1.0,
                0.82,
                lunarEclipse *
                    CINEMATIC_FOG_LUNAR_ECLIPSE_INTENSITY
            );
        vec3 scatteringColor = mix(
            adaptiveMoonTint * vec3(0.035, 0.055, 0.090),
            vec3(0.360, 0.025, 0.010),
            lunarEclipse *
                CINEMATIC_FOG_LUNAR_ECLIPSE_INTENSITY
        );
        vec3 moonIntegratedBackground =
            backgroundColor +
            scatteringColor * scatteringStrength;

        return mix(moonIntegratedBackground, moonColor, opacity);
    }
#endif

// MAIN FUNCTION ------------------

void main() {
    vec4 blockColor = texture2DLod(colortex1, texcoord, 0);
    float d = texture2DLod(depthtex0, texcoord, 0).r;
    float linearDepth = ld(d);

    // Distant Horizons: vanilla depth is 1.0 on LOD pixels, so fog needs the
    // LOD position and the LOD render distance as its horizon.
    float fogHorizon = far;
    float lodMask = 0.0;
    vec3 lodPlayerPosition = vec3(0.0);
    bool isLodPixel = false;
    #ifdef DISTANT_HORIZONS
        float lodDepth = dhSceneDepth(texcoord);
        isLodPixel = dhIsLodPixel(d, lodDepth);
        fogHorizon = max(far, float(dhRenderDistance));
        if (isLodPixel) {
            lodMask = 1.0;
            lodPlayerPosition = (
                gbufferModelViewInverse *
                vec4(dhViewPosition(texcoord, lodDepth), 1.0)
            ).xyz;
        }
    #endif

    #if RAIN_PUDDLES == 1 && !defined NETHER && !defined THE_END
        if (isEyeInWater == 0) {
            float terrainSkyExposure =
                texture2DLod(colortex2, texcoord, 0).g;
            blockColor.rgb = applyRainPuddles(
                blockColor.rgb,
                texcoord,
                d,
                terrainSkyExposure
            );
        }
    #endif

    vec2 eyeBrightSmoothFloat = vec2(eyeBrightnessSmooth);

    // Depth to distance
    float screen_distance = linearDepth * far * 0.5;

    // Underwater fog
    if(isEyeInWater == 1) {
        #if defined CINEMATIC_FOG_STYLE && !defined NETHER && !defined THE_END
            float underwaterDistance =
                max(linearDepth * far * 0.5, 0.0);
            float absorptionDensity =
                dayBlendFloat(0.050, 0.043, 0.064) +
                WATER_ABSORPTION * 0.18;
            float waterAbsorption = clamp(
                1.0 -
                    exp2(
                        -underwaterDistance *
                        absorptionDensity
                    ),
                0.0,
                1.0
            );
            float nearScattering = clamp(
                1.0 -
                    exp2(
                        -underwaterDistance * 0.070
                    ),
                0.0,
                1.0
            );

            vec3 volumeWaterColor =
                cinematicFogUnderwaterPalette(
                    rainStrength
                );
            float underwaterSkylight = clamp(
                (eyeBrightSmoothFloat.y * 0.8 + 48.0) *
                    0.004166666666666667,
                0.0,
                1.0
            );
            float volumeIllumination =
                dayBlendFloat(0.72, 0.86, 0.52) *
                mix(1.0, 0.91, rainStrength);
            volumeIllumination +=
                underwaterSkylight * 0.14;
            vec3 illuminatedWater =
                volumeWaterColor *
                volumeIllumination;

            // Red light disappears first; cyan and blue survive farther into
            // rivers and oceans, while nearby blocks remain readable.
            vec3 channelExtinction =
                vec3(0.064, 0.038, 0.021) *
                (0.86 + WATER_ABSORPTION * 1.45) *
                dayBlendFloat(1.00, 0.88, 1.18);
            vec3 transmission = exp2(
                -underwaterDistance *
                channelExtinction
            );
            vec3 transmittedScene =
                blockColor.rgb * transmission;
            blockColor.rgb = mix(
                transmittedScene,
                illuminatedWater,
                waterAbsorption * 0.94
            );
            blockColor.rgb +=
                volumeWaterColor *
                nearScattering *
                0.055;
        #else
            float waterAbsorption = clamp(
                1.0 -
                    pow(
                        1.001 - linearDepth,
                        5.0 +
                            (4.0 * WATER_ABSORPTION)
                    ),
                0.0,
                1.0
            );
            blockColor.rgb = mix(
                blockColor.rgb,
                WATER_COLOR *
                    directLightColor *
                    ((eyeBrightSmoothFloat.y * .8 + 48) *
                        0.004166666666666667),
                waterAbsorption
            );
        #endif

    } else if(isEyeInWater == 2) {
        blockColor = mix(blockColor, vec4(1.0, .1, 0.0, 1.0), clamp(sqrt(linearDepth * far * 0.125), 0.0, 1.0));
    }

    #ifdef THE_END
        if(isEyeInWater == 0) {
            vec4 endViewPosition =
                gbufferProjectionInverse *
                (vec4(texcoord, d, 1.0) * 2.0 - 1.0);
            vec3 endWorldDirection = normalize(
                (
                    gbufferModelViewInverse *
                    vec4(endViewPosition.xyz, 0.0)
                ).xyz
            );

            float endLightning =
                endStormLightningPulse(frameTimeCounter);
            float endLightningGlow =
                endStormLightningGlow(
                    endWorldDirection,
                    frameTimeCounter
                );

            // Depth fog anchors the storm to End stone instead of affecting
            // only the empty background. A shallow height veil makes distant
            // islands disappear into rolling haze around the horizon.
            float endDistanceFog =
                1.0 - exp2(-max(screen_distance - 7.0, 0.0) * 0.0105);
            float endHorizonHaze =
                1.0 -
                smoothstep(
                    0.05,
                    0.52,
                    abs(endWorldDirection.y + 0.025)
                );
            float endFogAmount =
                clamp(
                    endDistanceFog *
                        (0.58 + endHorizonHaze * 0.38),
                    0.0,
                    0.88
                );

            float endGroundHaze = 0.0;
            if(d < 0.9999) {
                vec3 endViewSurface =
                    endViewPosition.xyz /
                    max(abs(endViewPosition.w), 0.0001);
                vec3 endWorldPosition =
                    (
                        gbufferModelViewInverse *
                        vec4(endViewSurface, 1.0)
                    ).xyz +
                    cameraPosition;
                float endLowAltitude =
                    1.0 -
                    smoothstep(
                        72.0,
                        116.0,
                        endWorldPosition.y
                    );
                float endMistVariation =
                    0.84 +
                    0.16 *
                    sin(
                        endWorldPosition.x * 0.031 +
                        endWorldPosition.z * 0.024 +
                        sin(endWorldPosition.z * 0.013) * 1.7
                    );
                endGroundHaze =
                    (
                        1.0 -
                        exp2(
                            -max(screen_distance - 3.0, 0.0) *
                            0.018
                        )
                    ) *
                    endLowAltitude *
                    endMistVariation *
                    0.72;
                endFogAmount = max(
                    endFogAmount,
                    endGroundHaze
                );
            }

            // Preserve detailed cloud silhouettes in the void while still
            // allowing a restrained luminous haze around active strikes.
            if(d > 0.9999) {
                endFogAmount *= 0.16;
            }

            vec3 electricalFog =
                endStormFogColor(endLightning);
            blockColor.rgb = mix(
                blockColor.rgb,
                electricalFog,
                endFogAmount
            );

            float sceneFlash =
                endLightning *
                    (
                        0.025 +
                        endDistanceFog * 0.11 +
                        endGroundHaze * 0.13
                    ) +
                endLightningGlow * 0.10;
            blockColor.rgb +=
                vec3(0.20, 0.25, 0.43) *
                sceneFlash;
        }
    #endif

    #if defined WORLD_ATMOSPHERIC_FOG && !defined NETHER && !defined THE_END
        if (isEyeInWater == 0) {
            float outdoorVisibility = smoothstep(
                8.0,
                150.0,
                float(eyeBrightnessSmooth.y)
            );

            float nightPhase = step(0.5, dayMoment) * nightMixer;
            float midnightPhase =
                smoothstep(0.62, 0.72, dayMoment) *
                (1.0 - smoothstep(0.78, 0.90, dayMoment));
            vec3 clearHorizonColor = dayBlend(
                HORIZON_SUNSET_COLOR,
                HORIZON_DAY_COLOR,
                HORIZON_NIGHT_COLOR
            );
            vec3 clearZenithColor = dayBlend(
                ZENITH_SUNSET_COLOR,
                ZENITH_DAY_COLOR,
                ZENITH_NIGHT_COLOR
            );
            vec3 clearAtmosphericColor = mix(
                clearHorizonColor,
                clearZenithColor,
                0.16
            );
            vec3 moonlitHazeBase = mix(
                vec3(0.130, 0.180, 0.290),
                vec3(0.480, 0.085, 0.045),
                CINEMATIC_FOG_LUNAR_ECLIPSE_LIGHTING
            );
            vec3 moonlitHazeColor =
                moonlitHazeBase *
                (0.72 + 0.28 * NIGHT_BRIGHT_PHASE) *
                mix(1.0, 0.88, midnightPhase);
            clearAtmosphericColor = mix(
                clearAtmosphericColor,
                moonlitHazeColor,
                nightPhase * 0.92
            );

            // A wet blue-gray participating medium reads as rain; the old
            // bright gray converged toward white after automatic exposure.
            vec3 daylightRainColor = vec3(0.190, 0.260, 0.345);
            vec3 moonlitRainColor =
                moonlitHazeColor * vec3(0.82, 0.88, 0.96);
            vec3 weatherAtmosphericColor = mix(
                daylightRainColor,
                moonlitRainColor,
                nightPhase
            );
            vec3 atmosphericColor = mix(
                clearAtmosphericColor,
                weatherAtmosphericColor,
                rainStrength * 0.88
            );

            float phaseDensity = dayBlendFloat(0.94, 1.0, 0.96);
            blockColor.rgb = applyWorldAtmosphericFog(
                blockColor.rgb,
                texcoord,
                d,
                atmosphericColor,
                outdoorVisibility,
                phaseDensity,
                fogHorizon,
                lodPlayerPosition,
                lodMask
            );
        }
    #endif

    #if MC_VERSION >= 11900
        if((blindness > .01 || darknessFactor > .01) && linearDepth > 0.9) {
            blockColor.rgb = vec3(0.0);
        }
    #else
        if(blindness > .01 && linearDepth > 0.999) {
            blockColor.rgb = vec3(0.0);
        }
    #endif

    #if (VOL_LIGHT == 1 && !defined NETHER) || (VOL_LIGHT == 2 && defined SHADOW_CASTING && !defined NETHER)
        #if AA_TYPE > 0
           float dither = shiftedDither17(gl_FragCoord.xy);
        #else
            float dither = rDither(gl_FragCoord.xy);
        #endif
    #endif

    #if VOL_LIGHT == 1 && !defined NETHER
        #if defined THE_END
            float volumetricLight = 0.1;
            if(d > 0.9999) {
                volumetricLight = 0.5;
            }
        #else
            float volumetricLight = ssGodrays(dither);
        #endif

        vec4 centerFarPlanePos = modeli_times_projectioni * (vec4(0.5, 0.5, 1.0, 1.0) * 2.0 - 1.0);
        vec3 centerEyeDirection = normalize(centerFarPlanePos.xyz);

        vec4 farPlaneClipPos = modeli_times_projectioni * (vec4(texcoord, 1.0, 1.0) * 2.0 - 1.0);
        vec3 eyeDirection = normalize(farPlaneClipPos.xyz);

        #if defined THE_END
            // Fixed light source position in sky for intensity calculation
            vec3 auxVector =
                normalize((gbufferModelViewInverse * gbufferModelView * vec4(0.0, 0.89442719, 0.4472136, 0.0)).xyz);
            float volumetricIntensity =
                clamp(dot(centerEyeDirection, auxVector), 0.0, 1.0);

            volumetricIntensity *= clamp(dot(eyeDirection, auxVector), 0.0, 1.0);

            volumetricIntensity *= 0.666;

            blockColor.rgb += (volumetricLightColor * volumetricLight * volumetricIntensity * 2.0);
        #else
            // Light source position for depth based godrays intensity calculation
            vec3 auxVector =
                normalize((gbufferModelViewInverse * vec4(astroLightPos, 0.0)).xyz);
            float volumetricIntensity =
                clamp(dot(centerEyeDirection, auxVector), 0.0, 1.0);
            volumetricIntensity *= dot(eyeDirection, auxVector);
            volumetricIntensity =
                pow(clamp(volumetricIntensity, 0.0, 1.0), volumetricDayMixer) * 0.5 * abs(dayNightMix * 2.0 - 1.0);

            #ifdef CINEMATIC_FOG_STYLE
                float cinematicFogShaftNight =
                    step(0.5, dayMoment) * nightMixer;
                // Keep the direct solar halo controlled. The previous boost
                // washed out most of the frame when the camera faced the sun.
                volumetricIntensity *=
                    0.82 * mix(1.0, 1.16, cinematicFogShaftNight);
            #endif

            blockColor.rgb =
                mix(blockColor.rgb, volumetricLightColor * volumetricLight, volumetricIntensity * (volumetricLight * 0.5 + 0.5) * (1.0 - rainStrength * 0.92));
        #endif
    #endif

    #if VOL_LIGHT == 2 && defined SHADOW_CASTING && !defined NETHER
        #if defined COLORED_SHADOW
            vec3 volumetricLight = get_volumetric_color_light(dither, screen_distance, modeli_times_projectioni);
        #else
            float volumetricLight = get_volumetric_light(dither, screen_distance, modeli_times_projectioni);
        #endif

        // Volumetric intensity adjustments

        vec4 farPlaneClipPos = modeli_times_projectioni * (vec4(texcoord, 1.0, 1.0) * 2.0 - 1.0);
        vec3 eyeDirection = normalize(farPlaneClipPos.xyz);

        #if defined THE_END
            // Fixed light source position in sky for volumetrics intensity calculation (The End)
            float volumetricIntensity = dot(eyeDirection, normalize((gbufferModelViewInverse * gbufferModelView * vec4(0.0, 0.89442719, 0.4472136, 0.0)).xyz));
        #else
            // Light source position for volumetrics intensity calculation
            float volumetricIntensity = dot(eyeDirection, normalize((gbufferModelViewInverse * vec4(shadowLightPosition, 0.0)).xyz));
        #endif

        #if defined THE_END
            volumetricIntensity =
                ((squarePow(clamp((volumetricIntensity + .666667) * 0.6, 0.0, 1.0)) * 0.5));
            blockColor.rgb += (volumetricLightColor * volumetricLight * volumetricIntensity * 2.0);
        #else
            volumetricIntensity =
                pow(clamp((volumetricIntensity + 0.5) * 0.666666666666666, 0.0, 1.0), volumetricDayMixer) * 0.6 * abs(dayNightMix * 2.0 - 1.0);

            #ifdef CINEMATIC_FOG_STYLE
                float cinematicFogShaftNight =
                    step(0.5, dayMoment) * nightMixer;
                // Match the screen-space shaft path to the restrained direct
                // solar halo used above.
                volumetricIntensity *=
                    0.80 * mix(1.0, 1.16, cinematicFogShaftNight);
            #endif

            blockColor.rgb =
                mix(blockColor.rgb, volumetricLightColor * volumetricLight, volumetricIntensity * (volumetricLight * 0.5 + 0.5) * (1.0 - rainStrength * 0.92));
        #endif
    #endif

    // Compose the complete dynamic moon after clouds, atmospheric fog and
    // volumetric lighting. Its cloud-weighted HDR source then enters the same
    // TAA and bloom pipeline as the rest of the cinematic sky.
    #if defined CINEMATIC_FOG_STYLE && !defined NETHER && !defined THE_END
        if(isEyeInWater == 0 && d > 0.9999 && !isLodPixel) {
            vec4 moonViewPosition =
                gbufferProjectionInverse *
                (vec4(texcoord, 1.0, 1.0) * 2.0 - 1.0);
            vec3 moonEyeDirection = normalize(moonViewPosition.xyz);
            blockColor.rgb = renderDynamicLunarSystem(
                blockColor.rgb,
                moonEyeDirection,
                texture2D(colortex2, texcoord).r
            );
        }
    #endif

    // Inside snow
    #ifdef BLOOM
        if(isEyeInWater == 3) {
            blockColor.rgb =
                mix(blockColor.rgb, vec3(0.7, 0.8, 1.0) / exposure, clamp(screen_distance, 0.0, 1.0));
        }
    #else
        if(isEyeInWater == 3) {
            blockColor.rgb =
                mix(blockColor.rgb, vec3(0.85, 0.9, 0.6), clamp(screen_distance, 0.0, 1.0));
        }
    #endif

    #ifdef BLOOM
        // Bloom source
        float bloom_luma = smoothstep(0.85, 1.0, luma(blockColor.rgb * exposure)) * 0.5;

        blockColor = clamp(blockColor, vec4(0.0), vec4(vec3(50.0), 1.0));
        /* DRAWBUFFERS:016 */
        gl_FragData[0] = blockColor * bloom_luma;
        gl_FragData[1] = blockColor;
        gl_FragData[2] = vec4(exposure, 0.0, 0.0, 0.0);
    #else
        blockColor = clamp(blockColor, vec4(0.0), vec4(vec3(50.0), 1.0));
        /* DRAWBUFFERS:16 */
        gl_FragData[0] = blockColor;
        gl_FragData[1] = vec4(exposure, 0.0, 0.0, 0.0);
    #endif
}
