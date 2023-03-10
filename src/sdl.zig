const std = @import("std");
const io = std.io;
const sdl = @import("zsdl");
const stbi = @import("zstbi");
const gl = @import("zopengl");
const zm = @import("zmath");
const m2 = @import("m2.zig");

const gl_major = 3;
const gl_minor = 3;

const vertexShaderSource =
\\#version 330 core
\\layout (location = 0) in vec3 position;
\\layout (location = 1) in vec3 normal;
\\layout (location = 2) in vec2 uv;
\\out vec2 TexCoord;
\\uniform mat4 mvp;
\\void main()
\\{
\\  gl_Position = mvp * vec4(position, 1.0);
\\  TexCoord = uv;
\\}
;

const fragmentShaderSource =
\\#version 330 core
\\out vec4 FragColor;
\\in vec2 TexCoord;
\\uniform vec4 ourColor;
\\uniform sampler2D ourTexture;
\\void main()
\\{
\\  FragColor = texture(ourTexture,TexCoord) * ourColor;
\\}
;


const Vertex = extern struct{
    pos: [3]f32,
    uv: [2]f32,
    normal: [3]f32,
};


pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var allocator = gpa.allocator();
    
    stbi.init(allocator);
    defer stbi.deinit();

    try sdl.init(.{ .audio = true, .video = true });
    defer sdl.quit();
    const window = try sdl.Window.create(
        "Model viewer",
        sdl.Window.pos_undefined,
        sdl.Window.pos_undefined,
        600,
        600,
        .{ .opengl = true, .allow_highdpi = true },
    );
    defer window.destroy();

    const gl_context = try sdl.gl.createContext(window);
    defer sdl.gl.deleteContext(gl_context);

    try sdl.gl.makeCurrent(window, gl_context);
    try sdl.gl.setSwapInterval(0);

    try gl.loadCoreProfile(sdl.gl.getProcAddress, gl_major, gl_minor);
    gl.enable(gl.CULL_FACE);
    gl.enable(gl.DEPTH_TEST);
    gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
    gl.enable(gl.BLEND);

    var extensions = gl.getString(gl.EXTENSIONS);
    var iter = std.mem.split(gl.Ubyte, std.mem.span(extensions), " ");
    std.debug.print("extensions: \n", .{});
    while(iter.next()) |ext| {
        if(std.mem.indexOf(u8, ext, "compression")) |_|{
            std.debug.print("{s}\n", .{ext});
        }
    }

    const window_size = window.getSize();
    const drawable_size = sdl.gl.getDrawableSize(window);

    std.debug.print("Window size is {d}x{d}\n", .{window_size[0], window_size[1]});
    std.debug.print("Drawable size is {d}x{d}\n", .{drawable_size[0], drawable_size[1]});



    var data = @embedFile("assets/Creature/bear/bear.m2");
    var model: m2.M2Model = try m2.parseM2(allocator, data[0..]);
    defer model.deinit();
    std.debug.print("model name: {s}\n", .{model.name});
    var viewModel = ViewModel.init(model);
    defer viewModel.deinit();

    //texture
    const bear_blp = @embedFile("assets/Creature/bear/BearSkinBlack.blp");
    var bear_texture = try make_compressed_texture(gpa.allocator(), bear_blp);
    defer gl.deleteTextures(1, &bear_texture);

    const view = zm.lookAtRh(
        zm.f32x4(0, 4, 2, 1),
        zm.f32x4(0, 0, 1, 1),
        zm.f32x4(0, 0, 1, 0),
    );
    const proj = zm.perspectiveFovRh(
        (std.math.pi / 4.0),
        @intToFloat(f32, drawable_size[0]) / @intToFloat(f32, drawable_size[1]),
        0.1,
        20,
    );
    var vp = zm.mul(view, proj);




    //const wall_data = @embedFile("assets/wall.jpg");
    //var image = try stbi.Image.initFromData(wall_data, 4);
    //defer image.deinit();
    //var wall_texture = try make_simple_texture(image.width, image.height, image.data);
    //var VAO = create_debug_square();

        
    var program = create_program();
    defer gl.deleteProgram(program);
    var colorLocation = gl.getUniformLocation(program, @ptrCast([*c]const i8, "ourColor"));
    var mvpLocation = gl.getUniformLocation(program, @ptrCast([*c]const i8, "mvp"));
    var textureLocation = gl.getUniformLocation(program, @ptrCast([*c]const i8, "ourTexture"));
    //_ = mvp;
    //_ = mvpLocation;
    if(colorLocation == -1){
        std.debug.print("Failed to get location for: {s}\n", .{ "ourColor" });
    }
    if(textureLocation == -1){
        std.debug.print("Failed to get location for: {s}\n", .{ "ourTexture" });
    }
    if(mvpLocation == -1){
        std.debug.print("Failed to get location for: {s}\n", .{ "mvp" });
    }

    var freq: u64 = sdl.getPerformanceFrequency();
    var last: u64 = 0;
    var now: u64 = sdl.getPerformanceCounter();

    var rotnum: f32 = 0;
    var rot_delta: f32 = 0;
    var modelMatrix = zm.identity();
    //std.debug.print("time: {} freq: {}\n", .{now, freq});
    main_loop: while(true) {
        last = now;
        now = sdl.getPerformanceCounter();
        const delta_time: f32 = @intToFloat(f32, now-last) / @intToFloat(f32, freq);

        //var mousePos: [2]i32 = [_]i32{0,0};
        //Process events and inputs
        var event: sdl.Event = undefined;
        while(sdl.pollEvent(&event)) {
            switch(event.type){
                .quit => break :main_loop,
                .keyup => {
                    if(event.key.keysym.sym == .escape)
                        break :main_loop;

                    if(event.key.keysym.sym == .a){
                        rot_delta = 0;
                    } else if(event.key.keysym.sym == .d) {
                        rot_delta = 0;
                    }
                },
                .keydown => {
                    if(event.key.keysym.sym == .a) {
                        rot_delta = -3;
                    }
                    else if(event.key.keysym.sym == .d) {
                        rot_delta =  3;
                    }
                },
                .mousemotion => {},
                else => {}
            }
        }

        //Update
        rotnum = delta_time*rot_delta;
        const rot = zm.rotationZ( rotnum * (std.math.pi / 5.0));
        modelMatrix = zm.mul(rot, modelMatrix);
        var mvp = zm.mul(modelMatrix, vp);

        //_ = VAO;
        //_ = wall_texture;
        // render
        gl.clearColor(1.0, 0.0, 1.0, 1.0);
        gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
        gl.uniform1i(textureLocation, 0);

        gl.useProgram(program);
        gl.cullFace(gl.BACK);
        //gl.frontFace(gl.CW);
        gl.uniform4f(colorLocation, 1.0, 1.0, 1.0, 1.0);
        gl.uniformMatrix4fv(mvpLocation, 1, gl.FALSE, @ptrCast([*c]const gl.Float,  &mvp));
        gl.bindTexture(gl.TEXTURE_2D, bear_texture);
        viewModel.draw();
        gl.bindVertexArray(0);
        gl.useProgram(0);


        sdl.gl.swapWindow(window);
    }
}

