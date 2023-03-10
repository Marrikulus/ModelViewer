struct Uniforms {
  mvp : mat4x4<f32>,
};
@group(0) @binding(0) var<uniform> uniforms : Uniforms;

struct VertexOutput {
    @builtin(position) Position: vec4<f32>,
    @location(0) normal: vec3<f32>,
    @location(1) uv: vec2<f32>,
}

@vertex fn main(
    @location(0) position: vec3<f32>,
    @location(1) normal: vec3<f32>,
    @location(2) uv: vec2<f32>,
) -> VertexOutput {
    var output : VertexOutput;
    //output.Position = vec4<f32>(position.x, -position.z, position.y, 1.0) * uniforms.mvp;
    output.Position = vec4<f32>(position, 1.0) * uniforms.mvp;
    output.normal = normal;
    output.uv = uv;
    //output.color = color;

    return output;
}

