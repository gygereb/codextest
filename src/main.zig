const std = @import("std");

const WorldSize = 16;
const VoxelCount = WorldSize * WorldSize * WorldSize;

const Voxel = struct {
    solid: bool,
    color: [3]f32,
};

const MaskCell = struct {
    solid: bool,
    color: [3]f32,
    normal: [3]f32,
};

var world: [VoxelCount]Voxel = undefined;
var mesh_buffer: std.ArrayList(f32) = undefined;
var mesh_ptr: u32 = 0;
var mesh_len: u32 = 0;

fn idx(x: usize, y: usize, z: usize) usize {
    return x + y * WorldSize + z * WorldSize * WorldSize;
}

fn voxelAt(x: i32, y: i32, z: i32) ?Voxel {
    if (x < 0 or y < 0 or z < 0) return null;
    if (x >= WorldSize or y >= WorldSize or z >= WorldSize) return null;
    return world[idx(@as(usize, @intCast(x)), @as(usize, @intCast(y)), @as(usize, @intCast(z)))];
}

fn pushVertex(buffer: *std.ArrayList(f32), pos: [3]f32, normal: [3]f32, color: [3]f32) !void {
    try buffer.appendSlice(&.{ pos[0], pos[1], pos[2], normal[0], normal[1], normal[2], color[0], color[1], color[2] });
}

fn addQuad(
    buffer: *std.ArrayList(f32),
    origin: [3]f32,
    du: [3]f32,
    dv: [3]f32,
    normal: [3]f32,
    color: [3]f32,
    flip: bool,
) !void {
    var v0 = origin;
    var v1 = origin;
    var v2 = origin;
    var v3 = origin;

    if (flip) {
        v1[0] += dv[0];
        v1[1] += dv[1];
        v1[2] += dv[2];

        v2[0] += du[0] + dv[0];
        v2[1] += du[1] + dv[1];
        v2[2] += du[2] + dv[2];

        v3[0] += du[0];
        v3[1] += du[1];
        v3[2] += du[2];
    } else {
        v1[0] += du[0];
        v1[1] += du[1];
        v1[2] += du[2];

        v2[0] += du[0] + dv[0];
        v2[1] += du[1] + dv[1];
        v2[2] += du[2] + dv[2];

        v3[0] += dv[0];
        v3[1] += dv[1];
        v3[2] += dv[2];
    }

    try pushVertex(buffer, v0, normal, color);
    try pushVertex(buffer, v1, normal, color);
    try pushVertex(buffer, v2, normal, color);

    try pushVertex(buffer, v0, normal, color);
    try pushVertex(buffer, v2, normal, color);
    try pushVertex(buffer, v3, normal, color);
}

fn buildWorld() void {
    var z: usize = 0;
    while (z < WorldSize) : (z += 1) {
        var y: usize = 0;
        while (y < WorldSize) : (y += 1) {
            var x: usize = 0;
            while (x < WorldSize) : (x += 1) {
                const fx = @as(f32, @floatFromInt(x)) / @as(f32, WorldSize - 1);
                const fy = @as(f32, @floatFromInt(y)) / @as(f32, WorldSize - 1);
                const fz = @as(f32, @floatFromInt(z)) / @as(f32, WorldSize - 1);
                const dx = fx - 0.5;
                const dy = fy - 0.5;
                const dz = fz - 0.5;
                const dist = @sqrt(dx * dx + dy * dy + dz * dz);
                const solid = dist < 0.55;
                world[idx(x, y, z)] = .{
                    .solid = solid,
                    .color = .{ fx, fy, fz },
                };
            }
        }
    }
}

