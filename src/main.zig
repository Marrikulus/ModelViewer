const std = @import("std");
const io = std.io;
const mach = @import("mach");
const gpu = @import("gpu");
const m2 = @import("m2.zig");

const zm = @import("zmath");

const UniformBufferObject = struct {
    mat: zm.Mat,
};

var timer: mach.Timer = undefined;
var resource_manager: mach.ResourceManager = undefined;

pub const App = @This();

pipeline: *gpu.RenderPipeline,
queue: *gpu.Queue,

bind_group: *gpu.BindGroup,
uniform_buffer: *gpu.Buffer,
depth_texture: ?*gpu.Texture,
depth_texture_view: *gpu.TextureView,

mesh: M2Mesh,
texture: *gpu.Texture,
meshes: []M2Mesh,

rotation_speed: f32 = 5.0,

fn create_index_buffer(comptime T: type, core: *mach.Core, verts: []const T) *gpu.Buffer {
    var size = @sizeOf(T) * verts.len;
    std.debug.print("Index len: {any} {any}\n\n", .{ verts.len, size });
    const buffer = core.device.createBuffer(&.{
        .usage = .{ .index = true },
        .size = size + size % 4,
        .mapped_at_creation = true,
    });
    var buffer_mapped = buffer.getMappedRange(T, 0, verts.len);
    std.mem.copy(T, buffer_mapped.?, verts[0..]);
    buffer.unmap();

    return buffer;
}

fn create_vertex_buffer(comptime T: type, core: *mach.Core, verts: []const T) *gpu.Buffer {
    var size = @sizeOf(T) * verts.len;
    std.debug.print("Vertex len: {any} {any}\n\n", .{ verts.len, size });
    const buffer = core.device.createBuffer(&.{
        .usage = .{ .vertex = true },
        .size = size + size % 4,
        .mapped_at_creation = true,
    });
    var buffer_mapped = buffer.getMappedRange(T, 0, verts.len);
    std.mem.copy(T, buffer_mapped.?, verts[0..]);
    buffer.unmap();

    return buffer;
}

const Context = struct {
    core: *mach.Core,
};

//look at how std.rand.Random.init uses anyopaque
fn loadM2(maybe_ptr: ?*anyopaque, data: []const u8) anyerror!*anyopaque {
    if (maybe_ptr) |ptr| {
        const alignment = @typeInfo(*Context).Pointer.alignment;
        const context = @ptrCast(*Context, @alignCast(alignment, ptr));

        //std.debug.print("\n\ncontext: {any}\nlen:{any} '{s}'\n\n", .{context.core, data.len, data[0..4]});
        return try makeMesh(context.core, data[0..]);
    }
    return error.InvalidResource;
}

fn unloadM2(context: ?*anyopaque, resource: *anyopaque) void {
    std.debug.print("{any} {any}", .{ context, resource });
}
const resTypes: []const mach.ResourceManager.ResourceType = &.{
    //.{ .name = "M2", .load = loadM2, .unload = unloadM2 },
};

pub fn init(app: *App, core: *mach.Core) !void {
    //core.internal.close();

    timer = try mach.Timer.start();

    resource_manager = try mach.ResourceManager.init(core.allocator, &.{"assets/"}, resTypes);
    resource_manager.setLoadContext(Context{ .core = core });
    //std.debug.print("\n\nres_manager: {any}\n\n", .{ resource_manager });

    //var res = resource_manager.getResource("M2://Wisp.m2");
    //std.debug.print("\n\nres: {any}\n\n", .{ res });

    //const data = @embedFile("assets/Shield_Crest_A_01.m2");
    //const data = @embedFile("assets/Wisp.m2");
    var data = @embedFile("assets/Creature/bear/bear.m2");
    app.mesh = try makeMesh(core, data[0..]);

    const bear_blp = @embedFile("assets/Creature/bear/BearSkinBlack.blp");
    app.texture = try texture(core, bear_blp);

    const vs_module = core.device.createShaderModuleWGSL("vert.wgsl", @embedFile("vert.wgsl"));
    const fs_module = core.device.createShaderModuleWGSL("frag.wgsl", @embedFile("frag.wgsl"));

    const color_target = gpu.ColorTargetState{
        .format = core.swap_chain_format,
        .blend = &gpu.BlendState{},
        .write_mask = gpu.ColorWriteMaskFlags.all,
    };
    const pipeline_descriptor = gpu.RenderPipeline.Descriptor{
        .fragment = &gpu.FragmentState.init(.{
            .module = fs_module,
            .entry_point = "main",
            .targets = &.{color_target},
        }),
        .vertex = gpu.VertexState.init(.{
            .module = vs_module,
            .entry_point = "main",
            .buffers = &.{m2.Vertex.desc},
        }),
        .depth_stencil = &.{
            .format = .depth24_plus,
            .depth_write_enabled = true,
            .depth_compare = .less,
        },
        .primitive = .{
            .cull_mode = .back,
        },
    };

    app.pipeline = core.device.createRenderPipeline(&pipeline_descriptor);

    const uniform_buffer = core.device.createBuffer(&.{
        .usage = .{ .copy_dst = true, .uniform = true },
        .size = @sizeOf(UniformBufferObject),
        .mapped_at_creation = false,
    });

    const sampler = core.device.createSampler(&.{
        .mag_filter = .linear,
        .min_filter = .linear,
    });

    const bind_group = core.device.createBindGroup(
        &gpu.BindGroup.Descriptor.init(.{
            .layout = app.pipeline.getBindGroupLayout(0),
            .entries = &.{
                gpu.BindGroup.Entry.buffer(0, uniform_buffer, 0, @sizeOf(UniformBufferObject)),
                gpu.BindGroup.Entry.sampler(1, sampler),
                gpu.BindGroup.Entry.textureView(2, app.texture.createView(&gpu.TextureView.Descriptor{})),
            },
        }),
    );

    app.uniform_buffer = uniform_buffer;
    app.bind_group = bind_group;
    app.depth_texture = null;
    app.depth_texture_view = undefined;

    app.queue = core.device.getQueue();

    vs_module.release();
    fs_module.release();
}

