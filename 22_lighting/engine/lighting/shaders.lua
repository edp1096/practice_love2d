-- engine/lighting/shaders.lua
-- Lighting system shaders (GLSL)

local shaders = {}

-- Light rendering shader (radial gradient for point lights)
shaders.light_code = [[
    extern vec2 light_position;
    extern float light_radius;
    extern vec3 light_color;
    extern float light_intensity;

    vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords)
    {
        // Calculate distance from light center
        float dist = distance(screen_coords, light_position);

        // Smooth falloff
        float attenuation = 1.0 - smoothstep(0.0, light_radius, dist);
        attenuation = pow(attenuation, 2.0);  // Quadratic falloff

        // Apply light color and intensity
        vec3 light = light_color * attenuation * light_intensity;

        return vec4(light, 1.0) * color;
    }
]]

-- Spotlight rendering shader (cone-shaped light)
shaders.spotlight_code = [[
    extern vec2 light_position;
    extern vec2 light_direction;  // Normalized direction vector
    extern float light_radius;
    extern float cone_angle;      // In radians
    extern vec3 light_color;
    extern float light_intensity;

    vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords)
    {
        // Vector from light to pixel
        vec2 to_pixel = screen_coords - light_position;
        float dist = length(to_pixel);

        if (dist > light_radius) {
            return vec4(0.0, 0.0, 0.0, 1.0);
        }

        vec2 to_pixel_norm = normalize(to_pixel);

        // Calculate angle between light direction and pixel direction
        float angle = acos(dot(light_direction, to_pixel_norm));

        // Check if pixel is within cone
        if (angle > cone_angle) {
            return vec4(0.0, 0.0, 0.0, 1.0);
        }

        // Distance attenuation
        float dist_attenuation = 1.0 - smoothstep(0.0, light_radius, dist);
        dist_attenuation = pow(dist_attenuation, 2.0);

        // Angular attenuation (soften edges)
        float angle_attenuation = 1.0 - smoothstep(0.0, cone_angle, angle);

        // Combine attenuations
        float attenuation = dist_attenuation * angle_attenuation;

        // Apply light color and intensity
        vec3 light = light_color * attenuation * light_intensity;

        return vec4(light, 1.0) * color;
    }
]]

-- Initialize shaders
function shaders.init()
    shaders.light = love.graphics.newShader(shaders.light_code)
    shaders.spotlight = love.graphics.newShader(shaders.spotlight_code)

    dprint("Lighting shaders initialized")
end

return shaders