fn buildMesh(allocator: std.mem.Allocator) !void {
    mesh_buffer = std.ArrayList(f32).init(allocator);

    const dims = [_]usize{ WorldSize, WorldSize, WorldSize };
    var mask = try allocator.alloc(MaskCell, WorldSize * WorldSize);
    defer allocator.free(mask);

    var d: usize = 0;
    while (d < 3) : (d += 1) {
        const u: usize = (d + 1) % 3;
        const v: usize = (d + 2) % 3;
        var x = [_]i32{ 0, 0, 0 };
        var q = [_]i32{ 0, 0, 0 };
        q[d] = 1;

        x[d] = 0;
        while (x[d] <= @as(i32, @intCast(dims[d]))) : (x[d] += 1) {
            var n: usize = 0;
            x[v] = 0;
            while (x[v] < @as(i32, @intCast(dims[v]))) : (x[v] += 1) {
                x[u] = 0;
                while (x[u] < @as(i32, @intCast(dims[u]))) : (x[u] += 1) {
                    const a = voxelAt(x[0], x[1], x[2]);
                    const b = voxelAt(x[0] - q[0], x[1] - q[1], x[2] - q[2]);
                    if (a != null and b == null and a.?.solid) {
                        mask[n] = .{
                            .solid = true,
                            .color = a.?.color,
                            .normal = .{ -@as(f32, @floatFromInt(q[0])), -@as(f32, @floatFromInt(q[1])), -@as(f32, @floatFromInt(q[2])) },
                        };
                    } else if (a == null and b != null and b.?.solid) {
                        mask[n] = .{
                            .solid = true,
                            .color = b.?.color,
                            .normal = .{ @as(f32, @floatFromInt(q[0])), @as(f32, @floatFromInt(q[1])), @as(f32, @floatFromInt(q[2])) },
                        };
                    } else {
                        mask[n] = .{ .solid = false, .color = .{ 0, 0, 0 }, .normal = .{ 0, 0, 0 } };
                    }
                    n += 1;
                }
            }

            var j: usize = 0;
            while (j < dims[v]) : (j += 1) {
                var i: usize = 0;
                while (i < dims[u]) {
                    const idx_mask = i + j * dims[u];
                    const cell = mask[idx_mask];
                    if (!cell.solid) {
                        i += 1;
                        continue;
                    }

                    var w: usize = 1;
                    while (i + w < dims[u]) : (w += 1) {
                        const next_cell = mask[idx_mask + w];
                        if (!next_cell.solid or !std.mem.eql(f32, next_cell.color[0..], cell.color[0..]) or !std.mem.eql(f32, next_cell.normal[0..], cell.normal[0..])) break;
                    }

                    var h: usize = 1;
                    while (j + h < dims[v]) : (h += 1) {
                        var k: usize = 0;
                        var row_ok = true;
                        while (k < w) : (k += 1) {
                            const check_cell = mask[idx_mask + k + h * dims[u]];
                            if (!check_cell.solid or !std.mem.eql(f32, check_cell.color[0..], cell.color[0..]) or !std.mem.eql(f32, check_cell.normal[0..], cell.normal[0..])) {
                                row_ok = false;
                                break;
                            }
                        }
                        if (!row_ok) break;
                    }

                    var origin = [_]f32{ @as(f32, @floatFromInt(x[0])), @as(f32, @floatFromInt(x[1])), @as(f32, @floatFromInt(x[2])) };
                    origin[u] += @as(f32, @floatFromInt(i));
                    origin[v] += @as(f32, @floatFromInt(j));

                    var du = [_]f32{ 0, 0, 0 };
                    var dv = [_]f32{ 0, 0, 0 };
                    du[u] = @as(f32, @floatFromInt(w));
                    dv[v] = @as(f32, @floatFromInt(h));

                    const flip = cell.normal[d] < 0;
                    try addQuad(&mesh_buffer, origin, du, dv, cell.normal, cell.color, flip);

                    var jj: usize = 0;
                    while (jj < h) : (jj += 1) {
                        var ii: usize = 0;
                        while (ii < w) : (ii += 1) {
                            mask[idx_mask + ii + jj * dims[u]].solid = false;
                        }
                    }

                    i += w;
                }
            }
        }
    }

    mesh_ptr = @as(u32, @intCast(@ptrToInt(mesh_buffer.items.ptr)));
    mesh_len = @as(u32, @intCast(mesh_buffer.items.len));
}

export fn build_mesh() void {
    buildWorld();
    var allocator = std.heap.wasm_allocator;
    buildMesh(allocator) catch {};
}

export fn mesh_data_ptr() u32 {
    return mesh_ptr;
}

export fn mesh_data_len() u32 {
    return mesh_len;
}
