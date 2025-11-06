-- engine/effects/screen/shaders.lua
-- Screen-space effect shaders (GLSL)

local shaders = {}

-- Flash effect shader (full screen color overlay with fade)
shaders.flash_code = [[
    extern vec3 flash_color;
    extern float intensity;

    vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords)
    {
        vec4 pixel = Texel(texture, texture_coords);

        // Add flash color
        pixel.rgb = pixel.rgb + (flash_color * intensity);

        return pixel * color;
    }
]]

-- Vignette effect shader (darkens edges)
shaders.vignette_code = [[
    extern vec3 vignette_color;
    extern float intensity;
    extern float radius;  // 0.0-1.0, how much of screen is affected

    vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords)
    {
        vec4 pixel = Texel(texture, texture_coords);

        // Calculate distance from center
        vec2 position = texture_coords - vec2(0.5, 0.5);
        float dist = length(position);

        // Create vignette effect
        float vignette = smoothstep(radius, radius - 0.3, dist);

        // Mix original color with vignette color
        pixel.rgb = mix(vignette_color, pixel.rgb, vignette * (1.0 - intensity) + intensity);

        return pixel * color;
    }
]]

-- Color overlay shader (simple tint)
shaders.overlay_code = [[
    extern vec3 overlay_color;
    extern float intensity;

    vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords)
    {
        vec4 pixel = Texel(texture, texture_coords);

        // Mix with overlay color
        pixel.rgb = mix(pixel.rgb, overlay_color, intensity);

        return pixel * color;
    }
]]

-- Initialize shaders
function shaders.init()
    shaders.flash = love.graphics.newShader(shaders.flash_code)
    shaders.vignette = love.graphics.newShader(shaders.vignette_code)
    shaders.overlay = love.graphics.newShader(shaders.overlay_code)

    dprint("Screen effect shaders initialized")
end

return shaders