const  ViewModel  = struct {
    VAO: u32,
    EBO: u32,
    VBO: u32,

    pub fn initVI(comptime Tv: type, comptime Ti: type, vertices: []Tv, indices: []Ti) ViewModel {
        const vertexSize: isize = @sizeOf(Tv);
        const indexSize: isize = @sizeOf(Ti);
        var VAO: u32 = undefined;
        var EBO: u32 = undefined;
        var VBO: u32 = undefined;
        gl.genVertexArrays(1, &VAO);
        gl.genBuffers(1, &EBO);
        gl.genBuffers(1, &VBO);

        var data_size = vertexSize * @intCast(isize, vertices.len);
        gl.bindVertexArray(VAO);
        gl.bindBuffer(gl.ARRAY_BUFFER, VBO);
        gl.bufferData(gl.ARRAY_BUFFER, data_size,  @ptrCast(*const anyopaque, vertices), gl.STATIC_DRAW);
        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, EBO);
        gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, indexSize *  @intCast(isize, indices.len), @ptrCast(*const anyopaque, indices), gl.STATIC_DRAW);

        gl.enableVertexAttribArray(0);
        gl.vertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, @sizeOf(Tv), null);
        gl.bindBuffer(gl.ARRAY_BUFFER, 0);
        gl.bindVertexArray(0);

        return ViewModel {
            .VAO = VAO,
            .EBO = EBO,
            .VBO = VBO,
        };
    }

    pub fn init(model: m2.M2Model) ViewModel {
        const vertexSize: isize = @sizeOf(m2.Vertex);
        const indexSize: isize = @sizeOf(u16);
        //_ = model;
        var VAO: u32 = undefined;
        var EBO: u32 = undefined;
        var VBO: u32 = undefined;

        gl.genVertexArrays(1, &VAO);
        gl.genBuffers(1, &EBO);
        gl.genBuffers(1, &VBO);


        var data_size = vertexSize * @intCast(isize, model.global_vertices.len);
        std.debug.print("global_vertices length: {} data_size: {}\n", .{ model.global_vertices.len, model.triangles.len });
        gl.bindVertexArray(VAO);
        gl.bindBuffer(gl.ARRAY_BUFFER, VBO);
        gl.bufferData(gl.ARRAY_BUFFER, data_size,  @ptrCast(*const anyopaque, model.global_vertices), gl.STATIC_DRAW);
        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, EBO);
        gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, indexSize *  @intCast(isize, model.triangles.len), @ptrCast(*const anyopaque, model.triangles), gl.STATIC_DRAW);

        gl.enableVertexAttribArray(0);
        gl.vertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, @sizeOf(m2.Vertex), null);
        gl.enableVertexAttribArray(1);
        gl.vertexAttribPointer(1, 3, gl.FLOAT, gl.FALSE, @sizeOf(m2.Vertex), @intToPtr(*const anyopaque, @offsetOf(m2.Vertex, "normal")));
        gl.enableVertexAttribArray(2);
        gl.vertexAttribPointer(2, 2, gl.FLOAT, gl.FALSE, @sizeOf(m2.Vertex), @intToPtr(*const anyopaque, @offsetOf(m2.Vertex, "uv")));
        gl.bindBuffer(gl.ARRAY_BUFFER, 0);
        gl.bindVertexArray(0);

        return ViewModel {
            .VAO = VAO,
            .EBO = EBO,
            .VBO = VBO,
        };
    }

    pub fn deinit(self: *ViewModel) void {
        gl.deleteVertexArrays(1, &self.VAO);
        gl.deleteBuffers(1, &self.EBO);
        gl.deleteBuffers(1, &self.VBO);
    }

    pub fn draw(self: *ViewModel) void {
        gl.bindVertexArray(self.VAO);
        gl.drawElements(gl.TRIANGLES, 1860, gl.UNSIGNED_SHORT, null);
        gl.bindVertexArray(0);
    }
};

