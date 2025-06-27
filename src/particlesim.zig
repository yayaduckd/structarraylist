// NOTE - THIS WAS DEVELOPED IN THE CONTEXT OF A LARGER RENDERER I WAS WORKING ON.
// THIS MEANT I WAS ABLE TO HAVE SOME FUNNY VISUALIZATIONS OF THE SIMULATION
// HOWEVER, THIS IS JUST AN EXCERPT OF THE CODEBASE TO DEMONSTRATE THE
// PARTICLE SIMUATION ALGORITHM
// AS SUCH, IT IS MISSING SOME FILES AND WILL NOT COMPILE AS-IS

const c = @import("cmix.zig");
const Batcher = @import("drawer.zig");
const mk = @import("mkmix.zig");
const cam = @import("camera.zig");

const std = @import("std");
const zm = @import("include/zmath.zig");

const svl = @import("svl.zig");

const Engine = @This();

const Color = struct {
    r: f32 = 1,
    g: f32 = 1,
    b: f32 = 1,
    a: f32 = 1,
};

const Particle = struct {
    pos: @Vector(3, f32),
    vel: @Vector(3, f32),
    rot: f32,
    size: f32,
    mass: f32,
    initialization_color: Color,
    second_color: Color,
    particle_type: u32,
    user_data: u64,
    win_zone_locations: [10]@Vector(3, f32),
    win_zone_radii: [10]u32,
};

done: bool = false,
window: *c.SDL_Window = undefined,
gpu_device: *c.SDL_GPUDevice = undefined,

// pipeline: *c.SDL_GPUGraphicsPipeline = undefined,
// gpu resources
// vertex_buffer: *c.SDL_GPUBuffer = undefined,
// index_buffer: *c.SDL_GPUBuffer = undefined,

duck_texture: *c.SDL_GPUTexture = undefined,
debug_texture: *c.SDL_GPUTexture = undefined,
// duck_sampler: *c.SDL_GPUSampler = undefined,

clear_color: c.ImVec4 = .{ .x = 0.39, .y = 0.58, .z = 0.93, .w = 1.00 }, // clear color for rendering

current_frame: u64 = 0,

batcher: Batcher = undefined,

im_draw_data: ([*c]c.struct_ImDrawData) = undefined,

// particles

particles: svl.StructVecListReal(Particle) = undefined,
particlesa: std.ArrayList(Particle) = undefined,

total_svl_time_ns: u64 = 0,
total_arraylist_time_ns: u64 = 0,

fn cleanup(self: *Engine) void {
    c.ImGui_ImplSDLGPU3_Shutdown();
    c.ImGui_ImplSDL3_Shutdown();
    c.igDestroyContext(null); // destroy context
    c.SDL_ReleaseWindowFromGPUDevice(self.gpu_device, self.window);
    c.SDL_DestroyGPUDevice(self.gpu_device);
    c.SDL_DestroyWindow(self.window);
    c.SDL_Quit(); // defer sdl_quit

}

pub fn init() !Engine {
    var self = Engine{};

    try self.load_content();

    return self;
}

pub fn deinit(self: *Engine) void {
    _ = c.SDL_WaitForGPUIdle(self.gpu_device);
    self.cleanup();
}