pub fn deinit(app: *App, _: *mach.Core) void {
    app.uniform_buffer.release();
    app.bind_group.release();
    app.depth_texture.?.release();
    app.depth_texture_view.release();

    app.mesh.deinit();
    app.texture.release();
    resource_manager.deinit();
}

pub fn update(app: *App, core: *mach.Core) !void {
    while (core.pollEvent()) |event| {
        switch (event) {
            .key_press => |ev| {
                if (ev.key == .escape)
                    core.close();
                if (ev.key == .space) {
                    if (app.rotation_speed == 0) {
                        app.rotation_speed = 5;
                    } else {
                        app.rotation_speed = 0;
                    }
                }

                if (ev.key == .up)
                    app.rotation_speed += 0.1;
                if (ev.key == .down)
                    app.rotation_speed -= 0.1;
            },
            else => {},
        }
    }

    const back_buffer_view = core.swap_chain.?.getCurrentTextureView();
    const color_attachment = gpu.RenderPassColorAttachment{
        .view = back_buffer_view,
        .clear_value = std.mem.zeroes(gpu.Color),
        .load_op = .clear,
        .store_op = .store,
    };

    const encoder = core.device.createCommandEncoder(null);
    const render_pass_info = gpu.RenderPassDescriptor.init(.{
        .color_attachments = &.{color_attachment},
        .depth_stencil_attachment = &.{
            .view = app.depth_texture_view,
            .depth_clear_value = 1.0,
            .depth_load_op = .clear,
            .depth_store_op = .store,
        },
    });

    {
        const time = timer.read();
        //const model = zm.mul(zm.rotationX(time * (std.math.pi / 2.0)), zm.rotationZ(time * (std.math.pi / 2.0)));
        const model = zm.rotationZ(time * (std.math.pi / 5.0));
        const view = zm.lookAtRh(
            zm.f32x4(0, 4, 2, 1),
            zm.f32x4(0, 0, 1, 1),
            zm.f32x4(0, 0, 1, 0),
        );
        const proj = zm.perspectiveFovRh(
            (std.math.pi / 4.0),
            @intToFloat(f32, core.current_desc.width) / @intToFloat(f32, core.current_desc.height),
            0.1,
            20,
        );
        const mvp = zm.mul(zm.mul(model, view), proj);
        //const mvp = zm.mul(view, proj);
        const ubo = UniformBufferObject{
            .mat = zm.transpose(mvp),
        };
        encoder.writeBuffer(app.uniform_buffer, 0, &[_]UniformBufferObject{ubo});
    }

    const pass = encoder.beginRenderPass(&render_pass_info);
    pass.setPipeline(app.pipeline);
    pass.setBindGroup(0, app.bind_group, &.{});

    pass.setVertexBuffer(0, app.mesh.vertex_buffer, 0, gpu.whole_size);
    pass.setIndexBuffer(app.mesh.index_buffer, .uint16, 0, gpu.whole_size);
    for (app.mesh.model.submeshes) |submesh| {
        //std.debug.print("submesh: {any} \n", .{submesh});
        pass.drawIndexed(submesh.indexCount, 1, submesh.indexStart, 0, 0);
    }

    pass.end();
    pass.release();

    var command = encoder.finish(null);
    encoder.release();

    app.queue.submit(&.{command});
    command.release();
    core.swap_chain.?.present();
    back_buffer_view.release();
}

pub fn resize(app: *App, core: *mach.Core, width: u32, height: u32) !void {
    // If window is resized, recreate depth buffer otherwise we cannot use it.
    if (app.depth_texture != null) {
        app.depth_texture.?.release();
        app.depth_texture_view.release();
    }
    app.depth_texture = core.device.createTexture(&gpu.Texture.Descriptor{
        .size = gpu.Extent3D{
            .width = width,
            .height = height,
        },
        .format = .depth24_plus,
        .usage = .{
            .render_attachment = true,
            .texture_binding = true,
        },
    });

    app.depth_texture_view = app.depth_texture.?.createView(&gpu.TextureView.Descriptor{
        .format = .depth24_plus,
        .dimension = .dimension_2d,
        .array_layer_count = 1,
        .mip_level_count = 1,
    });
}