pub fn make_simple_texture(width:u32 , height:u32, data: []const u8) !u32 {
    var tex: c_uint = undefined;
    gl.genTextures(1, &tex);
    //defer gl.deleteTextures(1, &tex);
    gl.bindTexture(gl.TEXTURE_2D, tex);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);

    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGB, @intCast(c_int, width), @intCast(c_int, height), 0, gl.RGB, gl.UNSIGNED_BYTE, data.ptr);
    gl.generateMipmap(gl.TEXTURE_2D);    
    gl.bindTexture(gl.TEXTURE_2D, 0);

    return tex;
}

pub fn make_compressed_texture(allocator: std.mem.Allocator, data: []const u8) !u32 {
    //_ = allocator;
    var parse_source = io.fixedBufferStream(data);
    try parse_source.seekableStream().seekTo(0);
    const header = try parse_source.reader().readStruct(m2.BlpHeader);

    std.debug.print("{}x{} {} {}\n", .{ header.width, header.height, header.format, header.alpha_size });
    std.debug.print("{any} {any}\n", .{ header.mip_offsets, header.mip_sizes });

    var tex: c_uint = undefined;
    gl.genTextures(1, &tex);
    //defer gl.deleteTextures(1, &tex);
    gl.bindTexture(gl.TEXTURE_2D, tex);
    //gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT);
    //gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT);




    //const mip_level = 0;
    var mip_max: usize = if(header.mips_flags > 0) 10 else 1;

    for(0..mip_max) |mip_level|{
        try parse_source.seekableStream().seekTo(header.mip_offsets[mip_level]);
        var buf = try allocator.alloc(u8, header.mip_sizes[mip_level]);
        defer allocator.free(buf);
        try parse_source.reader().readNoEof(buf[0..]);
        var image_size = header.mip_sizes[mip_level];
        if(image_size == 0) continue;
        std.debug.print("data len: {}, image_size: {}\n", .{data.len, image_size});
        switch(header.format){
            .dxt3 => gl.compressedTexImage2D(gl.TEXTURE_2D, @intCast(i32, mip_level), gl.COMPRESSED_RGBA_S3TC_DXT3_EXT, @intCast(c_int, header.width), @intCast(c_int, header.height), 0, @intCast(c_int, image_size), @ptrCast(*const anyopaque, buf)),
            .dxt5 => gl.compressedTexImage2D(gl.TEXTURE_2D, @intCast(i32, mip_level), gl.COMPRESSED_RGBA_S3TC_DXT5_EXT, @intCast(c_int, header.width), @intCast(c_int, header.height), 0, @intCast(c_int, image_size), @ptrCast(*const anyopaque, buf)),
            else => {
                std.debug.panic("Unsupported", .{});
            }
        }
    }


    gl.generateMipmap(gl.TEXTURE_2D);    
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);

    //glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB, width, height, 0, GL_RGB, GL_UNSIGNED_BYTE, data);
    gl.bindTexture(gl.TEXTURE_2D, 0);

    return tex;
}

