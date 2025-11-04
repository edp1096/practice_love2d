-- systems/camera.lua
-- Camera effects: shake and slow motion

local camera_sys = {}

camera_sys.shake_x = 0
camera_sys.shake_y = 0
camera_sys.shake_timer = 0
camera_sys.shake_intensity = 0

camera_sys.slow_motion_active = false
camera_sys.slow_motion_timer = 0
camera_sys.time_scale = 1.0
camera_sys.target_time_scale = 1.0

function camera_sys:shake(intensity, duration)
    self.shake_intensity = intensity or 10
    self.shake_timer = duration or 0.3
end

function camera_sys:activate_slow_motion(duration, time_scale)
    self.slow_motion_active = true
    self.slow_motion_timer = duration or 0.5
    self.target_time_scale = time_scale or 0.3
end

function camera_sys:update(dt)
    -- Slow motion
    if self.slow_motion_active then
        self.slow_motion_timer = self.slow_motion_timer - dt
        if self.slow_motion_timer <= 0 then
            self.slow_motion_active = false
            self.target_time_scale = 1.0
        end
    end

    -- Smooth time scale transition
    local time_scale_speed = 8.0
    if self.time_scale < self.target_time_scale then
        self.time_scale = math.min(self.time_scale + time_scale_speed * dt, self.target_time_scale)
    elseif self.time_scale > self.target_time_scale then
        self.time_scale = math.max(self.time_scale - time_scale_speed * dt, self.target_time_scale)
    end

    -- Camera shake
    if self.shake_timer > 0 then
        self.shake_timer = math.max(0, self.shake_timer - dt)

        if self.shake_timer > 0 then
            self.shake_x = (math.random() - 0.5) * 2 * self.shake_intensity
            self.shake_y = (math.random() - 0.5) * 2 * self.shake_intensity
        else
            self.shake_x = 0
            self.shake_y = 0
        end
    end
end

function camera_sys:get_scaled_dt(dt)
    return dt * self.time_scale
end

function camera_sys:get_shake_offset()
    return self.shake_x, self.shake_y
end

return camera_sys