pub const M2Mesh = struct {
    vertex_buffer: *gpu.Buffer,
    index_buffer: *gpu.Buffer,

    model: m2.M2Model,

    const Self = @This();
    pub fn deinit(self: Self) void {
        self.vertex_buffer.release();
        self.index_buffer.release();
        self.model.deinit();
    }
};

pub fn makeMesh(core: *mach.Core, data: []const u8) !M2Mesh {
    var model = try m2.parseM2(core.allocator, data);

    const vertex_buffer = create_vertex_buffer(m2.Vertex, core, model.global_vertices);
    const index_buffer = create_index_buffer(u16, core, model.triangles);
    var mesh = M2Mesh{
        .vertex_buffer = vertex_buffer,
        .index_buffer = index_buffer,
        .model = model,
    };
    return mesh;
}

pub fn texture(core: *mach.Core, data: []const u8) !*gpu.Texture {
    const mip_level = 0;

    const allocator = core.allocator;
    var parse_source = io.fixedBufferStream(data);
    try parse_source.seekableStream().seekTo(0);
    const header = try parse_source.reader().readStruct(m2.BlpHeader);

    try parse_source.seekableStream().seekTo(header.mip_offsets[mip_level]);
    var buf = try allocator.alloc(u8, header.mip_sizes[mip_level]);
    defer allocator.free(buf);
    try parse_source.reader().readNoEof(buf[0..]);

    const img_size = gpu.Extent3D{ .width = @intCast(u32, header.width), .height = @intCast(u32, header.height) };
    const cube_texture = core.device.createTexture(&.{
        .size = img_size,
        .format = .bc2_rgba_unorm,
        .usage = .{
            .texture_binding = true,
            .copy_dst = true,
            //.render_attachment = true,
        },
    });
    const data_layout = gpu.Texture.DataLayout{
        .bytes_per_row = @intCast(u32, (header.width / 4) * 16),
        //.rows_per_image = @intCast(u32, header.height),
    };

    const queue = core.device.getQueue();
    queue.writeTexture(&.{ .texture = cube_texture }, &data_layout, &img_size, buf);

    return cube_texture;
}

//const vertex_buffer = core.device.createBuffer(&.{
//    .usage = .{ .vertex = true },
//    .size = @sizeOf(f32) * 3 * model.global_vertices.len,
//    .mapped_at_creation = true,
//});
//{
//    var buffer_mapped = vertex_buffer.getMappedRange(f32, 0, 3 * model.global_vertices.len);
//    for(model.global_vertices) |vert, i| {
//        buffer_mapped.?[i*3 + 0] = model.global_vertices[index].position[0];
//        buffer_mapped.?[i*3 + 1] = model.global_vertices[index].position[1];
//        buffer_mapped.?[i*3 + 2] = model.global_vertices[index].position[2;
//    }
//    vertex_buffer.unmap();
//}
//std.debug.print("vert size: {any} * {any} = {any} \n", .{ @sizeOf(Vertex), model.global_vertices.len, @sizeOf(Vertex) * model.global_vertices.len });
//std.debug.print("idx size: {any} * {any} = {any} \n", .{ @sizeOf(u16), model.indices.len, @sizeOf(u16) * model.indices.len });
//std.debug.print("tri size: {any} * {any} = {any} \n", .{ @sizeOf(u16), model.triangles.len, @sizeOf(u16) * model.triangles.len });
//const len = model.triangles.len;
//const index_buffer = core.device.createBuffer(&.{
//    .usage = .{ .index = true },
//    .size = @sizeOf(u16) * len,
//    .mapped_at_creation = true,
//});
//{
//    var buffer_mapped = index_buffer.getMappedRange(u16, 0, len + len % 4);
//    std.debug.print("submesh: {any}..{any}, {any}\n", .{submesh.indexStart, submesh.indexCount, submesh.indexCount / 3});
//    var i = submesh.indexStart;
//    while(i < submesh.indexCount) : (i += 3) {
//        buffer_mapped.?[i] = model.triangles[i];
//        //Flipping from right handed to left handed
//        buffer_mapped.?[i+1] = model.triangles[i+1];
//        buffer_mapped.?[i+2] = model.triangles[i+2];
//    }
//    //for(model.triangles[submesh.indexStart..submesh.indexCount]) |tri, i| {
//    //for(model.triangles[submesh.indexStart..submesh.indexCount]) |tri, i| {
//    //    const idx = model.indices[tri];
//    //    buffer_mapped.?[i] = idx;
//    //    //std.debug.print("{any}: {any} -> {any}\n", .{i, tri, idx });
//    //}
//    //std.mem.copy(u16, buffer_mapped.?, model.triangles[0..submesh.indexCount]);
//    index_buffer.unmap();
//}