fn create_debug_square() u32 {
    var vertices = [_]Vertex{
        .{
            .pos = .{ 0.5,  0.5, 0.0 },
            .normal = .{ 0.5,  0.5, 0.0 },
            .uv = .{ 1.0,  1.0 },
            //.bone_w = .{ },
            //.bone_idx = .{ },
            //.unk = .{ 0.0,  0.0 },
        },
        .{
            .pos = .{ 0.5, -0.5, 0.0 },
            .normal = .{ 0.5,  0.5, 0.0 },
            .uv = .{ 1.0,  0.0 },
            //.bone_w = .{ },
            //.bone_idx = .{ },
            //.unk = .{ 0.0,  0.0 },
        },
        .{
            .pos = .{-0.5, -0.5, 0.0 },
            .uv = .{ 0.0,  0.0 },
            //.bone_w = .{ },
            //.bone_idx = .{ },
            .normal = .{ 0.5,  0.5, 0.0 },
            //.unk = .{ 0.0,  0.0 },
        },
        .{
            .pos = .{-0.5,  0.5, 0.0 },
            .uv = .{ 0.0,  1.0 },
            //.bone_w = .{ },
            //.bone_idx = .{ },
            .normal = .{ 0.5,  0.5, 0.0 },
            //.unk = .{ 0.0,  0.0 },
        },

        .{
            .pos = .{ 1.0,  1.0, 0.0 },
            .uv = .{ 1.0,  1.0 },
            //.bone_w = .{ },
            //.bone_idx = .{ },
            .normal = .{ 0.5,  0.5, 0.0 },
            //.unk = .{ 0.0,  0.0 },
        },
        .{
            .pos = .{1.0, -1.0, 0.0, },
            .uv = .{ 0.0,  0.0 },
            //.bone_w = .{ },
            //.bone_idx = .{ },
            .normal = .{ 0.5,  0.5, 0.0 },
            //.unk = .{ 0.0,  0.0 },
        },
        .{
            .pos = .{-1.0, -1.0, 0.0, },
            .uv = .{ 1.0,  0.0 },
            //.bone_w = .{ },
            //.bone_idx = .{ },
            .normal = .{ 0.5,  0.5, 0.0 },
            //.unk = .{ 0.0,  0.0 },
        },
        .{
            .pos = .{-1.0,  1.0, 0.0, },
            .uv = .{ 0.0,  1.0 },
            //.bone_w = .{ },
            //.bone_idx = .{ },
            .normal = .{ 0.5,  0.5, 0.0 },
            //.unk = .{ 0.0,  0.0 },
        },
    };

    var indices = [_]u16{
        0,1,3,
        1,2,3,

        4,5,7,
        5,6,7,
    };

    var VAO: u32 = undefined;
    gl.genVertexArrays(1, &VAO);
    defer gl.deleteVertexArrays(1, &VAO);

    var EBO: u32 = undefined;
    gl.genBuffers(1, &EBO);
    defer gl.deleteBuffers(1, &EBO);

    var VBO: u32 = undefined;
    gl.genBuffers(1, &VBO);
    defer gl.deleteBuffers(1, &VBO);

    gl.bindVertexArray(VAO);
    gl.bindBuffer(gl.ARRAY_BUFFER, VBO);
    gl.bufferData(gl.ARRAY_BUFFER, @sizeOf(Vertex) * vertices.len, &vertices, gl.STATIC_DRAW);
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, EBO);
    gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, @sizeOf(u16) * indices.len, &indices, gl.STATIC_DRAW);

    gl.enableVertexAttribArray(0);
    gl.vertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, @sizeOf(Vertex), null);

    gl.enableVertexAttribArray(1);
    gl.vertexAttribPointer(1, 3, gl.FLOAT, gl.FALSE, @sizeOf(Vertex), @intToPtr(*const anyopaque, @offsetOf(Vertex, "normal")));

    gl.enableVertexAttribArray(2);
    gl.vertexAttribPointer(2, 2, gl.FLOAT, gl.FALSE, @sizeOf(Vertex), @intToPtr(*const anyopaque, @offsetOf(Vertex, "uv")));

    gl.bindBuffer(gl.ARRAY_BUFFER, 0);
    gl.bindVertexArray(0);

    return VAO;
}