pub fn run(self: *Engine) !void {
    const stdout = std.io.getStdOut();
    var writer = stdout.writer();
    const cwd = std.fs.cwd();

    // --- Setup the output CSV file and writer ---
    const output_file = try cwd.createFile("output.csv", .{});
    defer output_file.close(); // IMPORTANT: Ensure the file is closed on exit.
    var output_writer = output_file.writer();

    // const output_file2 = try cwd.createFile("sily.csv", .{});
    // defer output_file2.close(); // IMPORTANT: Ensure the file is closed on exit.
    // const output_writer2 = output_file2.writer();

    // --- Write the CSV header before the loop starts ---
    try output_writer.print("frame,svl_time_ms,arraylist_time_ms\n", .{});

    self.current_frame = 1;
    // We no longer need init_time or prev_t for the primary display
    while (!self.done) {
        // --- Game Logic Update ---
        // self.update(); // update general game logic

        // --- Time the 'Single Vector of Layouts' (SVL) implementation ---
        const svl_start = std.time.nanoTimestamp();
        try self.update_particles_svl();
        const svl_end = std.time.nanoTimestamp();
        const svl_time_ns = svl_end - svl_start;
        self.total_svl_time_ns += @intCast(svl_time_ns);

        // --- Time the 'ArrayList' implementation ---
        const arraylist_start = std.time.nanoTimestamp();
        try self.update_particles_arraylist();
        const arraylist_end = std.time.nanoTimestamp();
        const arraylist_time_ns = arraylist_end - arraylist_start;
        self.total_arraylist_time_ns += @intCast(arraylist_time_ns);

        // --- Calculate metrics in milliseconds ---
        const svl_time_ms: f64 = @as(f64, @floatFromInt(svl_time_ns)) / 1_000_000.0;
        const avg_svl_ms: f64 = (@as(f64, @floatFromInt(self.total_svl_time_ns)) / @as(f64, @floatFromInt(self.current_frame))) / 1_000_000.0;
        const al_time_ms: f64 = @as(f64, @floatFromInt(arraylist_time_ns)) / 1_000_000.0;
        const avg_al_ms: f64 = (@as(f64, @floatFromInt(self.total_arraylist_time_ns)) / @as(f64, @floatFromInt(self.current_frame))) / 1_000_000.0;

        // --- Print the benchmark results to the console ---
        try writer.print(
            "Frame {d} - SVL: {d:.4}ms (avg: {d:.4}ms)  |  ArrayList: {d:.4}ms (avg: {d:.4}ms) \r",
            .{ self.current_frame, svl_time_ms, avg_svl_ms, al_time_ms, avg_al_ms },
        );

        // --- NEW: Write the per-frame data to the CSV file ---
        try output_writer.print(
            "{d},{d:.4},{d:.4}\n",
            .{ self.current_frame, svl_time_ms, al_time_ms },
        );
        // const particle0 = self.particlesa.items[self.current_frame % self.particlesa.items.len - 1];

        // try std.json.stringify(particle0, .{}, output_writer2);

        // --- Drawing (optional, remains commented out) ---
        // try self.draw();
        // try self.draw_to_screen();
        self.current_frame += 1;
        if (self.current_frame >= 500) {
            self.done = true;
        }
    }
    // Print a final newline so the shell prompt doesn't overwrite the last output line
    try writer.print("\n", .{});
}

