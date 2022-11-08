const std = @import("std");
const io = std.io;
const gpu = @import("gpu");

const List = extern struct {
    num: u32,
    ofs: u32,
};

pub fn M2Array(comptime T: type) type {
    return extern struct {
        const Self = @This();

        count: u32,
        offset: u32,

        pub fn readOne(self: Self, comptime SourceT: type, source: * SourceT) !T {
            try source.seekableStream().seekTo(self.offset);
            switch(@typeInfo(T)){
                .Struct => return try source.reader().readStruct(T),
                .Int => return try source.reader().readIntLittle(T),
                else => @compileError("Unsupported " ++ @typeName(T)),
            }
        }

        pub fn readAll(self: Self, comptime SourceT: type, source: * SourceT, allocator: std.mem.Allocator) ![]T {

            const array = try allocator.alloc(T, self.count);

            var i: usize = 0;
            try source.seekableStream().seekTo(self.offset);
            while (i < self.count) : (i += 1) {
                switch(@typeInfo(T)){
                    .Struct =>  array[i] = try source.reader().readStruct(T),
                    .Int =>  array[i] = try source.reader().readIntLittle(T),
                    else => @compileError("Unsupported " ++ @typeName(T)),
                }
            }
            return array;
        }
    };
}

const Header = extern struct {
    id: u32,
    version: u32,
    name: M2Array(u8),
    model_type: u32,

    global_sequences: List,
    animations: List,
    animation_lookup: List,
    playable_animation_lookup: List,
    bones: List,
    key_bone_lookup: List,

    vertices: M2Array(Vertex),
    views: M2Array(View),
    colors: List,

    textures: M2Array(M2Texture),
    texture_weights: List,
    texture_flipbooks: List,
    texture_transforms: List,
    replaceable_texture_lookup: List,
    texture_flags: List,

    bone_lookup_table: List,
    texture_lookup: List,
    texture_unit_lookup: List,
    texture_weight_lookup: List,
    texture_transforms_lookup: List,

    bounding_box: [6]f32,
    bounding_sphere_radius: f32,
    collision_box: [6]f32,
    collision_sphere_radius: f32,

    bounding_triangles: List,
    bounding_vertices: List,
    bounding_normals: List,

    attachments: List,
    attachment_lookup: List,
    events: List,
    lights: List,
    cameras: List,
    cameraLookup: List,
    ribbon_emitters: List,
    particle_emitters: List,
};


pub const Vertex = extern struct {
    pos:        [3]f32,
    bone_w:     [4]u8,
    bone_idx:   [4]u8,
    normal:     [3]f32,
    uv:         [2]f32,
    unk:        [2]f32,

    pub const desc = gpu.VertexBufferLayout.init(.{
        .array_stride = @sizeOf(Vertex),
        .step_mode = .vertex,
        .attributes = &[_]gpu.VertexAttribute{
            .{ .format = .float32x3, .offset = @offsetOf(Vertex, "pos"), .shader_location = 0 },
            .{ .format = .float32x3, .offset = @offsetOf(Vertex, "normal"), .shader_location = 1 },
            .{ .format = .float32x2, .offset = @offsetOf(Vertex, "uv"), .shader_location = 2 },
        },
    });
};


const View = extern struct {
    //magic: [4]u8,
    vertices: M2Array(u16),
    indices: M2Array(u16),
    bones: List,
    submeshes: M2Array(SubMesh),
    batches: List,
    boneCountMax: u32,
};

const SubMesh = extern struct {
    skinSectionId:u16,
    level:u16,

    vertexStart:u16,
    vertexCount:u16,
    indexStart:u16,
    indexCount:u16,
    boneCount:u16,
    boneComboIndex:u16,
    boneInfluences:u16,
    centerBoneIndex:u16,
    centerPosition: [3]f32,
};

const M2Texture = extern struct {
    type: u32,
    flags: u32,
    filename: M2Array(u8),
};

pub fn dump(comptime T: type, data: *const T) void {
    inline for (std.meta.fields(T)) |f| {
        if(f.field_type == List
 //or f.field_type == M2Array
        ){
            std.debug.print("{s}: {any}\n", .{f.name, @field(data, f.name)});
        } else {
            std.debug.print("{s}: {any}\n", .{f.name, @field(data, f.name)});
        }
    }
}


pub const M2Model = struct {
    allocator: std.mem.Allocator,
    name: []u8,
    global_vertices: []Vertex,
    indices: []u16,
    triangles: []u16,
    submeshes: []SubMesh,
    textures: []M2Texture,
    texture_names: [][]u8,

    const Self = @This();
    //pub fn init(allocator: std.mem.Allocator) Self {
    //    return Self{
    //        .allocator = allocator,
    //        .name = null,
    //        .global_vertices = null,
    //    };
    //}

    pub fn deinit(self: Self) void {
        self.allocator.free(self.name);
        self.allocator.free(self.global_vertices);
        self.allocator.free(self.indices);
        self.allocator.free(self.triangles);
        self.allocator.free(self.submeshes);
        self.allocator.free(self.textures);

        self.allocator.free(self.texture_names);
    }
    
};



