tintColor = gl_Color;

// Native light (lmcoord.x: block light, lmcoord.y: sky) ----
#if defined THE_END || defined NETHER
    vec2 illumination = vec2(lmcoord.x, 1.0);
#else
    vec2 illumination = lmcoord;
#endif

illumination.y = max(illumination.y - 0.065, 0.0) * 1.06951871657754;
visibleSky = clamp(illumination.y, 0.0, 1.0);

#if defined UNKNOWN_DIM
    visibleSky = (visibleSky * 0.6) + 0.4;
#endif

// Block light intensity and color
float candle_luma = illumination.x * sqrt(illumination.x);
candleColor = CANDLE_BASELIGHT * (candle_luma + sixthPow(illumination.x * 1.17));
candleColor = clamp(candleColor, vec3(0.0), vec3(4.0));

// Direct light attenuation by direction ===================================
#if defined THE_END || defined NETHER
    vec3 astroVector = normalize(gbufferModelView * vec4(0.0, 0.89442719, 0.4472136, 0.0)).xyz;
#else
    vec3 astroVector = normalize(sunPosition);
#endif

vec3 normal = gl_NormalMatrix * gl_Normal;
float astroLightStrength;

// Checking the squared length (dot product) is much faster than the length (sqrt).
if (dot(normal, normal) > 0.0001) {  // Workaround for undefined normals
    normal = normalize(normal);
    astroLightStrength = dot(normal, astroVector);
} else {
    normal = vec3(0.0, 1.0, 0.0);
    astroLightStrength = 1.0;
}

#if defined THE_END || defined NETHER
    directLightStrength = astroLightStrength;
#else
    directLightStrength = mix(-astroLightStrength, astroLightStrength, dayNightMix);
#endif

// Omni light intensity changes by angle
float omniStrength = ((directLightStrength + 1.0) * 0.25) + 0.75;     

// Direct light color
#ifdef UNKNOWN_DIM
    directLightColor = texture2D(lightmap, vec2(0.0, lmcoord.y)).rgb;
#else
    directLightColor = dayBlend(LIGHT_SUNSET_COLOR, LIGHT_DAY_COLOR, LIGHT_NIGHT_COLOR);
    #if defined IS_IRIS && defined THE_END && MC_VERSION >= 12109
        directLightColor += (endFlashIntensity * endFlashIntensity * 0.1);
    #endif
#endif

directLightStrength = clamp(directLightStrength, 0.0, 1.0);

#if defined THE_END || defined NETHER
    omniLight = LIGHT_DAY_COLOR;
#else
    directLightColor = mix(directLightColor, ZENITH_SKY_RAIN_COLOR * luma(directLightColor) * 0.4, rainStrength);

    // Minimal light
    vec3 omniColor = mix(ZenithSkyColorRGB, directLightColor * 0.45, OMNI_TINT);
    float omniColorLuma = colorAverage(omniColor);
    
    // Prevent division by zero
    float lumaRatio = AVOID_DARK_LEVEL / max(omniColorLuma, 0.0001);
    
    vec3 omniColorMin = omniColor * lumaRatio;
    omniColor = max(omniColor, omniColorMin);
    
    omniLight = mix(omniColorMin, omniColor, visibleSky) * omniStrength;

    #ifdef CINEMATIC_FOG_STYLE
        // Keep distant terrain under the same sky-aware moonlight as near chunks.
        float cinematicFogNightLight = step(0.5, dayMoment) * nightMixer;
        float cinematicFogMidnight =
            smoothstep(0.62, 0.72, dayMoment) *
            (1.0 - smoothstep(0.78, 0.90, dayMoment));
        float moonSkyExposure = smoothstep(0.18, 0.92, visibleSky);
        vec3 moonAmbientBase = mix(
            vec3(0.030, 0.046, 0.082),
            vec3(0.130, 0.022, 0.012),
            CINEMATIC_FOG_LUNAR_ECLIPSE_LIGHTING
        );
        vec3 moonAmbient =
            moonAmbientBase *
            (0.72 + 0.28 * NIGHT_BRIGHT_PHASE) *
            mix(1.0, 0.76, cinematicFogMidnight);
        omniLight +=
            moonAmbient *
            moonSkyExposure *
            cinematicFogNightLight *
            (1.0 - rainStrength * 0.55);

        applyCinematicFogOvercastLighting(
            directLightColor,
            directLightStrength,
            omniLight,
            visibleSky
        );
    #endif
#endif

if (isEyeInWater == 0) {
    // Replace pow(x, 10.0) with multiplications
    // Much faster than pow(). x^10 = (x^2)^2 * x^2
    float visSky2 = visibleSky * visibleSky;     // x^2
    float visSky4 = visSky2 * visSky2;       // x^4
    float visSky8 = visSky4 * visSky4;       // x^8
    float vis_sky_10 = visSky8 * visSky2;      // x^10
    directLightStrength = mix(0.0, directLightStrength, vis_sky_10);
} else {
    directLightStrength = mix(0.0, directLightStrength, visibleSky);
}

if (dhMaterialId == DH_BLOCK_ILLUMINATED) {
    directLightStrength = 10.0;
} else if (dhMaterialId == DH_BLOCK_LAVA) {
    directLightStrength = 1.0;
}