pub fn update_particles_arraylist(self: *Engine) !void {
    // --- Gravity Simulation ---
    // These constants can be tuned for different simulation effects.
    const G: f32 = 15.0; // Gravitational constant, affects the strength of attraction.
    const dt: f32 = 0.0005; // Delta time, the simulation time step. Smaller is more stable but slower.
    const softening_sq: f32 = 0.25; // Squared softening factor (0.5^2) to prevent forces from becoming infinite at close distances.

    // This is a classic N-body simulation with O(n^2) complexity.
    // For each particle, we calculate the total force exerted on it by all other particles.
    for (self.particlesa.items, 0..) |part1, i| {
        var total_acceleration: @Vector(3, f32) = .{ 0, 0, 0 };
        const p1_pos = part1.pos;

        // Sum the gravitational acceleration from all other particles.
        for (self.particlesa.items, 0..) |part2, j| {
            if (i == j) continue; // A particle is not affected by its own gravity.
            const p2_pos = part2.pos;

            const direction_vec = p2_pos - p1_pos;
            const zmdvec = zm.Vec{ direction_vec[0], direction_vec[1], direction_vec[2], 1 };
            const dist_sq = zm.dot3(zmdvec, zmdvec)[0];

            // Using the softening factor to avoid division by zero and extreme accelerations.
            // Force = G * m1 * m2 / (r^2 + s^2)
            // Acceleration = Force / m1 = G * m2 / (r^2 + s^2)
            // As we assume all masses (m2) are 1, acceleration magnitude is G / (r^2 + s^2).
            if (dist_sq > 0.00001) { // Only calculate if particles are not at the exact same spot.
                const force_mag = G / (dist_sq + softening_sq);
                // a = direction_normalized * force_mag
                // a = (direction_vec / dist) * force_mag
                // const acceleration = direction_vec * (force_mag / @sqrt(dist_sq));
                // const acceleration = zm.mul(zmdvec, (force_mag / @sqrt(dist_sq)));
                const f = (force_mag / @sqrt(dist_sq));
                const acceleration = .{ f * direction_vec[0], f * direction_vec[1], f * direction_vec[2] };
                // zm.mul(a: anytype, b: anytype)
                total_acceleration += acceleration;
            }
        }

        // Update velocity using Symplectic Euler integration: v_new = v_old + a * dt
        self.particlesa.items[i].vel += .{ total_acceleration[0] * dt, total_acceleration[1] * dt, total_acceleration[2] * dt };
    }

    // After calculating all new velocities, update all particle positions.
    // This two-step process (update all velocities, then all positions) is more stable.
    for (self.particlesa.items) |*part| {
        // p_new = p_old + v_new * dt
        part.*.pos += .{
            part.*.vel[0] * dt,
            part.*.vel[1] * dt,
            part.*.vel[2] * dt,
        };
        // std.log.debug("new part {}", .{part});
    }
}

pub fn update_particles_svl(self: *Engine) !void {

    // --- Gravity Simulation ---
    // These constants can be tuned for different simulation effects.
    const G: f32 = 15.0; // Gravitational constant, affects the strength of attraction.
    const dt: f32 = 0.0005; // Delta time, the simulation time step. Smaller is more stable but slower.
    const softening_sq: f32 = 0.25; // Squared softening factor (0.5^2) to prevent forces from becoming infinite at close distances.

    const positions = self.particles.get_attribute("pos");
    var velocities = self.particles.get_attribute("vel");

    // This is a classic N-body simulation with O(n^2) complexity.
    // For each particle, we calculate the total force exerted on it by all other particles.
    for (positions, 0..) |p1_pos, i| {
        var total_acceleration: @Vector(3, f32) = .{ 0, 0, 0 };

        // Sum the gravitational acceleration from all other particles.
        for (positions, 0..) |p2_pos, j| {
            if (i == j) continue; // A particle is not affected by its own gravity.

            const direction_vec = p2_pos - p1_pos;
            const zmdvec = zm.Vec{ direction_vec[0], direction_vec[1], direction_vec[2], 1 };
            const dist_sq = zm.dot3(zmdvec, zmdvec)[0];

            // Using the softening factor to avoid division by zero and extreme accelerations.
            // Force = G * m1 * m2 / (r^2 + s^2)
            // Acceleration = Force / m1 = G * m2 / (r^2 + s^2)
            // As we assume all masses (m2) are 1, acceleration magnitude is G / (r^2 + s^2).
            if (dist_sq > 0.00001) { // Only calculate if particles are not at the exact same spot.
                const force_mag = G / (dist_sq + softening_sq);

                const f = (force_mag / @sqrt(dist_sq));
                const acceleration = .{ f * direction_vec[0], f * direction_vec[1], f * direction_vec[2] };
                total_acceleration += acceleration;
            }
        }

        // Update velocity using Symplectic Euler integration: v_new = v_old + a * dt
        velocities[i] += .{ total_acceleration[0] * dt, total_acceleration[1] * dt, total_acceleration[2] * dt };
    }

    // After calculating all new velocities, update all particle positions.
    // This two-step process (update all velocities, then all positions) is more stable.
    for (positions, 0..) |*pos, i| {
        // p_new = p_old + v_new * dt
        pos.* += .{
            velocities[i][0] * dt,
            velocities[i][1] * dt,
            velocities[i][2] * dt,
        };
    }
}