fn draw_debug_square(VAO: u32) void {
    gl.cullFace(gl.FRONT);
    gl.bindVertexArray(VAO);
        gl.drawElements(gl.TRIANGLES, 6, gl.UNSIGNED_SHORT, null);

        //gl.uniform4f(colorLocation, 0.0, 0.0, 1.0, 1.0);
        //gl.drawElements(gl.TRIANGLES, 6, gl.UNSIGNED_SHORT, @intToPtr(*const anyopaque, @sizeOf(u16)*6));

    gl.bindVertexArray(0);
}


fn create_program() u32 {
    var program = gl.createProgram();
    var success: i32 = 0;
    var vertexShader = gl.createShader(gl.VERTEX_SHADER);
    gl.shaderSource(vertexShader, 1, @ptrCast([*c]const [*c]const i8, &vertexShaderSource), null);
    //gl.shaderSource(vertexShader, 1, &vertexShaderSource, null);
    gl.compileShader(vertexShader);
    gl.getShaderiv(vertexShader, gl.COMPILE_STATUS, &success);
    if(success != gl.TRUE){
        var infoLog: [512]u8 = undefined;
        var logSize: usize = 0;
        gl.getShaderInfoLog(vertexShader, 512,  @ptrCast([*c]c_int, &logSize), @ptrCast([*c]i8, &infoLog));
        std.debug.print("Failed to compile vertex shader: {s}\n", .{ infoLog[0..logSize] });
    }

    var fragmentShader = gl.createShader(gl.FRAGMENT_SHADER);
    gl.shaderSource(fragmentShader, 1, @ptrCast([*c]const [*c]const i8, &fragmentShaderSource), null);
    //gl.shaderSource(fragmentShader, 1, &fragmentShaderSource, null);
    gl.compileShader(fragmentShader);

    gl.getShaderiv(fragmentShader, gl.COMPILE_STATUS, &success);
    if(success != gl.TRUE){
        var infoLog: [512]u8 = undefined;
        var logSize: usize = 0;
        gl.getShaderInfoLog(fragmentShader, 512, @ptrCast([*c]c_int, &logSize), @ptrCast([*c]i8, &infoLog));
        std.debug.print("Failed to compile fragment shader:  {s}\n", .{  infoLog[0..logSize] });
    }

    gl.attachShader(program, vertexShader);
    gl.attachShader(program, fragmentShader);

    gl.linkProgram(program);
    gl.deleteShader(vertexShader);
    gl.deleteShader(fragmentShader);

    return program;
}