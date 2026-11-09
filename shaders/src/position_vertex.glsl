gl_Position = gl_ModelViewProjectionMatrix * gl_Vertex;

#ifdef FOLIAGE_V  // Optimized path for foliage and general blocks
    
    isFoliage = 0.0;

    // In vanilla-only mode the three exclusive grass IDs behave like the
    // pack's original foliage panels. Procedural modes keep their source
    // vertices anchored so the geometry stage can build stable roots.
    bool isVanillaGrassPanel = false;
    #if GRASS_MODE == 0
        isVanillaGrassPanel = (
            mc_Entity.x == ENTITY_VANILLA_GRASS ||
            mc_Entity.x == ENTITY_VANILLA_TALL_GRASS_LOWER ||
            mc_Entity.x == ENTITY_VANILLA_TALL_GRASS_UPPER
        );
    #endif

    // Check whether the current entity is a foliage type.
    bool isFoliageEntity = (
        mc_Entity.x == ENTITY_LOWERGRASS ||
        mc_Entity.x == ENTITY_UPPERGRASS ||
        mc_Entity.x == ENTITY_SMALLGRASS ||
        mc_Entity.x == ENTITY_SMALLENTS ||
        mc_Entity.x == ENTITY_LEAVES ||
        mc_Entity.x == ENTITY_SMALLENTS_NW ||
        isVanillaGrassPanel
    );

    vec4 viewPosition = gl_ModelViewMatrix * gl_Vertex;
    vec4 position = gbufferModelViewInverse * viewPosition;
    
    if (isFoliageEntity) {
        isFoliage = 0.4;

        #ifdef PLAYER_INTERACTIVE_FOLIAGE
            bool receivesPlayerBend = (
                mc_Entity.x == ENTITY_SMALLGRASS ||
                mc_Entity.x == ENTITY_LOWERGRASS ||
                mc_Entity.x == ENTITY_UPPERGRASS ||
                mc_Entity.x == ENTITY_SMALLENTS ||
                isVanillaGrassPanel
            );

            if (receivesPlayerBend) {
                position.xyz = bendFoliageAwayFromPlayer(
                    position.xyz,
                    cameraPosition,
                    relativeEyePosition,
                    gl_MultiTexCoord0.xy,
                    mc_midTexCoord.y
                );

                // Project the bent world-space point. This is the final bridge
                // between the distance calculation and the rasterized position.
                viewPosition = gbufferModelView * position;
                gl_Position = gl_ProjectionMatrix * viewPosition;
            }
        #endif

        #if WAVING == 1
            if (mc_Entity.x != ENTITY_SMALLENTS_NW) {
                vec3 worldpos = position.xyz + cameraPosition;

                // Original logic for the movement weight
                float weight = float(gl_MultiTexCoord0.t < mc_midTexCoord.t);

                if (
                    mc_Entity.x == ENTITY_UPPERGRASS ||
                    mc_Entity.x == ENTITY_VANILLA_TALL_GRASS_UPPER
                ) {
                    weight += 1.0;
                } else if (mc_Entity.x == ENTITY_LEAVES) {
                    weight = .3;
                } else if (mc_Entity.x == ENTITY_SMALLENTS && (weight > 0.9 || fract(worldpos.y + 0.0675) > 0.01)) {
                    weight = 1.0;
                }

                weight *= lmcoord.y * lmcoord.y;
                
                // Compute the offset and add it to the base position computed above.
                vec3 waveOffsetWorld = wave_move(worldpos.xzy) * weight * (0.03 + (rainStrength * .05));
                vec4 waveOffsetClip = gl_ModelViewProjectionMatrix * vec4(waveOffsetWorld, 0.0);
                
                gl_Position += waveOffsetClip;
            }
        #endif
    }

#else // Path for programs without foliage (e.g. entities)

    vec4 viewPosition = gl_ModelViewMatrix * gl_Vertex;
    #ifndef NO_SHADOWS
        #ifdef SHADOW_CASTING
            vec4 position = gbufferModelViewInverse * viewPosition;
        #endif
    #endif
    
#endif

#ifdef EMMISIVE_V
    float isFakeEmmisor = float(mc_Entity.x == ENTITY_F_EMMISIVE);
#endif

#if AA_TYPE > 1
    gl_Position.xy += taaOffset * gl_Position.w;
#endif

#ifndef SHADER_BASIC
    vec4 homopos = gbufferProjectionInverse * vec4(gl_Position.xyz / gl_Position.w, 1.0);
    vec3 viewPos = homopos.xyz / homopos.w;

    #if defined GBUFFER_CLOUDS
        gl_FogFragCoord = length(viewPos.xz);
    #else
        gl_FogFragCoord = length(viewPos.xyz);
    #endif
#endif

#if defined SHADOW_CASTING && SHADOW_LOCK > 0 && !defined NETHER && !defined GBUFFER_BASIC && !defined GBUFFER_CLOUDS && !defined GBUFFER_ARMOR_GLINT && !defined GBUFFER_SPIDEREYES
    vWorldPos = position.xyz;
#endif