pub fn parseM2(allocator: std.mem.Allocator, data: []const u8) !M2Model {
    //var model = M2Model.init(allocator);
    
    var parse_source  = io.fixedBufferStream(data);
    
    try parse_source.seekableStream().seekTo(0);
    const header = try parse_source.reader().readStruct(Header);
    dump(Header, &header);
    const name = try header.name.readAll(@TypeOf(parse_source), &parse_source, allocator);
    const global_vertices = try header.vertices.readAll(@TypeOf(parse_source), &parse_source, allocator);
    const view = try header.views.readOne(@TypeOf(parse_source), &parse_source);
    //dump(View, &view);
    //std.debug.print("\n\n", .{});


    const indices = try view.vertices.readAll(@TypeOf(parse_source), &parse_source, allocator);
    const triangles = try view.indices.readAll(@TypeOf(parse_source), &parse_source, allocator);
    const textures = try header.textures.readAll(@TypeOf(parse_source), &parse_source, allocator);

    const names = try allocator.alloc([]u8, textures.len);
    for(textures) |tex| {
        dump(M2Texture, &tex);
        //if(tex.type == 0) {
        //}

        const filename = try tex.filename.readAll(@TypeOf(parse_source), &parse_source, allocator);
        std.debug.print("\n\n{s}\n\n", .{ filename });
        allocator.free(filename);
    }
    return M2Model{
        .allocator = allocator,
        .name = name,
        .global_vertices = global_vertices,
        .indices = indices,
        .triangles = triangles,
        .submeshes = try view.submeshes.readAll(@TypeOf(parse_source), &parse_source, allocator),
        .textures = textures,
        .texture_names = names,
    };
}

const BlpColorEncoding = enum(u8) {
    jpeg,
    palette,
    dxt,
    argb8888,
    argb8888_dup,
};

const BlpPixelFormat = enum(u8) {
    dxt1,
    dxt3,
    argb8888,
    argb1555,
    argb4444,
    rgb565,
    a8,
    dxt5,
    unspecified,
    argb2565,
    unk,
    pixel_bc5, // dxgi_format_bc5_unorm 
    num_pixel_formats = 12, // (no idea if format=10 exists)
};

const BlpMipLvlAndFlags = enum(u8) {
    MIPS_NONE = 0x0,
    MIPS_GENERATED = 0x1,
    MIPS_HANDMADE = 0x2, // not supported
    flags_mipmap_mask = 0xF, // level
    flags_unk_0x10 = 0x10,
};

pub const BlpHeader = extern struct {
    id: [4]u8,
    version: u32,
    encoding: BlpColorEncoding,
    alpha_size: u8,
    format: BlpPixelFormat,
    mips_flags: u8,
    width: u32,
    height: u32,
    mip_offsets: [16]u32,
    mip_sizes: [16]u32,
    palette: [256]u32,
};

pub fn parseBlp(allocator: std.mem.Allocator, data: []const u8) !void {
    var parse_source  = io.fixedBufferStream(data);
    
    _ = allocator;
    try parse_source.seekableStream().seekTo(0);
    const header = try parse_source.reader().readStruct(BlpHeader);
    if(!std.mem.eql(u8, "BLP2", &header.id)) return error.InvalidData;
    if(header.version != 1) return error.InvalidData;

    
    std.debug.print("\n\nname: {s}\nversion: {any}\n\n\n", .{ header.id, header.version });
    dump(BlpHeader, &header);

    try parse_source.seekableStream().seekTo(header.mip_offsets[0]);

    //var buf = allocator.alloc(u8, header.mip_sizes[0]);
    var buf: [4]u8 = undefined;
    try parse_source.reader().readNoEof(buf[0..]);
    std.debug.print("{s}", .{buf});

    //TODO: find out which to use
    //DXT3: texture format
    //Texture.Format.bc2_rgba_unorm,
    //Texture.Format.bc2_rgba_unorm_srgb,
}


test "basic test" {

    {
        //const data = @embedFile("assets/Wisp.m2");
        //const model = try parseM2(std.testing.allocator, data[0..]);
        //defer model.deinit();

        const wisp_blp = @embedFile("assets/Creature/Wisp/Wisp.blp");
        try parseBlp(std.testing.allocator, wisp_blp);
        
        const bear_blp = @embedFile("assets/Creature/bear/BearSkinBlack.blp");
        try parseBlp(std.testing.allocator, bear_blp);
    }
}

