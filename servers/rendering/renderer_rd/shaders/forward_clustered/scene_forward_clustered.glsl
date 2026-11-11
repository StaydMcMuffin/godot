//////////////////////////////////
////  Forward+ Scene Shader  ////

// NOTES:
// `actions.base_varying_index` in `/scene_shader_forward_clustered.cpp` must be kept in-sync with the highest index of the varyings defined here.
// The current highest index is 14, so `base_varying_index` is set to 15.


///////////////////////////////////////////////////////////////////////////////
////  VERTEX STAGE  //////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////

#[vertex]
#version 450
#VERSION_DEFINES


#define SHADER_IS_SRGB		false
#define SHADER_SPACE_FAR	0.0

#ifdef USE_MULTIVIEW
#extension GL_EXT_multiview : enable
#define OUTPUT_IS_MULTIVIEW	true
#define ViewIndex			gl_ViewIndex
#else  // USE_MULTIVIEW
#define OUTPUT_IS_MULTIVIEW	false
#define ViewIndex			0
#endif // USE_MULTIVIEW


#if defined(USE_LIGHTMAP) && !defined(UV2_USED)
#define UV2_USED  // UV2 always used with lightmapping.
#endif // USE_LIGHTMAP && !UV2_USED


#include "../half_inc.glsl"
#include "scene_forward_clustered_inc.glsl"


/////////////////////////////
////  INPUT ATTRIBUTES  ////

// Always contains vertex position in XYZ, can contain tangent angle in W.
layout(location = 0) in vec4 vertex_angle_attrib;

#if defined(NORMAL_USED) || defined(TANGENT_USED)
// Contains Normal/Axis in RG, can contain tangent in BA.
layout(location = 1) in vec4 axis_tangent_attrib;
#endif // NORMAL_USED || TANGENT_USED

// Location 2 is unused.

#ifdef COLOR_USED
layout(location = 3) in vec4 color_attrib;
#endif // COLOR_USED

#ifdef UV_USED
layout(location = 4) in vec2 uv_attrib;
#endif // UV_USED

#if defined(UV2_USED) || defined(MODE_RENDER_MATERIAL)
layout(location = 5) in vec2 uv2_attrib;
#endif // UV2_USED || MODE_RENDER_MATERIAL

#ifdef CUSTOM0_USED
layout(location = 6) in vec4 custom0_attrib;
#endif // CUSTOM0_USED

#ifdef CUSTOM1_USED
layout(location = 7) in vec4 custom1_attrib;
#endif // CUSTOM0_USED

#ifdef CUSTOM2_USED
layout(location = 8) in vec4 custom2_attrib;
#endif // CUSTOM2_USED

#ifdef CUSTOM3_USED
layout(location = 9) in vec4 custom3_attrib;
#endif // CUSTOM3_USED

#if defined(BONES_USED) || defined(USE_PARTICLE_TRAILS)
layout(location = 10) in uvec4 bone_attrib;
#endif // BONES_USED || USE_PARTICLE_TRAILS

#if defined(WEIGHTS_USED) || defined(USE_PARTICLE_TRAILS)
layout(location = 11) in vec4 weight_attrib;
#endif // WEIGHTS_USED || USE_PARTICLE_TRAILS

#ifdef MOTION_VECTORS
layout(location = 12) in vec4 previous_vertex_attrib;
#if defined(NORMAL_USED) || defined(TANGENT_USED)
layout(location = 13) in vec4 previous_normal_attrib;
#endif // NORMAL_USED || TANGENT_USED
#endif // MOTION_VECTORS


invariant gl_Position;
float global_time;

#ifdef MATERIAL_UNIFORMS_USED
/* clang-format off */
layout(set = MATERIAL_UNIFORM_SET, binding = 0, std140) uniform MaterialUniforms
{
#MATERIAL_UNIFORMS
} material;
/* clang-format on */
#endif // MATERIAL_UNIFORMS_USED


//////////////////////////////
////  OUTPUT ATTRIBUTES  ////

layout(location = 0) out vec3 vertex_interp;

#ifdef NORMAL_USED
layout(location = 1) out vec3 normal_interp;
#endif // NORMAL_USED

#ifdef COLOR_USED
layout(location = 2) out vec4 color_interp;
#endif // COLOR_USED

#ifdef UV_USED
layout(location = 3, component = 0) out vec2 uv_interp;
#endif // UV_USED

#if defined(UV2_USED)
layout(location = 3, component = 2) out vec2 uv2_interp;
#endif // UV2_USED

#ifdef TANGENT_USED
layout(location = 4) out vec3 tangent_interp;
layout(location = 5) out vec3 bitangent_interp;
#endif // TANGENT_USED

#ifdef MOTION_VECTORS
layout(location = 6) out vec4 screen_position;
layout(location = 7) out vec4 prev_screen_position;
#endif // MOTION_VECTORS

#ifdef MODE_DUAL_PARABOLOID
layout(location = 8, component = 0) out float dp_clip;
#endif // MODE_DUAL_PARABOLOID

layout(location = 9) out flat uint instance_index_interp;

#ifdef USE_MULTIVIEW
layout(location = 10) out vec4 combined_projected;
#endif // USE_MULTIVIEW

#if !defined(MODE_RENDER_PREPASS) && !defined(MODE_UNSHADED) && defined(USE_VERTEX_LIGHTING)
#if (USE_VERTEX_LIGHTING == 0)  // (Per-vertex standard)
layout(location = 11) out vec4 diffuse_light_interp;
layout(location = 12) out vec4 specular_light_interp;
#else  // USE_VERTEX_LIGHTING == 1  (Per-vertex SH)
layout(location = 8, component = 1) out float sh_spec_scale_interp;
layout(location = 11) out vec4 sh_r_interp;
layout(location = 12) out vec4 sh_g_interp;
layout(location = 13) out vec4 sh_b_interp;
#endif // USE_VERTEX_LIGHTING == 0/1
#endif // !MODE_RENDER_PREPASS && !MODE_UNSHADED && USE_VERTEX_LIGHTING

#if defined(POINT_SIZE_USED) && defined(POINT_COORD_USED)
layout(location = 14) out vec2 point_coord_interp;
#endif // POINT_SIZE_USED || POINT_COORD_USED


/////////////////////////////
////  HELPER FUNCTIONS  ////

#ifdef USE_MULTIVIEW
vec3  multiview_uv (vec2 uv)	{ return  vec3(uv, ViewIndex); }
ivec3 multiview_uv (ivec2 uv)	{ return ivec3(uv, int(ViewIndex)); }
#else // USE_MULTIVIEW
vec2  multiview_uv (vec2 uv)	{ return uv; }
ivec2 multiview_uv (ivec2 uv)	{ return uv; }
#endif // USE_MULTIVIEW


/////////////////////////////////
////  Vertex Stage Globals  ////
#GLOBALS
//////////////////////////////


#if defined(NORMAL_USED) || defined(TANGENT_USED)
void axis_angle_to_tbn (
		vec3 axis, float angle,
		out vec3 tangent, out vec3 bitangent, out vec3 normal
	)
{
	float c = cos(angle);
	float s = sin(angle);
	vec3 omc_axis = (1.0 - c) * axis;
	vec3 s_axis = s * axis;
	tangent = omc_axis.xxx * axis + vec3(c, -s_axis.z, s_axis.y);
	bitangent = omc_axis.yyy * axis + vec3(s_axis.z, c, -s_axis.x);
	normal = omc_axis.zzz * axis + vec3(-s_axis.y, s_axis.x, c);
}
#endif // NORMAL_USED || TANGENT_USED


void _unpack_vertex_attributes (
		in vec4 p_vertex_in,
		in vec3 p_compressed_aabb_position,
		in vec3 p_compressed_aabb_size,
#if defined(NORMAL_USED) || defined(TANGENT_USED)
		in vec4 p_normal_in,
#ifdef NORMAL_USED
		out vec3 r_normal,
#endif // NORMAL_USED
		out vec3 r_tangent,
		out vec3 r_bitangent,
#endif // NORMAL_USED || TANGENT_USED
		out vec3 r_vertex
	)
{
	r_vertex = p_vertex_in.xyz * p_compressed_aabb_size + p_compressed_aabb_position;

#ifdef NORMAL_USED
	r_normal = oct_to_vec3(p_normal_in.xy * 2.0 - 1.0);
#endif // NORMAL_USED

#if defined(NORMAL_USED) || defined(TANGENT_USED)
	// This works because the oct value (0, 1) maps onto (0, 0, -1) which encodes to (1, 1).
	// Accordingly, if p_normal_in.z contains octahedral values, it won't equal (0, 1).
	if (p_normal_in.z > 0.0 || p_normal_in.w < 1.0)
	{
		// Uncompressed format.
		vec2 signed_tangent_attrib = p_normal_in.zw * 2.0 - 1.0;
		r_tangent = oct_to_vec3(vec2(signed_tangent_attrib.x, abs(signed_tangent_attrib.y) * 2.0 - 1.0));
		float bitangent_sign = sign(signed_tangent_attrib.y);
		r_bitangent = normalize(cross(r_normal, r_tangent) * bitangent_sign);
	}
	else
	{
		// Compressed format.
		float angle = p_vertex_in.w;
		float bitangent_sign = angle > 0.5 ? 1.0 : -1.0; // 0.5 does not exist in UNORM16, so values are either greater or smaller.
		angle = abs(angle * 2.0 - 1.0) * M_PI; // 0.5 is basically zero, allowing to encode both signs reliably.
		vec3 axis = r_normal;
		axis_angle_to_tbn(axis, angle, r_tangent, r_bitangent, r_normal);
		r_bitangent *= bitangent_sign;
	}
#endif // NORMAL_USED || TANGENT_USED
}


#if !defined(MODE_RENDER_PREPASS) && !defined(MODE_UNSHADED) && defined(USE_VERTEX_LIGHTING)

#if (USE_VERTEX_LIGHTING == 1)
#include "../sh_inc.glsl"
#endif // USE_VERTEX_LIGHTING == 1
#include "../scene_forward_vertex_lights_inc.glsl"

void cluster_get_item_range (
		uint p_offset,
		out uint item_min, out uint item_max,
		out uint item_from, out uint item_to)
{
	uint item_min_max = cluster_buffer.data[p_offset];
	item_min = item_min_max & 0xFFFFu;
	item_max = item_min_max >> 16;

	item_from = item_min >> 5;
	item_to = (item_max == 0) ? 0 : ((item_max - 1) >> 5) + 1;  // As a side effect of how it's stored, item_max=0 means no elements.
}
uint cluster_get_range_clip_mask (uint i, uint z_min, uint z_max)
{
	int local_min = clamp(int(z_min) - int(i) * 32, 0, 31);
	int mask_width = min(int(z_max) - int(z_min), 32 - local_min);
	return bitfieldInsert(uint(0), uint(0xFFFFFFFF), local_min, mask_width);
}
#endif // !MODE_RENDER_PREPASS && !MODE_UNSHADED && USE_VERTEX_LIGHTING


#ifdef USE_DOUBLE_PRECISION
// Helper functions for emulating double precision when adding floats.
vec3 quick_two_sum (
		vec3 a, vec3 b,
		out vec3 out_p)
{
	vec3 s = a + b;
	out_p = b - (s - a);
	return s;
}
vec3 two_sum (
		vec3 a, vec3 b,
		out vec3 out_p)
{
	vec3 s = a + b;
	vec3 v = s - a;
	out_p = (a - (s - v)) + (b - v);
	return s;
}
vec3 double_add_vec3 (
		vec3 base_a, vec3 prec_a, vec3 base_b, vec3 prec_b,
		out vec3 out_precision)
{
	vec3 s, t, se, te;
	s = two_sum(base_a, base_b, se);
	t = two_sum(prec_a, prec_b, te);
	se += t;
	s = quick_two_sum(s, se, se);
	se += te;
	s = quick_two_sum(s, se, out_precision);
	return s;
}
#endif // USE_DOUBLE_PRECISION

uint multimesh_stride ()
{
	uint stride = sc_multimesh_format_2d() ? 2 : 3;
	stride += sc_multimesh_has_color() ? 1 : 0;
	stride += sc_multimesh_has_custom_data() ? 1 : 0;
	return stride;
}


/////////////////////////////////////////
////  BASE VERTEX PROCESS FUNCTION  ////
void vertex_shader (
		in vec3 vertex_input,
#ifdef NORMAL_USED
		in vec3 normal_input,
#endif // NORMAL_USED
#ifdef TANGENT_USED
		in vec3 tangent_input,
		in vec3 bitangent_input,
#endif // TANGENT_USED
		in uint instance_index,
		in uint multimesh_offset,
		in SceneData scene_data,
		in mat3x4 in_model_matrix,
#ifdef USE_DOUBLE_PRECISION
		in vec3 model_precision,
#endif // USE_DOUBLE_PRECISION
		out vec4 screen_pos
	)
{
	vec4 instance_custom = vec4(0.0);
#ifdef COLOR_USED
	color_interp = color_attrib;
#endif // COLOR_USED

	mat4 inv_view_matrix = transpose(
		mat4(scene_data.inv_view_matrix[0],
			 scene_data.inv_view_matrix[1],
			 scene_data.inv_view_matrix[2],
			 vec4(0.0, 0.0, 0.0, 1.0))
	);

	mat4 model_matrix = transpose(
		mat4(in_model_matrix[0],
			 in_model_matrix[1],
			 in_model_matrix[2],
			 vec4(0.0, 0.0, 0.0, 1.0))
	);

	mat4 matrix;
	mat4 read_model_matrix = model_matrix;

	mat3 model_normal_matrix = mat3(model_matrix);
	if (bool(instances.data[instance_index].flags & INSTANCE_FLAGS_NON_UNIFORM_SCALE))
		model_normal_matrix = transpose(inverse(model_normal_matrix));

	if (sc_multimesh())
	{
#ifdef USE_PARTICLE_TRAILS

		// Particle Trail Multimesh //
		uint trail_size = (instances.data[instance_index].flags >> INSTANCE_FLAGS_PARTICLE_TRAIL_SHIFT) & INSTANCE_FLAGS_PARTICLE_TRAIL_MASK;
		uint stride = 3 + 1 + 1;  // Particles always use this format.
		uint offset = trail_size * stride * INSTANCE_INDEX;
#ifdef COLOR_USED
		vec4 pcolor;
#endif // COLOR_USED
		{
			uint boffset = offset + bone_attrib.x * stride;
			matrix = mat4(transforms.data[boffset + 0], transforms.data[boffset + 1], transforms.data[boffset + 2], vec4(0.0, 0.0, 0.0, 1.0)) * weight_attrib.x;
#ifdef COLOR_USED
			pcolor = transforms.data[boffset + 3] * weight_attrib.x;
#endif // COLOR_USED
		}
		if (weight_attrib.y > 0.001)
		{
			uint boffset = offset + bone_attrib.y * stride;
			matrix += mat4(transforms.data[boffset + 0], transforms.data[boffset + 1], transforms.data[boffset + 2], vec4(0.0, 0.0, 0.0, 1.0)) * weight_attrib.y;
#ifdef COLOR_USED
			pcolor += transforms.data[boffset + 3] * weight_attrib.y;
#endif // COLOR_USED
		}
		if (weight_attrib.z > 0.001)
		{
			uint boffset = offset + bone_attrib.z * stride;
			matrix += mat4(transforms.data[boffset + 0], transforms.data[boffset + 1], transforms.data[boffset + 2], vec4(0.0, 0.0, 0.0, 1.0)) * weight_attrib.z;
#ifdef COLOR_USED
			pcolor += transforms.data[boffset + 3] * weight_attrib.z;
#endif // COLOR_USED
		}
		if (weight_attrib.w > 0.001)
		{
			uint boffset = offset + bone_attrib.w * stride;
			matrix += mat4(transforms.data[boffset + 0], transforms.data[boffset + 1], transforms.data[boffset + 2], vec4(0.0, 0.0, 0.0, 1.0)) * weight_attrib.w;
#ifdef COLOR_USED
			pcolor += transforms.data[boffset + 3] * weight_attrib.w;
#endif // COLOR_USED
		}

		instance_custom = transforms.data[offset + 4];
#ifdef COLOR_USED
		color_interp *= pcolor;
#endif // COLOR_USED

#else // USE_PARTICLE_TRAILS

		// Standard Multimesh //
		uint stride = multimesh_stride();
		uint offset = stride * (INSTANCE_INDEX + multimesh_offset);

		if (sc_multimesh_format_2d())
		{
			matrix = mat4(transforms.data[offset + 0], transforms.data[offset + 1], vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
			offset += 2;
		}
		else
		{
			matrix = mat4(transforms.data[offset + 0], transforms.data[offset + 1], transforms.data[offset + 2], vec4(0.0, 0.0, 0.0, 1.0));
			offset += 3;
		}

		if (sc_multimesh_has_color())
		{
#ifdef COLOR_USED
			color_interp *= transforms.data[offset];
#endif // COLOR_USED
			offset += 1;
		}

		if (sc_multimesh_has_custom_data())
		{
			instance_custom = transforms.data[offset];
		}

#endif // USE_PARTICLE_TRAILS

		matrix = transpose(matrix);
#if !defined(USE_DOUBLE_PRECISION) || defined(SKIP_TRANSFORM_USED) || defined(VERTEX_WORLD_COORDS_USED) || defined(MODEL_MATRIX_USED)
		// Normally we can bake the multimesh transform into the model matrix, but when using double precision
		// we avoid baking it in so we can emulate high precision.
		read_model_matrix = model_matrix * matrix;
#if !defined(USE_DOUBLE_PRECISION) || defined(SKIP_TRANSFORM_USED) || defined(VERTEX_WORLD_COORDS_USED)
		model_matrix = read_model_matrix;
#endif // !USE_DOUBLE_PRECISION || SKIP_TRANSFORM_USED || VERTEX_WORLD_COORDS_USED
#endif // !USE_DOUBLE_PRECISION || SKIP_TRANSFORM_USED || VERTEX_WORLD_COORDS_USED || MODEL_MATRIX_USED
		model_normal_matrix = model_normal_matrix * mat3(matrix);
	}

	vec3 GD_vertex = vertex_input;
#ifdef NORMAL_USED
	vec3 GD_normal = normal_input;
#endif // NORMAL_USED
#ifdef TANGENT_USED
	vec3 GD_tangent = tangent_input;
	vec3 GD_bitangent = bitangent_input;
#endif // TANGENT_USED

// Transform to world-space if requested via `world_vertex_coords`.
#if !defined(SKIP_TRANSFORM_USED) && defined(VERTEX_WORLD_COORDS_USED)
	GD_vertex = (model_matrix * vec4(GD_vertex, 1.0)).xyz;
#ifdef NORMAL_USED
	GD_normal = model_normal_matrix * GD_normal;
#endif // NORMAL_USED
#ifdef TANGENT_USED
	GD_tangent = model_normal_matrix * GD_tangent;
	GD_bitangent = model_normal_matrix * GD_bitangent;
#endif // TANGENT_USED
#endif // !SKIP_TRANSFORM_USED && VERTEX_WORLD_COORDS_USED

#ifdef UV_USED
	uv_interp = uv_attrib;
#endif // UV_USED
#ifdef UV2_USED
	uv2_interp = uv2_attrib;
#endif // UV2_USED

	vec4 uv_scale = instances.data[instance_index].uv_scale;
	if (uv_scale != vec4(0.0))  // Compression enabled.
	{ 
#ifdef UV_USED
		uv_interp = (uv_interp - 0.5) * uv_scale.xy;
#endif // UV_USED
#ifdef UV2_USED
		uv2_interp = (uv2_interp - 0.5) * uv_scale.zw;
#endif // UV2_USED
	}

#ifdef OVERRIDE_POSITION
	vec4 GD_position = vec4(1.0);
#endif // OVERRIDE_POSITION

#ifdef USE_MULTIVIEW
	mat4 combined_projection = scene_data.projection_matrix;
	mat4 projection_matrix = scene_data.projection_matrix_view[ViewIndex];
	mat4 inv_projection_matrix = scene_data.inv_projection_matrix_view[ViewIndex];
	vec3 eye_offset = scene_data.eye_offset[ViewIndex].xyz;
#else  // USE_MULTIVIEW
	mat4 projection_matrix = scene_data.projection_matrix;
	mat4 inv_projection_matrix = scene_data.inv_projection_matrix;
	vec3 eye_offset = vec3(0.0, 0.0, 0.0);
#endif // USE_MULTIVIEW

#ifdef Z_CLIP_SCALE_USED
	float GD_z_clip_scale = 1.0;
#endif // Z_CLIP_SCALE_USED

	float GD_roughness = 1.0;

	mat4 read_view_matrix = transpose(
		mat4(scene_data.view_matrix[0],
			 scene_data.view_matrix[1],
			 scene_data.view_matrix[2],
			 vec4(0.0, 0.0, 0.0, 1.0))
	);

#ifdef USE_DOUBLE_PRECISION
	mat4 modelview = read_view_matrix * model_matrix;

	// We separate the basis from the origin because the basis is fine with single point precision.
	// Then we combine the translations from the model matrix and the view matrix using emulated doubles.
	// We add the result to the vertex and ignore the final lost precision.
	vec3 model_origin = model_matrix[3].xyz;
	if (sc_multimesh())
	{
		modelview = modelview * matrix;
		vec3 instance_origin = mat3(model_matrix) * matrix[3].xyz;
		model_origin = double_add_vec3(model_origin, model_precision, instance_origin, vec3(0.0), model_precision);
	}

	// Overwrite the translation part of modelview with improved precision.
	vec3 temp_precision;  // Will be ignored.
	modelview[3].xyz = double_add_vec3(model_origin, model_precision, inv_view_matrix[3].xyz, scene_data.inv_view_precision.xyz, temp_precision);
	modelview[3].xyz = mat3(read_view_matrix) * modelview[3].xyz;
#else  // USE_DOUBLE_PRECISION
	mat4 modelview = read_view_matrix * model_matrix;
#endif // USE_DOUBLE_PRECISION
	mat3 modelview_normal = mat3(read_view_matrix) * model_normal_matrix;
	vec2 read_viewport_size = scene_data.viewport_size;

#ifdef POINT_SIZE_USED
	float GD_point_size = 1.0;
#endif // POINT_SIZE_USED


///////////////////////////////////////////////////////////////////////////////
////  USER-SPACE VERTEX() CODE  //////////////////////////////////////////////
	{
#CODE : VERTEX
	}
////  ------------------------  //////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////


// Transform vertex position and TBN vectors, if not disabled by the user.
#ifndef SKIP_TRANSFORM_USED
#ifdef VERTEX_WORLD_COORDS_USED

	// Using world-space coordinates (world_vertex_coords).
	GD_vertex = (read_view_matrix * vec4(GD_vertex, 1.0)).xyz;
#ifdef NORMAL_USED
	GD_normal = (read_view_matrix * vec4(GD_normal, 0.0)).xyz;
#endif // NORMAL_USED
#ifdef TANGENT_USED
	GD_bitangent = (read_view_matrix * vec4(GD_bitangent, 0.0)).xyz;
	GD_tangent = (read_view_matrix * vec4(GD_tangent, 0.0)).xyz;
#endif // TANGENT_USED

#else  // VERTEX_WORLD_COORDS_USED

	// Using local coordinates (default).
	GD_vertex = (modelview * vec4(GD_vertex, 1.0)).xyz;
#ifdef NORMAL_USED
	GD_normal = modelview_normal * GD_normal;
#endif // NORMAL_USED
#ifdef TANGENT_USED
	GD_bitangent = modelview_normal * GD_bitangent;
	GD_tangent = modelview_normal * GD_tangent;
#endif // TANGENT_USED

#endif // VERTEX_WORLD_COORDS_USED
#endif // !SKIP_TRANSFORM_USED

	vertex_interp = GD_vertex;

	// Normalize TBN vectors before interpolation, per MikkTSpace.
	// See: http://www.mikktspace.com/
#ifdef NORMAL_USED
	normal_interp = normalize(GD_normal);
#endif // NORMAL_USED
#ifdef TANGENT_USED
	tangent_interp = normalize(GD_tangent);
	bitangent_interp = normalize(GD_bitangent);
#endif // TANGENT_USED

	float roughness = GD_roughness;

	// Dual Paraboloid Shadow Mapping //
#if defined(MODE_RENDER_PREPASS) && defined(MODE_DUAL_PARABOLOID)
	vertex_interp.z *= scene_data.dual_paraboloid_side;
	dp_clip = vertex_interp.z;  // This attempts to avoid noise caused by objects sent to the other parabolloid side due to bias.

	// For dual paraboloid shadow mapping, this is the fastest but least correct way, as it curves straight edges.
	vec3 vtx = vertex_interp;
	float distance = dot(vtx, vtx);
	float distance_rcp = inversesqrt(distance);
	vtx *= distance_rcp; distance *= distance_rcp;
	vtx.xy /= 1.0 - vtx.z;
	vtx.z = (distance / scene_data.z_far) * 2.0 - 1.0;
	vertex_interp = vtx;
#endif // MODE_RENDER_PREPASS && MODE_DUAL_PARABOLOID

#ifdef OVERRIDE_POSITION
	gl_Position = GD_position;
#else
	gl_Position = projection_matrix * vec4(vertex_interp, 1.0);
#endif // OVERRIDE_POSITION

#ifdef USE_MULTIVIEW
	combined_projected = combined_projection * vec4(vertex_interp, 1.0);
#endif // USE_MULTIVIEW

#ifdef MOTION_VECTORS
	screen_pos = gl_Position;
#endif // MOTION_VECTORS

#if !defined(MODE_RENDER_PREPASS) && !defined(MODE_UNSHADED) && defined(USE_VERTEX_LIGHTING)
#if (USE_VERTEX_LIGHTING == 0)
	diffuse_light_interp = vec4(0.0);
	specular_light_interp = vec4(0.0);
#else  // USE_VERTEX_LIGHTING == 1
	sh_spec_scale_interp = 0.0;
	sh_r_interp = vec4(0.0);
	sh_g_interp = vec4(0.0);
	sh_b_interp = vec4(0.0);
#endif // USE_VERTEX_LIGHTING == 0/1

#ifdef USE_MULTIVIEW
	vec3 view = normalize(eye_offset - vertex_interp);
	vec2 clip_pos = clamp((combined_projected.xy / combined_projected.w) * 0.5 + 0.5, 0.0, 1.0);
#else
	vec3 view = normalize(-vertex_interp);
	vec2 clip_pos = clamp((gl_Position.xy / gl_Position.w) * 0.5 + 0.5, 0.0, 1.0);
#endif // USE_MULTIVIEW

	uvec2 screen_size = uvec2(1.0 / scene_data.screen_pixel_size);
	uvec2 screen_pixel = clamp(uvec2(clip_pos * vec2(screen_size)), uvec2(0), screen_size - uvec2(1));
	uvec2 cluster_pos = screen_pixel >> implementation_data.cluster_shift;
	uint cluster_offset = (implementation_data.cluster_width * cluster_pos.y + cluster_pos.x) * (implementation_data.max_cluster_element_count_div_32 + 32);
	uint cluster_z = uint(clamp((-vertex_interp.z / scene_data.z_far) * 32.0, 0.0, 31.0));

	// Omni Lights //
	{
		uint cluster_omni_offset = cluster_offset;

		uint item_min, item_max, item_from, item_to;
		cluster_get_item_range(cluster_omni_offset + implementation_data.max_cluster_element_count_div_32 + cluster_z, item_min, item_max, item_from, item_to);

		for (uint i = item_from; i < item_to; i++)
		{
			uint mask = cluster_buffer.data[cluster_omni_offset + i];
			mask &= cluster_get_range_clip_mask(i, item_min, item_max);
			uint merged_mask = mask;

			while (merged_mask != 0)
			{
				uint bit = findMSB(merged_mask);
				merged_mask &= ~(1u << bit);
				uint light_index = 32 * i + bit;

				if (!bool(omni_lights.data[light_index].mask & instances.data[instance_index].layer_mask))
					continue;  // Not masked, skip.

				if (omni_lights.data[light_index].bake_mode == LIGHT_BAKE_STATIC && bool(instances.data[instance_index].flags & INSTANCE_FLAGS_USE_LIGHTMAP))
					continue;  // Statically baked light and object uses lightmap, skip.

				light_process_omni_vertex(
						light_index, vertex_interp, view, normal_interp, roughness,
#if (USE_VERTEX_LIGHTING == 0)
						diffuse_light_interp.rgb, specular_light_interp.rgb
#else  // USE_VERTEX_LIGHTING == 1
						sh_r_interp, sh_g_interp, sh_b_interp, sh_spec_scale_interp
#endif // USE_VERTEX_LIGHTING == 0/1
				);
			}
		}
	}

	// Spot Lights //
	{
		uint cluster_spot_offset = cluster_offset + implementation_data.cluster_type_size;

		uint item_min, item_max, item_from, item_to;
		cluster_get_item_range(cluster_spot_offset + implementation_data.max_cluster_element_count_div_32 + cluster_z, item_min, item_max, item_from, item_to);

		for (uint i = item_from; i < item_to; i++)
		{
			uint mask = cluster_buffer.data[cluster_spot_offset + i];
			mask &= cluster_get_range_clip_mask(i, item_min, item_max);
			uint merged_mask = mask;

			while (merged_mask != 0)
			{
				uint bit = findMSB(merged_mask);
				merged_mask &= ~(1u << bit);

				uint light_index = 32 * i + bit;

				if (!bool(spot_lights.data[light_index].mask & instances.data[instance_index].layer_mask))
					continue;  // Not masked, skip.

				if (spot_lights.data[light_index].bake_mode == LIGHT_BAKE_STATIC && bool(instances.data[instance_index].flags & INSTANCE_FLAGS_USE_LIGHTMAP))
					continue;  // Statically baked light and object uses lightmap, skip.

				light_process_spot_vertex(light_index, vertex_interp, view, normal_interp, roughness,
#if (USE_VERTEX_LIGHTING == 0)
						diffuse_light_interp.rgb, specular_light_interp.rgb
#else  // USE_VERTEX_LIGHTING == 1
						sh_r_interp, sh_g_interp, sh_b_interp, sh_spec_scale_interp
#endif // USE_VERTEX_LIGHTING == 0/1
				);
			}
		}
	}

	// Directional Lights //
	for (uint i = 0; i < scene_data.directional_light_count; i++)
	{
		DirectionalLightData light_data = directional_lights.data[i];

		if (!bool(light_data.mask & instances.data[instance_index].layer_mask))
			continue;  // Not masked, skip.
		
		if (light_data.bake_mode == LIGHT_BAKE_STATIC && bool(instances.data[instance_index].flags & INSTANCE_FLAGS_USE_LIGHTMAP))
			continue;  // Statically baked light and object uses lightmap, skip.

		float energy = light_data.energy;
			
#ifndef SHADOWS_DISABLED

#define BIAS_FUNC(m_var, m_idx) \
	m_var.xyz += light_dir * light_data.shadow_bias[m_idx]; \
	vec3 normal_bias = base_normal_bias * light_data.shadow_normal_bias[m_idx]; \
	normal_bias -= light_dir * dot(light_dir, normal_bias); \
	m_var.xyz += normal_bias;

		if (light_data.shadow_opacity > 0.001 && (-vertex_interp.z < light_data.shadow_split_offsets[3]))
		{
			float depth_z = -vertex_interp.z;
			vec3 light_dir = light_data.direction;
			vec3 base_normal_bias = normal_interp * (1.0 - max(0.0, dot(light_dir, -normal_interp)));

			const uint split_idx = uint(dot(vec3(greaterThan(vec3(depth_z), light_data.shadow_split_offsets.xyz)), vec3(1.0)));

			vec4 v = vec4(vertex_interp, 1.0);
			BIAS_FUNC(v, split_idx)
			vec4 pssm_coord = (light_data.shadow_matrix[split_idx] * v);
			pssm_coord.xyz *= 1.0 / pssm_coord.w;

			// Adjust shadow blur with reference to the first split to reduce discrepancy between shadow splits.
			float blur_factor = light_data.soft_shadow_scale * (light_data.shadow_split_offsets[0] / light_data.shadow_split_offsets[split_idx]);
			blur_factor += sqrt(blur_factor);  // Boost shadow filter scale to reduce per-vertex aliasing.
			float shadow = sample_directional_pcf_shadow_vertex(directional_shadow_atlas, scene_data.directional_shadow_pixel_size * blur_factor, pssm_coord);

			uint max_blend_split = light_data.shadow_split_offsets[3] > 0.0 ? 2 : 0;  // Final cascade does not blend.
			if (light_data.blend_splits && depth_z < light_data.shadow_split_offsets[max_blend_split])
			{
				v = vec4(vertex_interp, 1.0);
				BIAS_FUNC(v, (split_idx+1))
				pssm_coord = (light_data.shadow_matrix[split_idx+1] * v);
				pssm_coord.xyz *= 1.0 / pssm_coord.w;

				blur_factor = light_data.soft_shadow_scale * (light_data.shadow_split_offsets[0] / light_data.shadow_split_offsets[split_idx+1]);
				blur_factor += sqrt(blur_factor);  // Boost shadow filter scale to reduce per-vertex aliasing.
				float shadow2 = sample_directional_pcf_shadow_vertex(directional_shadow_atlas, scene_data.directional_shadow_pixel_size * blur_factor, pssm_coord);
				
				float pssm_blend = smoothstep(light_data.shadow_split_offsets[split_idx] * 0.8, light_data.shadow_split_offsets[split_idx], depth_z);  // Blend over last 20% of lower cascade.
				shadow = mix(shadow, shadow2, pssm_blend);
			}
			energy *= mix(shadow, 1.0, smoothstep(light_data.fade_from, light_data.fade_to, vertex_interp.z));
		}
#undef BIAS_FUNC

#endif // !SHADOWS_DISABLED

#if (USE_VERTEX_LIGHTING == 0)
		light_compute_vertex(
				normal_interp, light_data.direction, view, light_data.size, light_data.color * energy, roughness, light_data.specular,
				diffuse_light_interp.rgb, specular_light_interp.rgb
		);
#else // USE_VERTEX_LIGHTING == 1
		light_project_sh(
				normal_interp, light_data.direction, light_data.color * energy, light_data.specular,
				sh_r_interp, sh_g_interp, sh_b_interp, sh_spec_scale_interp
		);
#endif // USE_VERTEX_LIGHTING == 0/1
	}

#if (USE_VERTEX_LIGHTING == 0)
	// Interpolate per-vertex lighting brightness non-linearly for perceptually smoother gradients.
	diffuse_light_interp *= inversesqrt(abs(dot(diffuse_light_interp.rgb, vec3(1.0/3.0))) + 0.000001);
#ifndef SPECULAR_DISABLED
	specular_light_interp *= inversesqrt(abs(dot(specular_light_interp.rgb, vec3(1.0/3.0))) + 0.000001);
#endif // !SPECULAR_DISABLED
#else  // USE_VERTEX_LIGHTING == 1
#ifndef SPECULAR_DISABLED
	// Ratio between L0 brightness with and without specular_amount. This lets individual lights control their contribution to SH specular,
	// without requiring an entire separate set of coefficients to be accumulated and passed to the fragment shader.
	sh_spec_scale_interp = sqrt(abs(sh_spec_scale_interp) / (abs(dot(vec3(sh_r_interp.x, sh_g_interp.x, sh_b_interp.x), vec3(1.0/3.0))) + 0.000001));
#endif // !SPECULAR_DISABLED
	// Interpolate per-vertex SH brightness non-linearly for perceptually smoother gradients.
	float sh_l0_rsqrt = inversesqrt(abs(dot(vec3(sh_r_interp.x, sh_g_interp.x, sh_b_interp.x), vec3(1.0/3.0))) + 0.000001);
	sh_r_interp *= sh_l0_rsqrt;
	sh_g_interp *= sh_l0_rsqrt;
	sh_b_interp *= sh_l0_rsqrt;
#endif // USE_VERTEX_LIGHTING == 0/1

#endif // !MODE_RENDER_PREPASS && !MODE_UNSHADED && USE_VERTEX_LIGHTING


#ifdef MODE_RENDER_PREPASS
	if (bool(scene_data.flags & SCENE_DATA_FLAGS_USE_PANCAKE_SHADOWS))
	{
		if (gl_Position.z >= 0.9999)
			gl_Position.z = 0.9999;
	}
#endif // MODE_RENDER_PREPASS
#ifdef MODE_RENDER_MATERIAL
	if (bool(scene_data.flags & SCENE_DATA_FLAGS_USE_UV2_MATERIAL))
	{
		vec2 uv_dest_attrib;
		if (uv_scale != vec4(0.0))
			uv_dest_attrib = (uv2_attrib.xy - 0.5) * uv_scale.zw;
		else
			uv_dest_attrib = uv2_attrib.xy;

		vec2 uv_offset = unpackHalf2x16(draw_call.uv_offset);
		gl_Position.xy = (uv_dest_attrib + uv_offset) * 2.0 - 1.0;
		gl_Position.z = 0.00001;
		gl_Position.w = 1.0;
	}
#endif // MODE_RENDER_MATERIAL

#ifdef Z_CLIP_SCALE_USED
	if (!bool(scene_data.flags & SCENE_DATA_FLAGS_IN_SHADOW_PASS))
		gl_Position.z = mix(gl_Position.w, gl_Position.z, GD_z_clip_scale);
#endif // Z_CLIP_SCALE_USED

#ifdef POINT_SIZE_USED
	if (sc_emulate_point_size)
	{
		const vec2 point_coords[6] = vec2[](
				vec2(0, 1),
				vec2(0, 0),
				vec2(1, 1),
				vec2(0, 0),
				vec2(1, 0),
				vec2(1, 1)
		);
		vec2 point_coord = point_coords[gl_VertexIndex % 6];

		gl_Position.xy += (point_coord * 2.0 - 1.0) * (GD_point_size / scene_data.viewport_size) * gl_Position.w;
#ifdef POINT_COORD_USED
		point_coord_interp = point_coord;
#endif // POINT_COORD_USED
	}
	else gl_PointSize = GD_point_size;
#endif // POINT_SIZE_USED
}


/////////////////////////////////////
////  VERTEX STAGE ENTRY POINT  ////
void main()
{
	uint instance_index = draw_call.instance_index;
	if (!sc_multimesh())
		instance_index += INSTANCE_INDEX;
	instance_index_interp = instance_index;

#ifdef MOTION_VECTORS

	vec3 prev_vertex;
#ifdef NORMAL_USED
	vec3 prev_normal;
#endif // NORMAL_USED
#if defined(NORMAL_USED) || defined(TANGENT_USED)
	vec3 prev_tangent;
	vec3 prev_bitangent;
#endif // NORMAL_USED || TANGENT_USED

	_unpack_vertex_attributes(
			previous_vertex_attrib,
			instances.data[instance_index].compressed_aabb_position_pad.xyz,
			instances.data[instance_index].compressed_aabb_size_pad.xyz,
#if defined(NORMAL_USED) || defined(TANGENT_USED)
			previous_normal_attrib,
#ifdef NORMAL_USED
			prev_normal,
#endif // NORMAL_USED
			prev_tangent,
			prev_bitangent,
#endif // NORMAL_USED || TANGENT_USED
			prev_vertex
	);

	global_time = scene_data_block.prev_data.time;
	vertex_shader(
			prev_vertex,
#ifdef NORMAL_USED
			prev_normal,
#endif // NORMAL_USED
#ifdef TANGENT_USED
			prev_tangent,
			prev_bitangent,
#endif // TANGENT_USED
			instance_index, draw_call.multimesh_motion_vectors_previous_offset, scene_data_block.prev_data, instances.data[instance_index].prev_transform,
#ifdef USE_DOUBLE_PRECISION
			instances.data[instance_index].prev_model_precision.xyz,
#endif // USE_DOUBLE_PRECISION
			prev_screen_position
	);

#else // MOTION_VECTORS

	vec4 screen_position;  // Unused output attribute.

#endif // MOTION_VECTORS

	vec3 vertex;
#ifdef NORMAL_USED
	vec3 normal;
#endif // NORMAL_USED
#if defined(NORMAL_USED) || defined(TANGENT_USED)
	vec3 tangent;
	vec3 bitangent;
#endif // NORMAL_USED || TANGENT_USED

	_unpack_vertex_attributes(
			vertex_angle_attrib,
			instances.data[instance_index].compressed_aabb_position_pad.xyz,
			instances.data[instance_index].compressed_aabb_size_pad.xyz,
#if defined(NORMAL_USED) || defined(TANGENT_USED)
			axis_tangent_attrib,
#ifdef NORMAL_USED
			normal,
#endif // NORMAL_USED
			tangent,
			bitangent,
#endif
			vertex
	);

	// Current vertex.
	global_time = scene_data_block.data.time;
	vertex_shader(
			vertex,
#ifdef NORMAL_USED
			normal,
#endif // NORMAL_USED
#ifdef TANGENT_USED
			tangent,
			bitangent,
#endif // TANGENT_USED
			instance_index, draw_call.multimesh_motion_vectors_current_offset, scene_data_block.data, instances.data[instance_index].transform,
#ifdef USE_DOUBLE_PRECISION
			instances.data[instance_index].model_precision.xyz,
#endif // USE_DOUBLE_PRECISION
			screen_position
	);
}


///////////////////////////////////////////////////////////////////////////////
////  FRAGMENT STAGE  ////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////

#[fragment]
#version 450
#VERSION_DEFINES


#define SHADER_IS_SRGB		false
#define SHADER_SPACE_FAR	0.0

#ifdef USE_MULTIVIEW
#extension GL_EXT_multiview : enable
#define OUTPUT_IS_MULTIVIEW	true
#define ViewIndex			gl_ViewIndex
#else  // USE_MULTIVIEW
#define OUTPUT_IS_MULTIVIEW	false
#define ViewIndex			0
#endif // USE_MULTIVIEW


#if defined(USE_LIGHTMAP) && !defined(UV2_USED)
#define UV2_USED  // UV2 always used with lightmapping.
#endif // USE_LIGHTMAP && !UV2_USED

#if defined(SPECULAR_DISABLED) && defined(LIGHT_CLEARCOAT_USED)
#undef LIGHT_CLEARCOAT_USED  // Clearcoat requires specularity to be enabled.
#endif // SPECULAR_DISABLED && LIGHT_CLEARCOAT_USED

#if defined(ENABLE_SSS) && defined(ENABLE_TRANSMITTANCE)
#define LIGHT_TRANSMITTANCE_USED  // Both required for transmittance to be enabled.
#endif // ENABLE_SSS && ENABLE_TRANSMITTANCE

#if !defined(AMBIENT_LIGHT_DISABLED) && defined(USE_LIGHTMAP) && !defined(SPECULAR_DISABLED) && !defined(SPECULAR_OCCLUSION_DISABLED)
#define USE_IRRADIANCE_MATCHING  // Convenience, indicates Iradiance Matching can be used.
#endif // !AMBIENT_LIGHT_DISABLED && USE_LIGHTMAP && !SPECULAR_DISABLED && !SPECULAR_OCCLUSION_DISABLED


#include "../half_inc.glsl"
#include "scene_forward_clustered_inc.glsl"


/////////////////////////////
////  INPUT ATTRIBUTES  ////

layout(location = 0) in vec3 vertex_interp;

#ifdef NORMAL_USED
layout(location = 1) in vec3 normal_interp;
#endif // NORMAL_USED

#ifdef COLOR_USED
layout(location = 2) in vec4 color_interp;
#endif // COLOR_USED

#ifdef UV_USED
layout(location = 3, component = 0) in vec2 uv_interp;
#endif // UV_USED

#ifdef UV2_USED
layout(location = 3, component = 2) in vec2 uv2_interp;
#endif // UV2_USED

#ifdef TANGENT_USED
layout(location = 4) in vec3 tangent_interp;
layout(location = 5) in vec3 bitangent_interp;
#endif // TANGENT_USED

#ifdef MOTION_VECTORS
layout(location = 6) in vec4 screen_position;
layout(location = 7) in vec4 prev_screen_position;
#endif // MOTION_VECTORS

#ifdef MODE_DUAL_PARABOLOID
layout(location = 8, component = 0) in float dp_clip;
#endif // MODE_DUAL_PARABOLOID

layout(location = 9) in flat uint instance_index_interp;

#ifdef USE_MULTIVIEW
layout(location = 10) in vec4 combined_projected;
#endif // USE_MULTIVIEW

#if !defined(MODE_RENDER_PREPASS) && !defined(MODE_UNSHADED) && defined(USE_VERTEX_LIGHTING)
#if (USE_VERTEX_LIGHTING == 0)
layout(location = 11) in vec4 diffuse_light_interp;
layout(location = 12) in vec4 specular_light_interp;
#else  // USE_VERTEX_LIGHTING == 1
layout(location = 8, component = 1) in float sh_spec_scale_interp;
layout(location = 11) in vec4 sh_r_interp;
layout(location = 12) in vec4 sh_g_interp;
layout(location = 13) in vec4 sh_b_interp;
#endif // USE_VERTEX_LIGHTING
#endif // !MODE_RENDER_PREPASS && !MODE_UNSHADED && USE_VERTEX_LIGHTING

#if defined(POINT_SIZE_USED) && defined(POINT_COORD_USED)
layout(location = 14) in vec2 point_coord_interp;
#endif // POINT_SIZE_USED && POINT_COORD_USED


// Defines to keep compatibility with vertex.
#ifdef USE_MULTIVIEW
#define projection_matrix		scene_data.projection_matrix_view[ViewIndex]
#define inv_projection_matrix	scene_data.inv_projection_matrix_view[ViewIndex]
#else  // USE_MULTIVIEW
#define projection_matrix		scene_data.projection_matrix
#define inv_projection_matrix	scene_data.inv_projection_matrix
#endif // USE_MULTIVIEW

#define global_time				scene_data_block.data.time

#ifdef MATERIAL_UNIFORMS_USED
/* clang-format off */
layout(set = MATERIAL_UNIFORM_SET, binding = 0, std140) uniform MaterialUniforms
{
#MATERIAL_UNIFORMS
} material;
/* clang-format on */
#endif // MATERIAL_UNIFORMS_USED


//////////////////////////////
////  OUTPUT ATTRIBUTES  ////

#ifdef MODE_RENDER_PREPASS

#ifdef MODE_RENDER_MATERIAL
layout(location = 0) out vec4 albedo_output_buffer;
layout(location = 1) out vec4 normal_output_buffer;
layout(location = 2) out vec4 orm_output_buffer;
layout(location = 3) out vec4 emission_output_buffer;
layout(location = 4) out float depth_output_buffer;
#endif // MODE_RENDER_MATERIAL

#ifdef MODE_RENDER_NORMAL_ROUGHNESS
layout(location = 0) out vec4 normal_roughness_output_buffer;
#ifdef MODE_RENDER_VOXEL_GI
layout(location = 1) out uvec2 voxel_gi_buffer;
#endif // MODE_RENDER_VOXEL_GI
#endif // MODE_RENDER_NORMAL_ROUGHNESS

#else  // RENDER DEPTH

#ifdef MODE_SEPARATE_SPECULAR
layout(location = 0) out vec4 diffuse_buffer;  // RGB = Diffuse, A = Subsurface Strength
layout(location = 1) out vec4 specular_buffer;  // RGB = Specular, A = Metalness
#else  // MODE_SEPARATE_SPECULAR
layout(location = 0) out vec4 out_color;
#endif // MODE_SEPARATE_SPECULAR

#endif // RENDER DEPTH

#ifdef MOTION_VECTORS
layout(location = 2) out vec2 motion_buffer;
#endif // MOTION_VECTORS


/////////////////////////////
////  HELPER FUNCTIONS  ////

#ifdef USE_MULTIVIEW
vec3  multiview_uv (vec2 uv)	{ return  vec3(uv, ViewIndex); }
ivec3 multiview_uv (ivec2 uv)	{ return ivec3(uv, int(ViewIndex)); }
#else  // USE_MULTIVIEW
vec2  multiview_uv (vec2 uv)	{ return uv; }
ivec2 multiview_uv (ivec2 uv)	{ return uv; }
#endif // USE_MULTIVIEW


///////////////////////////////////
////  Fragment Stage Globals  ////
#GLOBALS
////////////////////////////////


#if defined(ALPHA_HASH_USED) || defined(ALPHA_ANTIALIASING_EDGE_USED)
#include "../scene_forward_aa_inc.glsl"
#endif // ALPHA_HASH_USED || ALPHA_ANTIALIASING_EDGE_USED

#if !defined(MODE_RENDER_PREPASS) && !defined(MODE_UNSHADED)

#ifdef USE_LIGHTMAP
// w0, w1, w2, and w3 are the four cubic B-spline basis functions
float w0 (float a)	{ return (1.0 / 6.0) * (a * (a * (-a + 3.0) - 3.0) + 1.0); }
float w1 (float a)	{ return (1.0 / 6.0) * (a * a * (3.0 * a - 6.0) + 4.0); }
float w2 (float a)	{ return (1.0 / 6.0) * (a * (a * (-3.0 * a + 3.0) + 3.0) + 1.0); }
float w3 (float a)	{ return (1.0 / 6.0) * (a * a * a); }
// g0 and g1 are the two amplitude functions
float g0 (float a)	{ return w0(a) + w1(a); }
float g1 (float a)	{ return w2(a) + w3(a); }
// h0 and h1 are the two offset functions
float h0 (float a)	{ return -1.0 + w1(a) / (w0(a) + w1(a)); }
float h1 (float a)	{ return 1.0 + w3(a) / (w2(a) + w3(a)); }

vec4 textureArray_bicubic (texture2DArray tex, vec3 uv, vec2 texture_size)
{
	vec2 texel_size = vec2(1.0) / texture_size;
	uv.xy = uv.xy * texture_size + vec2(0.5);

	vec2 iuv = floor(uv.xy);
	vec2 fuv = fract(uv.xy);

	float g0x = g0(fuv.x);
	float g1x = g1(fuv.x);
	float h0x = h0(fuv.x);
	float h1x = h1(fuv.x);
	float h0y = h0(fuv.y);
	float h1y = h1(fuv.y);

	vec2 p0 = (vec2(iuv.x + h0x, iuv.y + h0y) - vec2(0.5)) * texel_size;
	vec2 p1 = (vec2(iuv.x + h1x, iuv.y + h0y) - vec2(0.5)) * texel_size;
	vec2 p2 = (vec2(iuv.x + h0x, iuv.y + h1y) - vec2(0.5)) * texel_size;
	vec2 p3 = (vec2(iuv.x + h1x, iuv.y + h1y) - vec2(0.5)) * texel_size;

	return (g0(fuv.y) * (g0x * texture(sampler2DArray(tex, SAMPLER_LINEAR_CLAMP), vec3(p0, uv.z)) + g1x * texture(sampler2DArray(tex, SAMPLER_LINEAR_CLAMP), vec3(p1, uv.z)))) +
		   (g1(fuv.y) * (g0x * texture(sampler2DArray(tex, SAMPLER_LINEAR_CLAMP), vec3(p2, uv.z)) + g1x * texture(sampler2DArray(tex, SAMPLER_LINEAR_CLAMP), vec3(p3, uv.z))));
}
#endif // USE_LIGHTMAP

#if (defined(USE_VERTEX_LIGHTING) && (USE_VERTEX_LIGHTING == 1)) || defined(USE_LIGHTMAP)
#include "../sh_inc.glsl"
#endif // (USE_VERTEX_LIGHTING && (USE_VERTEX_LIGHTING == 1)) || USE_LIGHTMAP

#if !(defined(SPECULAR_DISABLED) || defined(SPECULAR_SCHLICK_GGX) || defined(SPECULAR_TOON))
#define SPECULAR_SCHLICK_GGX  // Default to SPECULAR_SCHLICK_GGX.
#endif // !(SPECULAR_DISABLED || SPECULAR_SCHLICK_GGX || SPECULAR_TOON) 

#include "../scene_forward_gi_inc.glsl"
#include "../scene_forward_lights_inc.glsl"

#endif // !MODE_RENDER_PREPASS && !MODE_UNSHADED


#ifndef MODE_RENDER_PREPASS
vec4 volumetric_fog_process (vec2 screen_uv, float z)
{
	vec3 fog_pos = vec3(screen_uv, z * implementation_data.volumetric_fog_inv_length);
	if (fog_pos.z < 0.0)
		return vec4(0.0, 0.0, 0.0, 1.0);
	else if (fog_pos.z < 1.0)
		fog_pos.z = pow(fog_pos.z, implementation_data.volumetric_fog_detail_spread);

	return texture(sampler3D(volumetric_fog_texture, SAMPLER_LINEAR_CLAMP), fog_pos);
}

vec4 fog_process (vec3 vertex)
{
	vec3 fog_color = scene_data_block.data.fog_light_color;

	if (scene_data_block.data.fog_aerial_perspective > 0.0)
	{
		vec3 sky_fog_color = vec3(0.0);
		vec3 cube_view = scene_data_block.data.radiance_inverse_xform * vertex;
		// mip_level always reads from the second mipmap and higher so the fog is always slightly blurred
		float mip_level = mix(1.0 / MAX_ROUGHNESS_LOD, 1.0, 1.0 - (abs(vertex.z) - scene_data_block.data.z_near) / (scene_data_block.data.z_far - scene_data_block.data.z_near));
#ifdef USE_RADIANCE_OCTMAP_ARRAY
		float roughness_lod, blend;
		blend = modf(mip_level * MAX_ROUGHNESS_LOD, roughness_lod);
		float cube_lod = vec3_to_oct_lod(dFdxCoarse(cube_view), dFdyCoarse(cube_view), scene_data_block.data.radiance_pixel_size);
		vec2 cube_uv = vec3_to_oct_with_border(cube_view, vec2(scene_data_block.data.radiance_border_size, 1.0 - scene_data_block.data.radiance_border_size * 2.0));
		vec3 sky_sample_a = textureLod(sampler2DArray(radiance_octmap, DEFAULT_SAMPLER_LINEAR_WITH_MIPMAPS_CLAMP), vec3(cube_uv, roughness_lod), cube_lod).rgb;
		vec3 sky_sample_b = textureLod(sampler2DArray(radiance_octmap, DEFAULT_SAMPLER_LINEAR_WITH_MIPMAPS_CLAMP), vec3(cube_uv, roughness_lod + 1), cube_lod).rgb;
		sky_fog_color = mix(sky_sample_a, sky_sample_b, blend);
#else  // USE_RADIANCE_OCTMAP_ARRAY
		float roughness_lod = mip_level * MAX_ROUGHNESS_LOD;
		vec2 cube_uv = vec3_to_oct_with_border(cube_view, vec2(scene_data_block.data.radiance_border_size, 1.0 - scene_data_block.data.radiance_border_size * 2.0));
		sky_fog_color = textureLod(sampler2D(radiance_octmap, DEFAULT_SAMPLER_LINEAR_WITH_MIPMAPS_CLAMP), cube_uv, roughness_lod).rgb;
#endif // USE_RADIANCE_OCTMAP_ARRAY
		fog_color = mix(fog_color, sky_fog_color, scene_data_block.data.fog_aerial_perspective);
	}

	if (scene_data_block.data.fog_sun_scatter > 0.001)
	{
		vec4 sun_scatter = vec4(0.0);
		float sun_total = 0.0;
		vec3 view = normalize(vertex);

		for (uint i = 0; i < scene_data_block.data.directional_light_count; i++)
		{
			vec3 light_color = directional_lights.data[i].color * directional_lights.data[i].energy;
			float light_amount = pow(max(dot(view, directional_lights.data[i].direction), 0.0), 8.0);
			fog_color += light_color * light_amount * scene_data_block.data.fog_sun_scatter;
		}
	}

	float fog_amount = 0.0;
	if (sc_use_depth_fog())
	{
		float fog_z = smoothstep(scene_data_block.data.fog_depth_begin, scene_data_block.data.fog_depth_end, length(vertex));
		fog_amount = pow(fog_z, scene_data_block.data.fog_depth_curve) * scene_data_block.data.fog_density;
	}
	else fog_amount = 1.0 - exp(min(0.0, -length(vertex) * scene_data_block.data.fog_density));

	if (abs(scene_data_block.data.fog_height_density) >= 0.0001)
	{
		mat4 inv_view_matrix = transpose(
			mat4(scene_data_block.data.inv_view_matrix[0],
				 scene_data_block.data.inv_view_matrix[1],
				 scene_data_block.data.inv_view_matrix[2],
				 vec4(0.0, 0.0, 0.0, 1.0))
		);
		float y_dist = (inv_view_matrix * vec4(vertex, 1.0)).y - scene_data_block.data.fog_height;
		float vfog_amount = 1.0 - exp(min(0.0, y_dist * scene_data_block.data.fog_height_density));
		fog_amount = max(vfog_amount, fog_amount);
	}

	return vec4(fog_color, fog_amount);
}

void cluster_get_item_range (
		in uint p_offset,
		out uint item_min, out uint item_max,
		out uint item_from, out uint item_to
	)
{
	uint item_min_max = cluster_buffer.data[p_offset];
	item_min = item_min_max & 0xFFFFu;
	item_max = item_min_max >> 16;

	item_from = item_min >> 5;
	item_to = (item_max == 0) ? 0 : ((item_max - 1) >> 5) + 1;  // As a side effect of how it's stored, item_max=0 means no elements.
}
uint cluster_get_range_clip_mask (uint i, uint z_min, uint z_max)
{
	int local_min = clamp(int(z_min) - int(i) * 32, 0, 31);
	int mask_width = min(int(z_max) - int(z_min), 32 - local_min);
	return bitfieldInsert(0u, 0xFFFFFFFFu, local_min, mask_width);
}
#endif // !MODE_RENDER DEPTH


#if defined(MODE_RENDER_NORMAL_ROUGHNESS) || defined(MODE_RENDER_MATERIAL)
// https://advances.realtimerendering.com/s2010/Kaplanyan-CryEngine3(SIGGRAPH%202010%20Advanced%20RealTime%20Rendering%20Course).pdf
vec3 encode24 (vec3 v)
{
	// Unsigned normal (handles most symmetry)
	vec3 vNormalUns = abs(v);
	// Get the major axis for our collapsed cubemap lookup
	float maxNAbs = max(vNormalUns.z, max(vNormalUns.x, vNormalUns.y));
	// Get the collapsed cubemap texture coordinates
	vec2 vTexCoord = vNormalUns.z < maxNAbs ? (vNormalUns.y < maxNAbs ? vNormalUns.yz : vNormalUns.xz) : vNormalUns.xy;
	vTexCoord /= maxNAbs;
	vTexCoord = vTexCoord.x < vTexCoord.y ? vTexCoord.yx : vTexCoord.xy;
	vTexCoord.y /= vTexCoord.x;
	float fFittingScale = texture(sampler2D(best_fit_normal_texture, SAMPLER_NEAREST_CLAMP), vTexCoord).r;
	// Scale the normal to its best-fit, relative to a unit cube.
	return v * (fFittingScale / maxNAbs);
}
#endif // MODE_RENDER_NORMAL_ROUGHNESS || MODE_RENDER_MATERIAL


///////////////////////////////////////////
////  BASE FRAGMENT PROCESS FUNCTION  ////
void fragment_shader(
		in SceneData scene_data
	)
{
	const uint instance_index = instance_index_interp;

	// Declare everything that can be used in a user shader.
	vec3 GD_vertex = vertex_interp;
#ifdef LIGHT_VERTEX_USED
	vec3 light_vertex = GD_vertex;
#endif // LIGHT_VERTEX_USED

#ifdef NORMAL_USED
	vec3 GD_normal = normal_interp;
#ifdef DO_SIDE_CHECK
	if (!gl_FrontFacing)
		GD_normal = -GD_normal;
#endif // DO_SIDE_CHECK
#endif // NORMAL_USED

#ifdef TANGENT_USED
	vec3 GD_tangent = tangent_interp;
	vec3 GD_bitangent = bitangent_interp;
#else
	vec3 GD_tangent = vec3(0.0);
	vec3 GD_bitangent = vec3(0.0);
#endif // TANGENT_USED

#ifdef USE_MULTIVIEW
	vec3 eye_offset = scene_data.eye_offset[ViewIndex].xyz;
	vec3 GD_view = normalize(eye_offset - vertex_interp);
	// UV in our combined frustum space is used for certain screen uv processes where it's
	// overkill to render separate left and right eye views
	vec2 combined_uv = (combined_projected.xy / combined_projected.w) * 0.5 + 0.5;
#else  // USE_MULTIVIEW
	vec3 eye_offset = vec3(0.0, 0.0, 0.0);
	vec3 GD_view = normalize(-vertex_interp);
#endif // USE_MULTIVIEW

	vec3 GD_albedo = vec3(1.0);
	vec3 backlight = vec3(0.0);
	vec4 transmittance_color = vec4(0.0, 0.0, 0.0, 1.0);
	float transmittance_depth = 0.0;
	float transmittance_boost = 0.0;
	float GD_metallic = 0.0;
	float specular = 0.5;
	vec3 emission = vec3(0.0);
	float GD_roughness = 1.0;
	float rim = 0.0;
	float rim_tint = 0.0;
	float clearcoat = 0.0;
	float GD_clearcoat_roughness = 0.0;
	float anisotropy = 0.0;
	vec2 anisotropy_flow = vec2(1.0, 0.0);
	vec3 energy_compensation = vec3(1.0);
	vec4 fog = vec4(0.0, 0.0, 0.0, 1.0);

#ifdef CUSTOM_RADIANCE_USED
	vec4 custom_radiance = vec4(0.0);
#endif // CUSTOM_RADIANCE_USED
#ifdef CUSTOM_IRRADIANCE_USED
	vec4 custom_irradiance = vec4(0.0);
#endif // CUSTOM_IRRADIANCE_USED

	float ao = 1.0;
	float ao_light_affect = 0.0;

	float GD_alpha = float(instances.data[instance_index].flags >> INSTANCE_FLAGS_FADE_SHIFT) / float(255.0);
#ifdef PREMUL_ALPHA_USED
	float premul_alpha = 1.0;
#endif // PREMUL_ALPHA_USED

#ifdef UV_USED
	vec2 uv = uv_interp;
#endif // UV_USED
#ifdef UV2_USED
	vec2 uv2 = uv2_interp;
#endif // UV2_USED
#ifdef COLOR_USED
	vec4 color = color_interp;
#endif // COLOR_USED

#ifdef NORMAL_MAP_USED
	vec3 normal_map = vec3(0.5);
	float normal_map_depth = 1.0;
#endif // NORMAL_MAP_USED
#ifdef BENT_NORMAL_MAP_USED
	vec3 bent_normal_vector = vec3(0.5);
	vec3 bent_normal_map = vec3(0.5);
#endif // BENT_NORMAL_MAP_USED

	vec2 screen_uv = gl_FragCoord.xy * scene_data.screen_pixel_size;

	float sss_strength = 0.0;

#ifdef ALPHA_SCISSOR_USED
	float alpha_scissor_threshold = 1.0;
#endif // ALPHA_SCISSOR_USED
#ifdef ALPHA_HASH_USED
	float alpha_hash_scale = 1.0;
#endif // ALPHA_HASH_USED
#ifdef ALPHA_ANTIALIASING_EDGE_USED
	float alpha_antialiasing_edge = 0.0;
	vec2 alpha_texture_coordinate = vec2(0.0, 0.0);
#endif // ALPHA_ANTIALIASING_EDGE_USED

	mat4 inv_view_matrix = transpose(
		mat4(scene_data.inv_view_matrix[0],
			 scene_data.inv_view_matrix[1],
			 scene_data.inv_view_matrix[2],
			 vec4(0.0, 0.0, 0.0, 1.0))
	);
	mat4 read_model_matrix = transpose(
		mat4(instances.data[instance_index].transform[0],
			 instances.data[instance_index].transform[1],
			 instances.data[instance_index].transform[2],
			 vec4(0.0, 0.0, 0.0, 1.0))
	);

	mat3 model_normal_matrix = mat3(read_model_matrix);
	if (bool(instances.data[instance_index].flags & INSTANCE_FLAGS_NON_UNIFORM_SCALE))
		model_normal_matrix = transpose(inverse(model_normal_matrix));

	mat4 read_view_matrix = transpose(
		mat4(scene_data.view_matrix[0],
			 scene_data.view_matrix[1],
			 scene_data.view_matrix[2],
			 vec4(0.0, 0.0, 0.0, 1.0))
	);
	vec2 read_viewport_size = scene_data.viewport_size;

#ifdef POINT_COORD_USED
#ifdef POINT_SIZE_USED
	vec2 point_coord = gl_PointCoord;
	if (sc_emulate_point_size)
		point_coord = point_coord_interp;
#else  // POINT_SIZE_USED
	vec2 point_coord = vec2(0.5);
#endif // POINT_SIZE_USED
#endif // POINT_COORD_USED


///////////////////////////////////////////////////////////////////////////////
////  USER-SPACE FRAGMENT() CODE  ////////////////////////////////////////////
	{
#CODE : FRAGMENT
	}
////  --------------------------  /////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////


	float roughness = GD_roughness;
#ifdef LIGHT_CLEARCOAT_USED
	float clearcoat_roughness = GD_clearcoat_roughness * CLEARCOAT_ROUGHNESS;
#endif // LIGHT_CLEARCOAT_USED

	float metallic = GD_metallic;
	vec3 albedo = GD_albedo;
	float alpha = GD_alpha;

#ifdef NORMAL_USED
	vec3 normal = GD_normal;
#endif // NORMAL_USED
#ifdef TANGENT_USED
	vec3 tangent = GD_tangent;
	vec3 bitangent = GD_bitangent;
#endif // TANGENT_USED

#ifdef LIGHT_TRANSMITTANCE_USED
	transmittance_color.a *= sss_strength;
#endif // LIGHT_TRANSMITTANCE_USED

	vec3 vertex = GD_vertex;
#ifdef LIGHT_VERTEX_USED
	vertex = light_vertex;
#ifdef USE_MULTIVIEW
	vec3 view = normalize(eye_offset - vertex);
#else
	vec3 view = normalize(-vertex);
#endif // USE_MULTIVIEW
#else  // LIGHT_VERTEX_USED
	vec3 view = normalize(GD_view);  // Ensure view vector is normalized, just in case it wasn't in the user shader.
#endif // LIGHT_VERTEX_USED

#ifdef NORMAL_USED
	vec3 geo_normal = normalize(normal);  // Same for normals.
#endif // NORMAL_USED


#ifndef USE_SHADOW_TO_OPACITY

#ifdef ALPHA_SCISSOR_USED
#ifdef MODE_RENDER_MATERIAL
	if (alpha < alpha_scissor_threshold)
		alpha = 0.0;
	else
		alpha = 1.0;
#else  // MODE_RENDER_MATERIAL
	if (alpha < alpha_scissor_threshold)
		discard;
#endif // MODE_RENDER_MATERIAL
#endif // ALPHA_SCISSOR_USED


	// Alpha hash can be used in unison with alpha antialiasing.
#ifdef ALPHA_HASH_USED
	vec3 object_pos = (inverse(read_model_matrix) * inv_view_matrix * vec4(vertex, 1.0)).xyz;
#ifdef MODE_RENDER_MATERIAL
	if (alpha < compute_alpha_hash_threshold(object_pos, alpha_hash_scale))
		alpha = 0.0;
	else
		alpha = 1.0;
#else  // MODE_RENDER_MATERIAL
	if (alpha < compute_alpha_hash_threshold(object_pos, alpha_hash_scale))
		discard;
#endif // MODE_RENDER_MATERIAL
#endif // ALPHA_HASH_USED


	// If we are not edge antialiasing, we need to remove the output alpha channel from scissor and hash.
#if (defined(ALPHA_SCISSOR_USED) || defined(ALPHA_HASH_USED)) && !defined(ALPHA_ANTIALIASING_EDGE_USED) && !defined(MODE_RENDER_MATERIAL)
	alpha = 1.0;
#endif // (ALPHA_SCISSOR_USED || ALPHA_HASH_USED) && !ALPHA_ANTIALIASING_EDGE_USED && !MODE_RENDER_MATERIAL


#ifdef ALPHA_ANTIALIASING_EDGE_USED
	// If alpha scissor is used, we must further the edge threshold, otherwise we won't get any edge feather.
#ifdef ALPHA_SCISSOR_USED
	alpha_antialiasing_edge = clamp(alpha_scissor_threshold + alpha_antialiasing_edge, 0.0, 1.0);
#endif // ALPHA_SCISSOR_USED
	alpha = compute_alpha_antialiasing_edge(alpha, alpha_texture_coordinate, alpha_antialiasing_edge);
#endif // ALPHA_ANTIALIASING_EDGE_USED


#ifdef MODE_RENDER_PREPASS
#if defined(USE_OPAQUE_PREPASS) || defined(ALPHA_ANTIALIASING_EDGE_USED)
	if (alpha < scene_data.opaque_prepass_threshold)
		discard;
#endif // USE_OPAQUE_PREPASS || ALPHA_ANTIALIASING_EDGE_USED
#endif // MODE_RENDER_PREPASS

#endif // !USE_SHADOW_TO_OPACITY

	// Perform alpha clipping for material prepass and shadowmapping.
#ifdef ENABLE_CLIP_ALPHA
#ifdef MODE_RENDER_MATERIAL
	if (albedo.a < 0.99)
	{
		albedo.a = 0.0;
		alpha = 0.0;
	}
	else
	{
		albedo.a = 1.0;
		alpha = 1.0;
	}
#else // MODE_RENDER_MATERIAL
	if (albedo.a < 0.99)
		discard;  
#endif // MODE_RENDER_MATERIAL
#endif // ENABLE_CLIP_ALPHA


	// Transform Normal Map //
#if defined(NORMAL_MAP_USED)
	normal_map.xy = normal_map.xy * 2.0 - 1.0;
	normal_map.z = sqrt(max(0.0, 1.0 - dot(normal_map.xy, normal_map.xy)));  // Always reconstruct Z component.

	// Tangent-space transformation is performed using unnormalized TBN vectors, per MikkTSpace.
	// See: http://www.mikktspace.com/
	normal = normalize(mix(normal, tangent * normal_map.x + bitangent * normal_map.y + normal * normal_map.z, normal_map_depth));
#elif defined(NORMAL_USED)
	normal = geo_normal;
#endif // NORMAL_MAP_USED || NORMAL_MAP_USED


	// Transform Bent-Normal Map //
#ifdef BENT_NORMAL_MAP_USED
	bent_normal_map.xy = bent_normal_map.xy * 2.0 - 1.0;
	bent_normal_map.z = sqrt(max(0.0, 1.0 - dot(bent_normal_map.xy, bent_normal_map.xy)));
	bent_normal_vector = normalize(tangent * bent_normal_map.x + bitangent * bent_normal_map.y + normal * bent_normal_map.z);
#endif // BENT_NORMAL_MAP_USED


	// Calculate Anisotropy Tangents //
#ifdef LIGHT_ANISOTROPY_USED
	// Tangents used for anisotropy must be made orthogonal to per-pixel normals.
	// Without this, specular highlights become warped and fail to interact with normal maps.
	vec3 aniso_tangent = normalize(cross(bitangent, normal));
	vec3 aniso_bitangent = cross(normal, aniso_tangent);  // No need to normalize, as the cross product of two orthogonal normalized vectors is itself normalized.
	if (abs(anisotropy) > 0.01)
	{
		mat3 rot = mat3(aniso_tangent, aniso_bitangent, normal);
		anisotropy_flow = normalize(anisotropy_flow);
		aniso_tangent = rot * vec3(anisotropy_flow.x, anisotropy_flow.y, 0.0);
		aniso_bitangent = rot * vec3(-anisotropy_flow.y, anisotropy_flow.x, 0.0);
	}
#endif // LIGHT_ANISOTROPY_USED


	////////////////
	////  FOG  ////
	// Fog is processed as early as possible and then packed to minimize VGPR usage.
	// Depth fog is drawn before volumetric fog to ensure volumetric fog can appear in front of the sky.

#ifndef MODE_RENDER_PREPASS
#ifndef FOG_DISABLED

#ifndef CUSTOM_FOG_USED
	if (bool(scene_data.flags & SCENE_DATA_FLAGS_USE_FOG))
	{
		fog = fog_process(vertex);
		// Premultiply by opacity and convert to transmittance to match volumetric fog.
		fog.rgb *= fog.a;
		fog.a = 1.0 - fog.a;
	}

	if (implementation_data.volumetric_fog_enabled)
	{
#ifdef USE_MULTIVIEW
		vec4 volumetric_fog = volumetric_fog_process(combined_uv, -vertex.z);
#else
		vec4 volumetric_fog = volumetric_fog_process(screen_uv, -vertex.z);
#endif // USE_MULTIVIEW
		if (bool(scene_data.flags & SCENE_DATA_FLAGS_USE_FOG))
		{
			//must use the full blending equation here to blend fogs
			if (sc_fog_use_legacy_blending())
			{
				fog.a = mix(0.0, fog.a, volumetric_fog.a);
				fog.rgb = mix(volumetric_fog.rgb, fog.rgb, volumetric_fog.a);
			}
			else
			{
				fog.a = fog.a * volumetric_fog.a;
				fog.rgb = fog.rgb * volumetric_fog.a + volumetric_fog.rgb;
			}
		}
		else
		{
			fog = volumetric_fog;
			if (sc_fog_use_legacy_blending())
				fog.rgb *= 1.0 - fog.a;
		}
	}
#else  // !CUSTOM_FOG_USED
	// Premultiply by opacity and convert to transmittance to match volumetric fog.
	fog.rgb *= fog.a;
	fog.a = 1.0 - fog.a;
#endif // !CUSTOM_FOG_USED

	uint fog_rg = packHalf2x16(fog.rg);
	uint fog_ba = packHalf2x16(fog.ba);

#endif // !FOG_DISABLED
#endif // !MODE_RENDER_PREPASS


	/////////////////////////////
	////  Projected Decals  ////

#ifndef MODE_RENDER_PREPASS

#ifdef USE_MULTIVIEW
	uvec2 cluster_pos = uvec2(combined_uv.xy / scene_data.screen_pixel_size) >> implementation_data.cluster_shift;
#else
	uvec2 cluster_pos = uvec2(gl_FragCoord.xy) >> implementation_data.cluster_shift;
#endif // USE_MULTIVIEW
	uint cluster_offset = (implementation_data.cluster_width * cluster_pos.y + cluster_pos.x) * (implementation_data.max_cluster_element_count_div_32 + 32);

	uint cluster_z = uint(clamp((-vertex.z / scene_data.z_far) * 32.0, 0.0, 31.0));

	// Needed to compute projected decal UV gradients.
	vec3 vertex_ddx = dFdxCoarse(vertex), vertex_ddy = dFdyCoarse(vertex);

	// Process Decals //
	{
		const uint cluster_decal_offset = cluster_offset + implementation_data.cluster_type_size * 3;

		uint item_min, item_max, item_from, item_to;
		cluster_get_item_range(cluster_decal_offset + implementation_data.max_cluster_element_count_div_32 + cluster_z, item_min, item_max, item_from, item_to);

		item_from = subgroupBroadcastFirst(subgroupMin(item_from));
		item_to = subgroupBroadcastFirst(subgroupMax(item_to));

		for (uint i = item_from; i < item_to; i++)
		{
			uint mask = cluster_buffer.data[cluster_decal_offset + i];
			mask &= cluster_get_range_clip_mask(i, item_min, item_max);

			uint merged_mask = subgroupBroadcastFirst(subgroupOr(mask));
			while (merged_mask != 0)
			{
				uint bit = findMSB(merged_mask);
				merged_mask &= ~(1u << bit);

				if (((1u << bit) & mask) == 0)
					continue;

				uint decal_index = 32 * i + bit;

				if (!bool(decals.data[decal_index].mask & instances.data[instance_index].layer_mask))
					continue;  // Not masked, skip.

				vec3 uv_local = (decals.data[decal_index].xform * vec4(vertex, 1.0)).xyz;
				if (any(lessThan(uv_local, vec3(0.0, -1.0, 0.0))) || any(greaterThan(uv_local, vec3(1.0))))
					continue;  // Fragment outside of decal bounds.

				float fade = pow(1.0 - (uv_local.y > 0.0 ? uv_local.y : -uv_local.y), uv_local.y > 0.0 ? decals.data[decal_index].upper_fade : decals.data[decal_index].lower_fade);
				if (decals.data[decal_index].normal_fade > 0.0)
					fade *= smoothstep(decals.data[decal_index].normal_fade, 1.0, dot(geo_normal, decals.data[decal_index].normal) * 0.5 + 0.5);

				// Transform derivatives into decal-space.
				vec2 ddx = (decals.data[decal_index].xform * vec4(vertex_ddx, 0.0)).xz;
				vec2 ddy = (decals.data[decal_index].xform * vec4(vertex_ddy, 0.0)).xz;

				if (decals.data[decal_index].albedo_rect != vec4(0.0))
				{
					vec4 decal_albedo;
					if (sc_decal_use_mipmaps())
						decal_albedo = textureGrad(sampler2D(decal_atlas_srgb, decal_sampler), uv_local.xz * decals.data[decal_index].albedo_rect.zw + decals.data[decal_index].albedo_rect.xy, ddx * decals.data[decal_index].albedo_rect.zw, ddy * decals.data[decal_index].albedo_rect.zw);
					else
						decal_albedo = textureLod(sampler2D(decal_atlas_srgb, decal_sampler), uv_local.xz * decals.data[decal_index].albedo_rect.zw + decals.data[decal_index].albedo_rect.xy, 0.0);

					decal_albedo *= decals.data[decal_index].modulate;
					decal_albedo.a *= fade;
					albedo = mix(albedo, decal_albedo.rgb, decal_albedo.a * decals.data[decal_index].albedo_mix);

					// Normal and ORM textures require albedo, as they share its alpha channel.
					if (decals.data[decal_index].normal_rect != vec4(0.0))
					{
						vec3 decal_normal;
						if (sc_decal_use_mipmaps())
							decal_normal = textureGrad(sampler2D(decal_atlas, decal_sampler), uv_local.xz * decals.data[decal_index].normal_rect.zw + decals.data[decal_index].normal_rect.xy, ddx * decals.data[decal_index].normal_rect.zw, ddy * decals.data[decal_index].normal_rect.zw).xyz;
						else
							decal_normal = textureLod(sampler2D(decal_atlas, decal_sampler), uv_local.xz * decals.data[decal_index].normal_rect.zw + decals.data[decal_index].normal_rect.xy, 0.0).xyz;

						decal_normal.xy = decal_normal.xy * vec2(2.0, -2.0) - vec2(1.0, -1.0);
						decal_normal.z = sqrt(max(0.0, 1.0 - dot(decal_normal.xy, decal_normal.xy)));
						
						decal_normal = (decals.data[decal_index].normal_xform * decal_normal.xzy).xyz;  // Convert to view space, use .xzy because Y is up.

						normal = normalize(mix(normal, decal_normal, decal_albedo.a));
					}
					if (decals.data[decal_index].orm_rect != vec4(0.0))
					{
						vec3 decal_orm;
						if (sc_decal_use_mipmaps())
							decal_orm = textureGrad(sampler2D(decal_atlas, decal_sampler), uv_local.xz * decals.data[decal_index].orm_rect.zw + decals.data[decal_index].orm_rect.xy, ddx * decals.data[decal_index].orm_rect.zw, ddy * decals.data[decal_index].orm_rect.zw).xyz;
						else
							decal_orm = textureLod(sampler2D(decal_atlas, decal_sampler), uv_local.xz * decals.data[decal_index].orm_rect.zw + decals.data[decal_index].orm_rect.xy, 0.0).xyz;
						
						ao = mix(ao, decal_orm.r, decal_albedo.a);
						roughness = mix(roughness, decal_orm.g, decal_albedo.a);
						metallic = mix(metallic, decal_orm.b, decal_albedo.a);
					}
				}

				// Emission is additive, so is independent from albedo.
				if (decals.data[decal_index].emission_rect != vec4(0.0))
				{
					if (sc_decal_use_mipmaps())
						emission += textureGrad(sampler2D(decal_atlas_srgb, decal_sampler), uv_local.xz * decals.data[decal_index].emission_rect.zw + decals.data[decal_index].emission_rect.xy, ddx * decals.data[decal_index].emission_rect.zw, ddy * decals.data[decal_index].emission_rect.zw).xyz * decals.data[decal_index].modulate.rgb * decals.data[decal_index].emission_energy * fade;
					else
						emission += textureLod(sampler2D(decal_atlas_srgb, decal_sampler), uv_local.xz * decals.data[decal_index].emission_rect.zw + decals.data[decal_index].emission_rect.xy, 0.0).xyz * decals.data[decal_index].modulate.rgb * decals.data[decal_index].emission_energy * fade;
				}
			}
		}
	}
#endif // !MODE_RENDER_PREPASS


	// Apply Geometric Specular Anti-aliasing //
	// https://www.jp.square-enix.com/tech/library/pdf/ImprovedGeometricSpecularAA.pdf
#ifdef NORMAL_USED
	if (bool(scene_data.flags & SCENE_DATA_FLAGS_USE_ROUGHNESS_LIMITER))
	{
		vec3 dndu = dFdxFine(geo_normal), dndv = dFdyFine(geo_normal);
		float variance = 2.0 * (dot(dndu, dndu) + dot(dndv, dndv));
		float kernel_roughness_sqr = min(variance * scene_data.roughness_limiter_amount, scene_data.roughness_limiter_limit);
		roughness = sqrt(min(1.0, roughness * roughness + kernel_roughness_sqr));
#ifdef LIGHT_CLEARCOAT_USED
		clearcoat_roughness = sqrt(min(1.0, clearcoat_roughness * clearcoat_roughness + kernel_roughness_sqr));
#endif // LIGHT_CLEARCOAT_USED
	}
#endif // NORMAL_USED

	// Force specular parameters to 0 when specularity is disabled, as the material is effectively diffuse-only.
#ifdef SPECULAR_DISABLED
	specular = 0.0;
	metallic = 0.0;
	clearcoat = 0.0;
#endif // SPECULAR_DISABLED



///////////////////////////////////////////////////////////////////////////////
////  LIGHTING  //////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////


#if !defined(MODE_RENDER_PREPASS) && !defined(MODE_UNSHADED)

	// Get Screen Buffer Coords //
	vec2 buffer_uv = screen_uv;
	if (implementation_data.gi_upscale_for_msaa && ((!sc_use_forward_gi() && bool(instances.data[instance_index].flags & INSTANCE_FLAGS_USE_GI_BUFFERS)) || bool(implementation_data.ss_effects_flags & SCREEN_SPACE_EFFECTS_FLAGS_USE_SSAO)))
	{
#ifdef USE_MULTIVIEW
		float closest_ang = dot(normal, normalize(textureLod(sampler2DArray(normal_roughness_buffer, SAMPLER_LINEAR_CLAMP), vec3(buffer_uv, ViewIndex), 0.0).xyz * 2.0 - 1.0));
#else // USE_MULTIVIEW
		float closest_ang = dot(normal, normalize(textureLod(sampler2D(normal_roughness_buffer, SAMPLER_LINEAR_CLAMP), buffer_uv, 0.0).xyz * 2.0 - 1.0));
#endif // USE_MULTIVIEW

		for (int i = 0; i < 4; i++)
		{
			const vec2 neighbors[4] = vec2[](vec2(-1, 0), vec2( 1, 0), vec2( 0,-1), vec2( 0, 1));
			vec2 neighbour_coord = screen_uv + neighbors[i] * scene_data.screen_pixel_size;
#ifdef USE_MULTIVIEW
			float neighbour_ang = dot(normal, normalize(textureLod(sampler2DArray(normal_roughness_buffer, SAMPLER_LINEAR_CLAMP), vec3(neighbour_coord, ViewIndex), 0.0).xyz * 2.0 - 1.0));
#else // USE_MULTIVIEW
			float neighbour_ang = dot(normal, normalize(textureLod(sampler2D(normal_roughness_buffer, SAMPLER_LINEAR_CLAMP), neighbour_coord, 0.0).xyz * 2.0 - 1.0));
#endif // USE_MULTIVIEW
			if (neighbour_ang > closest_ang)
			{
				closest_ang = neighbour_ang;
				buffer_uv = neighbour_coord;
			}
		}
	}

	// Get SSAO //
	// NOTE: SSAO can affect both direct and indirect light, hence we retrieve it before processing either.
	float direct_ao = mix(1.0, ao, ao_light_affect);
#ifdef AMBIENT_LIGHT_DISABLED
	// When indirect light is disabled, only sample SSAO if it will affect direct lighting.
	if (bool(implementation_data.ss_effects_flags & SCREEN_SPACE_EFFECTS_FLAGS_USE_SSAO) && (implementation_data.ssao_light_affect + ao_light_affect) > 0.001)
#else
	if (bool(implementation_data.ss_effects_flags & SCREEN_SPACE_EFFECTS_FLAGS_USE_SSAO))
#endif // AMBIENT_LIGHT_DISABLED
	{
#ifdef USE_MULTIVIEW
		float ssao = texture(sampler2DArray(ao_buffer, SAMPLER_LINEAR_CLAMP), vec3(buffer_uv, ViewIndex)).r;
#else  // USE_MULTIVIEW
		float ssao = texture(sampler2D(ao_buffer, SAMPLER_LINEAR_CLAMP), buffer_uv).r;
#endif // USE_MULTIVIEW
		
		float direct_ssao = mix(1.0, ssao, implementation_data.ssao_light_affect);
		direct_ao = mix(min(direct_ao, direct_ssao), direct_ao * direct_ssao, implementation_data.ssao_ao_affect);
		ao = mix(min(ao, ssao), ao * ssao, implementation_data.ssao_ao_affect);
	}


	///////////////////////////
	////  Indirect Light  ////

	vec3 indirect_diffuse = vec3(0.0);
	vec3 indirect_specular = vec3(0.0);  // Always defined, but never output when SPECULAR_DISABLED is defined, in which case anything modifying it is compiled out.
	
#ifdef USE_IRRADIANCE_MATCHING
	float hi_irradiance = 0.0;
#ifdef LIGHT_CLEARCOAT_USED
	float cc_hi_irradiance = 0.0;
#endif // LIGHT_CLEARCOAT_USED
#endif // USE_IRRADIANCE_MATCHING

#if !defined(AMBIENT_LIGHT_DISABLED) || defined(USE_VERTEX_LIGHTING)
#ifdef BENT_NORMAL_MAP_USED
	vec3 irradiance_vec = bent_normal_vector;  // Use bent normal for indirect lighting where possible.
#else  // BENT_NORMAL_MAP_USED
	vec3 irradiance_vec = normal;
#endif // BENT_NORMAL_MAP_USED

#ifndef SPECULAR_DISABLED
#ifdef LIGHT_ANISOTROPY_USED
	// https://google.github.io/filament/Filament.html#lighting/imagebasedlights/anisotropy
	vec3 anisotropic_direction = anisotropy >= 0.0 ? aniso_bitangent : aniso_tangent;
	vec3 anisotropic_tangent = cross(anisotropic_direction, view);
	vec3 anisotropic_normal = cross(anisotropic_tangent, anisotropic_direction);
	vec3 bent_normal = normalize(mix(normal, anisotropic_normal, abs(anisotropy) * clamp(5.0 * roughness, 0.0, 1.0)));
	vec3 radiance_vec = reflect(-view, bent_normal);
	radiance_vec = normalize(mix(radiance_vec, bent_normal, roughness * roughness));
#else  // LIGHT_ANISOTROPY_USED
	vec3 radiance_vec = reflect(-view, normal);
	radiance_vec = normalize(mix(radiance_vec, normal, roughness * roughness));
#endif // LIGHT_ANISOTROPY_USED
#else  // !SPECULAR_DISABLED
	vec3 radiance_vec = vec3(0.0);
#endif // !SPECULAR_DISABLED

#endif // !AMBIENT_LIGHT_DISABLED || USE_VERTEX_LIGHTING


#ifndef AMBIENT_LIGHT_DISABLED
#ifndef SPECULAR_DISABLED

	if (bool(scene_data.flags & SCENE_DATA_FLAGS_USE_AMBIENT_LIGHT))
	{
		indirect_specular = scene_data.ambient_light_color_energy.rgb;
#ifdef USE_IRRADIANCE_MATCHING
		// Divide reflected irradiance out of radiance, will be multiplied back in if nothing better is available.
		hi_irradiance = dot(indirect_specular, vec3(1.0/3.0));
		indirect_specular *= IRR_MATCH_LAMBDA_N / (hi_irradiance + IRR_MATCH_LAMBDA_D);
#endif // USE_IRRADIANCE_MATCHING
	}

	// Get Sky Radiance //
	if (bool(scene_data.flags & SCENE_DATA_FLAGS_USE_REFLECTION_CUBEMAP))
	{
		vec3 ref_vec = scene_data.radiance_inverse_xform * radiance_vec;

#ifdef USE_RADIANCE_OCTMAP_ARRAY
		float roughness_lod, blend;
		blend = modf(sqrt(roughness) * MAX_ROUGHNESS_LOD, roughness_lod);

		float ref_lod = vec3_to_oct_lod(dFdxCoarse(ref_vec), dFdyCoarse(ref_vec), scene_data_block.data.radiance_pixel_size);
		vec2 ref_uv = vec3_to_oct_with_border(ref_vec, vec2(scene_data_block.data.radiance_border_size, 1.0 - scene_data_block.data.radiance_border_size * 2.0));
		vec3 sky_sample_a = textureLod(sampler2DArray(radiance_octmap, DEFAULT_SAMPLER_LINEAR_WITH_MIPMAPS_CLAMP), vec3(ref_uv, roughness_lod), ref_lod).rgb;
		vec3 sky_sample_b = textureLod(sampler2DArray(radiance_octmap, DEFAULT_SAMPLER_LINEAR_WITH_MIPMAPS_CLAMP), vec3(ref_uv, roughness_lod + 1), ref_lod).rgb;
		vec3 sky_radiance = mix(sky_sample_a, sky_sample_b, blend);
#else  // USE_RADIANCE_OCTMAP_ARRAY
		float roughness_lod = sqrt(roughness) * MAX_ROUGHNESS_LOD;
		vec2 ref_uv = vec3_to_oct_with_border(ref_vec, vec2(scene_data_block.data.radiance_border_size, 1.0 - scene_data_block.data.radiance_border_size * 2.0));
		vec3 sky_radiance = textureLod(sampler2D(radiance_octmap, DEFAULT_SAMPLER_LINEAR_WITH_MIPMAPS_CLAMP), ref_uv, roughness_lod).rgb;
#endif // USE_RADIANCE_OCTMAP_ARRAY
		
#ifdef USE_IRRADIANCE_MATCHING
		// Divide reflected irradiance out of radiance.
#ifdef USE_RADIANCE_OCTMAP_ARRAY
		float lo_irradiance = dot(textureLod(sampler2DArray(radiance_octmap, DEFAULT_SAMPLER_LINEAR_WITH_MIPMAPS_CLAMP), vec3(ref_uv, MAX_ROUGHNESS_LOD), ref_lod).rgb, vec3(1.0/3.0));
#else  // USE_RADIANCE_OCTMAP_ARRAY
		float lo_irradiance = dot(textureLod(sampler2D(radiance_octmap, DEFAULT_SAMPLER_LINEAR_WITH_MIPMAPS_CLAMP), ref_uv, MAX_ROUGHNESS_LOD).rgb, vec3(1.0/3.0));
#endif // USE_RADIANCE_OCTMAP_ARRAY
		sky_radiance *= IRR_MATCH_LAMBDA_N / (lo_irradiance + IRR_MATCH_LAMBDA_D);
#endif // USE_IRRADIANCE_MATCHING

		sky_radiance *= scene_data.IBL_exposure_normalization * scene_data.ambient_light_color_energy.a;
		indirect_specular = mix(indirect_specular, sky_radiance, scene_data.ambient_color_sky_mix);
	}

#ifdef LIGHT_CLEARCOAT_USED
	vec3 cc_radiance_vec = reflect(-view, geo_normal);  // Clearcoat layer uses geometric normal.
	vec3 cc_indirect_specular = vec3(0.0);
	if (bool(scene_data.flags & SCENE_DATA_FLAGS_USE_AMBIENT_LIGHT))
	{
		cc_indirect_specular = scene_data.ambient_light_color_energy.rgb;
#ifdef USE_IRRADIANCE_MATCHING
		cc_hi_irradiance = dot(cc_indirect_specular, vec3(1.0/3.0));
		cc_indirect_specular *= IRR_MATCH_LAMBDA_N / (hi_irradiance + IRR_MATCH_LAMBDA_D);
#endif // USE_IRRADIANCE_MATCHING
	}

	// Get Sky Radiance for Clearcoat //
	if (bool(scene_data.flags & SCENE_DATA_FLAGS_USE_REFLECTION_CUBEMAP))
	{
		vec3 cc_ref_vec = scene_data.radiance_inverse_xform * cc_radiance_vec;
		
		float roughness_lod = sqrt(clearcoat_roughness) * MAX_ROUGHNESS_LOD;
#ifdef USE_RADIANCE_OCTMAP_ARRAY
		float lod, blend;
		blend = modf(roughness_lod, lod);

		float cc_ref_lod = vec3_to_oct_lod(dFdxCoarse(cc_ref_vec), dFdyCoarse(cc_ref_vec), scene_data_block.data.radiance_pixel_size);
		vec2 cc_ref_uv = vec3_to_oct_with_border(cc_ref_vec, vec2(scene_data_block.data.radiance_border_size, 1.0 - scene_data_block.data.radiance_border_size * 2.0));
		vec3 cc_sky_sample_a = textureLod(sampler2DArray(radiance_octmap, DEFAULT_SAMPLER_LINEAR_WITH_MIPMAPS_CLAMP), vec3(cc_ref_uv, lod), cc_ref_lod).rgb;
		vec3 cc_sky_sample_b = textureLod(sampler2DArray(radiance_octmap, DEFAULT_SAMPLER_LINEAR_WITH_MIPMAPS_CLAMP), vec3(cc_ref_uv, lod + 1), cc_ref_lod).rgb;
		vec3 cc_sky_radiance = mix(cc_sky_sample_a, cc_sky_sample_b, blend);
#else  // USE_RADIANCE_OCTMAP_ARRAY
		vec2 cc_ref_uv = vec3_to_oct_with_border(cc_ref_vec, vec2(scene_data_block.data.radiance_border_size, 1.0 - scene_data_block.data.radiance_border_size * 2.0));
		vec3 cc_sky_radiance = textureLod(sampler2D(radiance_octmap, DEFAULT_SAMPLER_LINEAR_WITH_MIPMAPS_CLAMP), cc_ref_uv, roughness_lod).rgb;
#endif // USE_RADIANCE_OCTMAP_ARRAY

#ifdef USE_IRRADIANCE_MATCHING
		// Divide reflected irradiance out of radiance.
#ifdef USE_RADIANCE_OCTMAP_ARRAY
		float cc_lo_irradiance = dot(textureLod(sampler2DArray(radiance_octmap, DEFAULT_SAMPLER_LINEAR_WITH_MIPMAPS_CLAMP), vec3(cc_ref_uv, MAX_ROUGHNESS_LOD), cc_ref_lod).rgb, vec3(1.0/3.0));
#else  // USE_RADIANCE_OCTMAP_ARRAY
		float cc_lo_irradiance = dot(textureLod(sampler2D(radiance_octmap, DEFAULT_SAMPLER_LINEAR_WITH_MIPMAPS_CLAMP), cc_ref_uv, MAX_ROUGHNESS_LOD).rgb, vec3(1.0/3.0));
#endif // USE_RADIANCE_OCTMAP_ARRAY
		cc_sky_radiance *= IRR_MATCH_LAMBDA_N / (cc_lo_irradiance + IRR_MATCH_LAMBDA_D);
#endif // USE_IRRADIANCE_MATCHING

		cc_sky_radiance *= scene_data.IBL_exposure_normalization * scene_data.ambient_light_color_energy.a;
		cc_indirect_specular = mix(cc_indirect_specular, cc_sky_radiance, scene_data.ambient_color_sky_mix);
	}
#endif // LIGHT_CLEARCOAT_USED

	// Blend custom radiance over sky radiance.
#ifdef CUSTOM_RADIANCE_USED
	indirect_specular = mix(indirect_specular, custom_radiance.rgb, custom_radiance.a);
#ifdef LIGHT_CLEARCOAT_USED
	cc_indirect_specular = mix(cc_indirect_specular, custom_radiance.rgb, custom_radiance.a);
#endif // LIGHT_CLEARCOAT_USED
#endif // CUSTOM_RADIANCE_USED
#endif // !SPECULAR_DISABLED


#ifndef USE_LIGHTMAP  // Lightmap overrides sky irradiance.
	if (bool(scene_data.flags & SCENE_DATA_FLAGS_USE_AMBIENT_LIGHT))
	{
		indirect_diffuse = scene_data.ambient_light_color_energy.rgb;

		// Get Sky Irradiance //
		if (bool(scene_data.flags & SCENE_DATA_FLAGS_USE_AMBIENT_CUBEMAP))
		{
			vec3 ambient_dir = scene_data.radiance_inverse_xform * irradiance_vec;
#ifdef USE_RADIANCE_OCTMAP_ARRAY
			float sky_lod = vec3_to_oct_lod(dFdxCoarse(ambient_dir), dFdyCoarse(ambient_dir), scene_data_block.data.radiance_pixel_size);
			vec2 sky_uv = vec3_to_oct_with_border(ambient_dir, vec2(scene_data_block.data.radiance_border_size, 1.0 - scene_data_block.data.radiance_border_size * 2.0));
			vec3 sky_irradiance = textureLod(sampler2DArray(radiance_octmap, DEFAULT_SAMPLER_LINEAR_WITH_MIPMAPS_CLAMP), vec3(sky_uv, MAX_ROUGHNESS_LOD), sky_lod).rgb;
#else  // USE_RADIANCE_OCTMAP_ARRAY
			vec2 sky_uv = vec3_to_oct_with_border(ambient_dir, vec2(scene_data_block.data.radiance_border_size, 1.0 - scene_data_block.data.radiance_border_size * 2.0));
			vec3 sky_irradiance = textureLod(sampler2D(radiance_octmap, DEFAULT_SAMPLER_LINEAR_WITH_MIPMAPS_CLAMP), sky_uv, MAX_ROUGHNESS_LOD).rgb;
#endif // USE_RADIANCE_OCTMAP_ARRAY

			sky_irradiance *= scene_data.IBL_exposure_normalization * scene_data.ambient_light_color_energy.a;
			indirect_diffuse = mix(indirect_diffuse, sky_irradiance, scene_data.ambient_color_sky_mix);
		}
	}
#endif // !USE_LIGHTMAP

	// Blend custom irradiance over sky irradiance.
#ifdef CUSTOM_IRRADIANCE_USED
	indirect_diffuse = mix(indirect_diffuse, custom_irradiance.rgb, custom_irradiance.a);
#endif // CUSTOM_IRRADIANCE_USED


	// Get Baked Lightmap Data //
#ifdef USE_LIGHTMAP
	if (bool(instances.data[instance_index].flags & INSTANCE_FLAGS_USE_LIGHTMAP_CAPTURE))
	{
		// Lightmap Probe //
		const uint index = instances.data[instance_index].gi_offset;
		const LightmapCapture lm_probe = lightmap_captures.data[index];
		
		vec3 world_normal = mat3(inv_view_matrix) * irradiance_vec;
		vec3 probe_diffuse = sh_l2_evaluate(lm_probe.sh, world_normal) * scene_data.IBL_exposure_normalization;
		indirect_diffuse += probe_diffuse;

#ifndef SPECULAR_DISABLED
		vec3 world_reflect = mat3(inv_view_matrix) * radiance_vec;
		vec3 probe_specular = sh_l2_evaluate(lm_probe.sh, world_reflect) * scene_data.IBL_exposure_normalization * (1.0 / M_PI);
#ifdef LIGHT_CLEARCOAT_USED
		vec3 cc_world_reflect = mat3(inv_view_matrix) * cc_radiance_vec;
		vec3 cc_probe_specular = sh_l2_evaluate(lm_probe.sh, cc_world_reflect) * scene_data.IBL_exposure_normalization * (1.0 / M_PI);
#endif // LIGHT_CLEARCOAT_USED

#ifdef USE_IRRADIANCE_MATCHING
		// Divide reflected irradiance out of radiance, will be multiplied back in if nothing better is available.
		hi_irradiance = dot(probe_specular, vec3(1.0/3.0));
		probe_specular *= IRR_MATCH_LAMBDA_N / (hi_irradiance + IRR_MATCH_LAMBDA_D);
#ifdef LIGHT_CLEARCOAT_USED
		cc_hi_irradiance = dot(cc_probe_specular, vec3(1.0/3.0));
		cc_probe_specular *= IRR_MATCH_LAMBDA_N / (cc_hi_irradiance + IRR_MATCH_LAMBDA_D);
#endif // LIGHT_CLEARCOAT_USED
#endif // USE_IRRADIANCE_MATCHING

		if (!bool(scene_data.flags & SCENE_DATA_FLAGS_USE_REFLECTION_CUBEMAP))
		{
			indirect_specular += probe_specular;
#ifdef LIGHT_CLEARCOAT_USED
			cc_indirect_specular += cc_probe_specular;
#endif // LIGHT_CLEARCOAT_USED
		}
#endif // !SPECULAR_DISABLED
	}
	else if (bool(instances.data[instance_index].flags & INSTANCE_FLAGS_USE_LIGHTMAP))
	{
		// Lightmap Texture //
		const uint idx = instances.data[instance_index].gi_offset & 0xFFFF;
		const uint slice = instances.data[instance_index].gi_offset >> 16;

		const Lightmap lm_data = lightmaps.data[idx];

		vec3 uvw = vec3(
				uv2 * instances.data[instance_index].lightmap_uv_scale.zw + instances.data[instance_index].lightmap_uv_scale.xy,
				float(slice)
		);
		vec3 lm_diffuse = vec3(0.0);
#ifndef SPECULAR_DISABLED
		vec3 lm_specular = vec3(0.0);
#ifdef LIGHT_CLEARCOAT_USED
		vec3 cc_lm_specular = vec3(0.0);
#endif // LIGHT_CLEARCOAT_USED
#endif // !SPECULAR_DISABLED
		if (bool(instances.data[instance_index].flags & INSTANCE_FLAGS_USE_SH_LIGHTMAP))
		{
			// Directional (L1 SH) Lightmap Texture //
			uvw.z *= 4.0;  // SH textures use 4 times more data, so stride accordingly.
			vec3 lm_light_l0, lm_light_l1n1, lm_light_l1_0, lm_light_l1p1;
			if (sc_use_lightmap_bicubic_filter())
			{
				lm_light_l0   = textureArray_bicubic(lightmap_textures[idx], uvw + vec3(0.0, 0.0, 0.0), lm_data.light_texture_size).rgb;
				lm_light_l1n1 = textureArray_bicubic(lightmap_textures[idx], uvw + vec3(0.0, 0.0, 1.0), lm_data.light_texture_size).rgb * vec3(2.0) - vec3(1.0);
				lm_light_l1_0 = textureArray_bicubic(lightmap_textures[idx], uvw + vec3(0.0, 0.0, 2.0), lm_data.light_texture_size).rgb * vec3(2.0) - vec3(1.0);
				lm_light_l1p1 = textureArray_bicubic(lightmap_textures[idx], uvw + vec3(0.0, 0.0, 3.0), lm_data.light_texture_size).rgb * vec3(2.0) - vec3(1.0);
			}
			else
			{
				lm_light_l0   = textureLod(sampler2DArray(lightmap_textures[idx], SAMPLER_LINEAR_CLAMP), uvw + vec3(0.0, 0.0, 0.0), 0.0).rgb;
				lm_light_l1n1 = textureLod(sampler2DArray(lightmap_textures[idx], SAMPLER_LINEAR_CLAMP), uvw + vec3(0.0, 0.0, 1.0), 0.0).rgb * vec3(2.0) - vec3(1.0);
				lm_light_l1_0 = textureLod(sampler2DArray(lightmap_textures[idx], SAMPLER_LINEAR_CLAMP), uvw + vec3(0.0, 0.0, 2.0), 0.0).rgb * vec3(2.0) - vec3(1.0);
				lm_light_l1p1 = textureLod(sampler2DArray(lightmap_textures[idx], SAMPLER_LINEAR_CLAMP), uvw + vec3(0.0, 0.0, 3.0), 0.0).rgb * vec3(2.0) - vec3(1.0);
			}
			lm_light_l1p1 *= lm_light_l0 * 4.0;
			lm_light_l1n1 *= lm_light_l0 * 4.0;
			lm_light_l1_0 *= lm_light_l0 * 4.0;

#ifdef LIGHTMAP_HIGH_QUALITY_SH
			vec3 sh_zonal_axis, sh_zl2_coeff;
			sh_l1_get_zh3_band(lm_light_l0, lm_light_l1p1, lm_light_l1n1, lm_light_l1_0, sh_zonal_axis, sh_zl2_coeff);
#endif // LIGHTMAP_HIGH_QUALITY_SH

			vec3 n = normalize(lm_data.normal_xform * irradiance_vec);
#ifdef LIGHTMAP_HIGH_QUALITY_SH
			lm_diffuse = sh_l1_evaluate_zh3(n, lm_light_l0, lm_light_l1p1, lm_light_l1n1, lm_light_l1_0, sh_zonal_axis, sh_zl2_coeff) * lm_data.exposure_normalization;
#else
			lm_diffuse = sh_l1_evaluate(n, lm_light_l0, lm_light_l1p1, lm_light_l1n1, lm_light_l1_0) * lm_data.exposure_normalization;
#endif // LIGHTMAP_HIGH_QUALITY_SH
#ifndef SPECULAR_DISABLED
			vec3 r = normalize(lm_data.normal_xform * radiance_vec);
#ifdef LIGHTMAP_HIGH_QUALITY_SH
			lm_specular = sh_l1_evaluate_zh3(r, lm_light_l0, lm_light_l1p1, lm_light_l1n1, lm_light_l1_0, sh_zonal_axis, sh_zl2_coeff) * lm_data.exposure_normalization * (1.0 / M_PI);
#else
			lm_specular = sh_l1_evaluate(r, lm_light_l0, lm_light_l1p1, lm_light_l1n1, lm_light_l1_0) * lm_data.exposure_normalization * (1.0 / M_PI);
#endif // LIGHTMAP_HIGH_QUALITY_SH
#ifdef LIGHT_CLEARCOAT_USED
			vec3 cc_r = normalize(lm_data.normal_xform * cc_radiance_vec);
#ifdef LIGHTMAP_HIGH_QUALITY_SH
			cc_lm_specular = sh_l1_evaluate_zh3(cc_r, lm_light_l0, lm_light_l1p1, lm_light_l1n1, lm_light_l1_0, sh_zonal_axis, sh_zl2_coeff) * lm_data.exposure_normalization * (1.0 / M_PI);
#else
			cc_lm_specular = sh_l1_evaluate(cc_r, lm_light_l0, lm_light_l1p1, lm_light_l1n1, lm_light_l1_0) * lm_data.exposure_normalization * (1.0 / M_PI);
#endif // LIGHTMAP_HIGH_QUALITY_SH
#endif // LIGHT_CLEARCOAT_USED
#ifdef USE_IRRADIANCE_MATCHING
			// Divide reflected irradiance out of radiance, will be multiplied back in if nothing better is available.
			hi_irradiance = dot(lm_specular, vec3(1.0/3.0));
			lm_specular *= IRR_MATCH_LAMBDA_N / (hi_irradiance + IRR_MATCH_LAMBDA_D);
#ifdef LIGHT_CLEARCOAT_USED
			cc_hi_irradiance = dot(cc_lm_specular, vec3(1.0/3.0));
			cc_lm_specular *= IRR_MATCH_LAMBDA_N / (cc_hi_irradiance + IRR_MATCH_LAMBDA_D);
#endif // LIGHT_CLEARCOAT_USED
#endif // USE_IRRADIANCE_MATCHING
#endif // !SPECULAR_DISABLED
		}
		else
		{
			// Standard Lightmap Texture //
			if (sc_use_lightmap_bicubic_filter())
				lm_diffuse = textureArray_bicubic(lightmap_textures[idx], uvw, lm_data.light_texture_size).rgb * lm_data.exposure_normalization;
			else
				lm_diffuse = textureLod(sampler2DArray(lightmap_textures[idx], SAMPLER_LINEAR_CLAMP), uvw, 0.0).rgb * lm_data.exposure_normalization;
#ifndef SPECULAR_DISABLED
			lm_specular = lm_diffuse * (1.0 / M_PI);
#ifdef USE_IRRADIANCE_MATCHING
			// Divide reflected irradiance out of radiance, will be multiplied back in if nothing better is available.
			hi_irradiance = dot(lm_specular, vec3(1.0/3.0));
			lm_specular *= IRR_MATCH_LAMBDA_N / (hi_irradiance + IRR_MATCH_LAMBDA_D);
#ifdef LIGHT_CLEARCOAT_USED
			// No directional information, so clearcoat specular is the same as base specular.
			cc_hi_irradiance = hi_irradiance;
			cc_lm_specular = lm_specular;
#endif // LIGHT_CLEARCOAT_USED
#endif // USE_IRRADIANCE_MATCHING
#endif // !SPECULAR_DISABLED
		}

		indirect_diffuse += lm_diffuse;
#ifndef SPECULAR_DISABLED
		if (!bool(scene_data.flags & SCENE_DATA_FLAGS_USE_REFLECTION_CUBEMAP))
		{
			indirect_specular += lm_specular;
#ifdef LIGHT_CLEARCOAT_USED
			cc_indirect_specular += cc_lm_specular;
#endif // LIGHT_CLEARCOAT_USED
		}
#endif // !SPECULAR_DISABLED
	}

#else  // USE_LIGHTMAP

	// Get GI Result in Forward Pass //
	if (sc_use_forward_gi())
	{
		// Get SDFGI //
		if (bool(instances.data[instance_index].flags & INSTANCE_FLAGS_USE_SDFGI))
		{
			// Make vertex orientation the world one, but still align to camera.
			vec3 cam_pos = mat3(inv_view_matrix) * vertex;
			vec3 cam_normal = mat3(inv_view_matrix) * irradiance_vec;
			vec3 cam_reflection = mat3(inv_view_matrix) * radiance_vec;

			// Apply cell Y-density.
			cam_pos.y *= sdfgi.y_mult;
			cam_normal.y *= sdfgi.y_mult;
			cam_reflection.y *= sdfgi.y_mult;
			cam_normal = normalize(cam_normal);
			cam_reflection = normalize(cam_reflection);

			vec4 light_accum = vec4(0.0);
			float weight_accum = 0.0;

			vec4 light_blend_accum = vec4(0.0);
			float weight_blend_accum = 0.0;

			float blend = 0.0;

			// Compute helper constants.
			uint cascade = 0xFFFFFFFF;
			vec3 cascade_pos, cascade_normal;
			for (uint i = 0; i < sdfgi.max_cascades; i++)
			{
				cascade_pos = (cam_pos - sdfgi.cascades[i].position) * sdfgi.cascades[i].to_probe;
				if (any(lessThan(cascade_pos, vec3(0.0))) || any(greaterThanEqual(cascade_pos, sdfgi.cascade_probe_size)))
					continue;  // Skip cascade.
				cascade = i;
				break;
			}

			if (cascade < SDFGI_MAX_CASCADES)
			{
#ifndef SPECULAR_DISABLED
#define use_specular  true
#else
#define use_specular  false
#endif // !SPECULAR_DISABLED
				float blend;
				vec3 diffuse, specular;
				sdfgi_process(cascade, cascade_pos, cam_pos, cam_normal, cam_reflection, use_specular, roughness, diffuse, specular, blend);

				// Blend with next cascade, provided this isn't the last.
				if ((cascade != sdfgi.max_cascades - 1) && (blend > 0.0))
				{
					float blend2;
					vec3 diffuse2, specular2;
					cascade_pos = (cam_pos - sdfgi.cascades[cascade + 1].position) * sdfgi.cascades[cascade + 1].to_probe;
					sdfgi_process(cascade + 1, cascade_pos, cam_pos, cam_normal, cam_reflection, use_specular, roughness, diffuse2, specular2, blend2);
					diffuse = mix(diffuse, diffuse2, blend);
#ifndef SPECULAR_DISABLED
					specular = mix(specular, specular2, blend);
#endif // !SPECULAR_DISABLED
					blend = blend2;
				}
				indirect_diffuse = mix(diffuse, indirect_diffuse, blend);
#ifndef SPECULAR_DISABLED
				indirect_specular = mix(specular, indirect_specular, blend);
#endif // !SPECULAR_DISABLED
#undef use_specular 
			}
		}

		// Get Voxel GI //
		if (bool(instances.data[instance_index].flags & INSTANCE_FLAGS_USE_VOXEL_GI))
		{
			// Make vertex orientation the world one, but still align to camera.
			vec3 cam_pos = mat3(inv_view_matrix) * vertex;
			vec3 cam_normal = mat3(inv_view_matrix) * irradiance_vec;
			vec3 ref_vec = mat3(inv_view_matrix) * radiance_vec;

			// Construct arbitrary TBN basis.
			vec3 v0 = abs(cam_normal.z) < 0.999 ? vec3(0.0, 0.0, 1.0) : vec3(0.0, 1.0, 0.0);
			vec3 tangent = normalize(cross(v0, cam_normal));
			vec3 bitangent = cross(tangent, cam_normal);
			mat3 normal_mat = mat3(tangent, bitangent, cam_normal);

			vec4 amb_accum = vec4(0.0), spec_accum = vec4(0.0);

			uint index1 = instances.data[instance_index].gi_offset & 0xFFFF;
			voxel_gi_compute(index1, cam_pos, cam_normal, ref_vec, normal_mat, roughness * roughness, indirect_diffuse, indirect_specular, spec_accum, amb_accum);

			uint index2 = instances.data[instance_index].gi_offset >> 16;
			if (index2 != 0xFFFF)
				voxel_gi_compute(index2, cam_pos, cam_normal, ref_vec, normal_mat, roughness * roughness, indirect_diffuse, indirect_specular, spec_accum, amb_accum);

			if (amb_accum.a > 0.0)
				amb_accum.rgb /= amb_accum.a;
			indirect_diffuse = amb_accum.rgb;

#ifndef SPECULAR_DISABLED
			if (spec_accum.a > 0.0)
				spec_accum.rgb /= spec_accum.a;
			indirect_specular = spec_accum.rgb;
#endif // !SPECULAR_DISABLED
		}
	}
	else
	{
		// Get Deferred GI Result from Buffers //
		if (bool(instances.data[instance_index].flags & INSTANCE_FLAGS_USE_GI_BUFFERS))
		{
#ifdef USE_MULTIVIEW
			vec4 buffer_ambient = textureLod(sampler2DArray(ambient_buffer, SAMPLER_LINEAR_CLAMP), vec3(buffer_uv, ViewIndex), 0.0);
#else
			vec4 buffer_ambient = textureLod(sampler2D(ambient_buffer, SAMPLER_LINEAR_CLAMP), buffer_uv, 0.0);
#endif // USE_MULTIVIEW
			indirect_diffuse = mix(indirect_diffuse, buffer_ambient.rgb, buffer_ambient.a);

#ifndef SPECULAR_DISABLED
#ifdef USE_MULTIVIEW
			vec4 buffer_reflection = textureLod(sampler2DArray(reflection_buffer, SAMPLER_LINEAR_CLAMP), vec3(buffer_uv, ViewIndex), 0.0);
#else
			vec4 buffer_reflection = textureLod(sampler2D(reflection_buffer, SAMPLER_LINEAR_CLAMP), buffer_uv, 0.0);
#endif // USE_MULTIVIEW
			indirect_specular = mix(indirect_specular, buffer_reflection.rgb, buffer_reflection.a);
#endif // !SPECULAR_DISABLED 
		}
	}

#endif // !USE_LIGHTMAP


	// Reflection Probes //
	{
		vec4 ambient_accum = vec4(0.0);
		vec4 reflection_accum = vec4(0.0);
#ifdef LIGHT_CLEARCOAT_USED
		vec4 cc_reflection_accum = vec4(0.0);
#endif // LIGHT_CLEARCOAT_USED
#ifdef SPECULAR_DISABLED
		reflection_accum.a = 1.0;
#ifdef LIGHT_CLEARCOAT_USED
		cc_reflection_accum.a = 1.0;
#endif // LIGHT_CLEARCOAT_USED
#endif // SPECULAR_DISABLED

		const uint cluster_reflection_offset = cluster_offset + implementation_data.cluster_type_size * 4;

		uint item_min, item_max, item_from, item_to;
		cluster_get_item_range(cluster_reflection_offset + implementation_data.max_cluster_element_count_div_32 + cluster_z, item_min, item_max, item_from, item_to);

		item_from = subgroupBroadcastFirst(subgroupMin(item_from));
		item_to = subgroupBroadcastFirst(subgroupMax(item_to));
		
		for (uint i = item_from; i < item_to; i++)
		{
			uint mask = cluster_buffer.data[cluster_reflection_offset + i];
			mask &= cluster_get_range_clip_mask(i, item_min, item_max);

			uint merged_mask = subgroupBroadcastFirst(subgroupOr(mask));
			while (merged_mask != 0)
			{
				uint bit = findMSB(merged_mask);
				merged_mask &= ~(1u << bit);

				if (((1u << bit) & mask) == 0)
					continue;

				const uint reflection_index = 32 * i + bit;

				if (!bool(reflections.data[reflection_index].mask & instances.data[instance_index].layer_mask))
					continue;  // Not masked, skip.

#ifdef LIGHT_CLEARCOAT_USED
				if (reflection_accum.a >= 1.0 && cc_reflection_accum.a >= 1.0 && ambient_accum.a >= 1.0)
					break;
#else  // LIGHT_CLEARCOAT_USED
				if (reflection_accum.a >= 1.0 && ambient_accum.a >= 1.0)
					break;
#endif // LIGHT_CLEARCOAT_USED

				reflection_process(
						reflection_index, vertex, radiance_vec, normal, roughness,
#ifdef LIGHT_CLEARCOAT_USED
						cc_radiance_vec, clearcoat_roughness, cc_reflection_accum,
#endif // LIGHT_CLEARCOAT_USED
						ambient_accum, reflection_accum
				);
			}
		}

		if (ambient_accum.a < 1.0)
			ambient_accum.rgb += indirect_diffuse * (1.0 - ambient_accum.a);

#ifndef SPECULAR_DISABLED
		if (reflection_accum.a < 1.0)
			reflection_accum.rgb += indirect_specular * (1.0 - reflection_accum.a);

#ifdef LIGHT_CLEARCOAT_USED
		if (cc_reflection_accum.a < 1.0)
			cc_reflection_accum.rgb += cc_indirect_specular * (1.0 - cc_reflection_accum.a);
#endif // LIGHT_CLEARCOAT_USED

		if (reflection_accum.a > 0.0)
			indirect_specular = reflection_accum.rgb;

#ifdef LIGHT_CLEARCOAT_USED
		if (cc_reflection_accum.a > 0.0)
			cc_indirect_specular = cc_reflection_accum.rgb;
#endif // LIGHT_CLEARCOAT_USED
#endif // !SPECULAR_DISABLED

#ifndef USE_LIGHTMAP
		if (ambient_accum.a > 0.0)
			indirect_diffuse = ambient_accum.rgb;
#endif // !USE_LIGHTMAP
	}


	// Finalize Indirect Light //
	{
		// Apply Irradiance Matching (aka. Cubemap Normalization) //
		// Low-spatial-frequency probe irradiance was previously divided out of indirect specular,
		// now multiply in high-spatial-frequency irradiance derived from lightmap data.
#ifdef USE_IRRADIANCE_MATCHING
		indirect_specular *= hi_irradiance * M_PI;
#ifdef LIGHT_CLEARCOAT_USED
		cc_indirect_specular *= cc_hi_irradiance * M_PI;
#endif // LIGHT_CLEARCOAT_USED
#endif // USE_IRRADIANCE_MATCHING


		// Apply Bent-Normal Specular Occlusion //
#if !defined(SPECULAR_DISABLED) && defined(BENT_NORMAL_MAP_USED)
		// Apply cone to cone intersection with cosine weighted assumption:
		// https://blog.selfshadow.com/publications/s2016-shading-course/activision/s2016_pbs_activision_occlusion.pdf
		float cos_a_v = sqrt(1.0 - ao);
		float limited_roughness = max(roughness, 0.01); // Avoid artifacts at really low roughness.
		float cos_a_s = exp2((-log(10.0) / log(2.0)) * limited_roughness * limited_roughness);
		float cos_b = dot(irradiance_vec, reflect(-view, normal));

		// Intersection between the spherical caps of the visibility and specular cone.
		// Based on Christopher Oat and Pedro V. Sander's "Ambient aperture lighting":
		// https://advances.realtimerendering.com/s2006/Chapter8-Ambient_Aperture_Lighting.pdf
		float r1 = acos(cos_a_v);
		float r2 = acos(cos_a_s);
		float d = acos(cos_b);
		float area = 0.0;

		if (d <= max(r1, r2) - min(r1, r2))
		{
			// One cap is enclosed in the other.
			area = M_TAU - M_TAU * max(cos_a_v, cos_a_s);
		}
		else if (d >= r1 + r2)
		{
			// No intersection.
			area = 0.0;
		}
		else
		{
			float delta = abs(r1 - r2);
			float x = 1.0 - clamp((d - delta) / (r1 + r2 - delta), 0.0, 1.0);
			area = smoothstep(0.0, 1.0, x);
			area *= M_TAU - M_TAU * max(cos_a_v, cos_a_s);
		}

		float specular_occlusion = area / (M_TAU * (1.0 - cos_a_s));
		indirect_specular *= specular_occlusion;
#ifdef LIGHT_CLEARCOAT_USED
		cc_indirect_specular *= specular_occlusion;
#endif // LIGHT_CLEARCOAT_USED
#endif  // !SPECULAR_DISABLED && BENT_NORMAL_MAP_USED

		indirect_diffuse *= ao;  // SSAO is applied to indirect diffuse _before_ SSIL.


		// Integrate SSIL //
		if (bool(implementation_data.ss_effects_flags & SCREEN_SPACE_EFFECTS_FLAGS_USE_SSIL))
		{
#ifdef USE_MULTIVIEW
			vec4 ssil = textureLod(sampler2DArray(ssil_buffer, SAMPLER_LINEAR_CLAMP), vec3(buffer_uv, ViewIndex), 0.0);
#else
			vec4 ssil = textureLod(sampler2D(ssil_buffer, SAMPLER_LINEAR_CLAMP), buffer_uv, 0.0);
#endif // USE_MULTIVIEW
			indirect_diffuse *= 1.0 - ssil.a;
			indirect_diffuse += ssil.rgb;
		}


		// Integrate SSR //
#ifndef SPECULAR_DISABLED
		if (bool(implementation_data.ss_effects_flags & SCREEN_SPACE_EFFECTS_FLAGS_USE_SSR))
		{
			const bool resolve_ssr = bool(implementation_data.ss_effects_flags & SCREEN_SPACE_EFFECTS_FLAGS_RESOLVE_SSR);

			float ssr_mip_level = 0.0;
			if (resolve_ssr)
			{
#ifdef USE_MULTIVIEW
				ssr_mip_level = textureLod(sampler2DArray(ssr_mip_level_buffer, SAMPLER_NEAREST_CLAMP), vec3(buffer_uv, ViewIndex), 0.0).x;
#else
				ssr_mip_level = textureLod(sampler2D(ssr_mip_level_buffer, SAMPLER_NEAREST_CLAMP), buffer_uv, 0.0).x;
#endif // USE_MULTIVIEW

				ssr_mip_level *= 14.0;
			}

#ifdef USE_MULTIVIEW
			vec4 ssr = textureLod(sampler2DArray(ssr_buffer, SAMPLER_LINEAR_WITH_MIPMAPS_CLAMP), vec3(buffer_uv, ViewIndex), ssr_mip_level);
#else
			vec4 ssr = textureLod(sampler2D(ssr_buffer, SAMPLER_LINEAR_WITH_MIPMAPS_CLAMP), buffer_uv, ssr_mip_level);
#endif // USE_MULTIVIEW

			if (resolve_ssr)
			{
				const vec3 rec709_luminance_weights = vec3(0.2126, 0.7152, 0.0722);
				ssr.rgb /= 1.0 - dot(ssr.rgb, rec709_luminance_weights);
			}

			// Apply fade when approaching 0.7 roughness to smooth-out the harsh cutoff in the main SSR trace pass.
			ssr *= smoothstep(0.0, 1.0, 1.0 - clamp((roughness - 0.6) / (0.7 - 0.6), 0.0, 1.0));

			// Alpha is premultiplied.
			indirect_specular = indirect_specular * (1.0 - ssr.a) + ssr.rgb;
		}
#endif // !SPECULAR_DISABLED
	}
#endif // !AMBIENT_LIGHT_DISABLED


#ifdef SPECULAR_DISABLED
	float f90 = 0.0;
	vec3 f0 = vec3(0.0);
#else  // SPECULAR_DISABLED

	// Calculate f0 and f90 from specular factor, albedo, and metalness.
	// From Filament: https://google.github.io/filament/Filament.html#lighting/occlusion/specularocclusion
	//                https://github.com/google/filament/blob/e8669b688a9381beb4f7470df828e1932d78efa6/shaders/src/surface_shading_lit.fs#L50
	float dielectric_f0 = get_dielectric_f0(specular);
	float f90 = mix(clamp(dielectric_f0 * 50.0, 0.0, 1.0), 1.0, metallic);
	vec3 f0 = mix(vec3(dielectric_f0), albedo, metallic);
	albedo *= (1.0 - metallic);

#ifdef LIGHT_CLEARCOAT_USED
	// The base layer's Fresnel is computed assuming an interface with air, which has an IOR near 1.0.
	// However, with clearcoat enabled the interface should be against the clearcoat layer, which has an IOR of 1.5.
	// This can be accounted for by recomputing the base layer's f0, first converting it to IOR with an interface of 1.0,
	// then converting the resulting IOR back to f0 with an interface of 1.5.
	f0 = mix(f0, f0_clearcoat_adjust(f0), clearcoat);
#endif // LIGHT_CLEARCOAT_USED


	// Get Indirect BRDF //
#ifndef SPECULAR_TOON
	// Indirect Fresnel and Visibility terms.
	float NdotV = clamp(dot(normal, view), MIN_NDOTV, 1.0);
	vec2 DFG = prefiltered_dfg(roughness, NdotV);

	// Multi-scattering term (affects both direct and indirect specular).
	energy_compensation = get_energy_compensation(f0, DFG.y);

#if !defined(AMBIENT_LIGHT_DISABLED) || defined(USE_VERTEX_LIGHTING)
	// Horizon-occlusion term.
	float horizon = min(1.0 + dot(radiance_vec, geo_normal), 1.0);
	horizon *= horizon;

	vec3 indirect_brdf = energy_compensation * ((f90 - f0) * DFG.x + f0 * DFG.y) * horizon * ao;
#endif // AMBIENT_LIGHT_DISABLED
#endif // SPECULAR_TOON


	// Apply Indirect BRDF //
#ifndef AMBIENT_LIGHT_DISABLED
	{
#ifdef SPECULAR_TOON
		// Simplify BRDF for toon shading.
		indirect_specular *= specular * metallic * albedo * 2.0;
#else  // SPECULAR_TOON
		indirect_specular *= indirect_brdf;
#ifdef LIGHT_CLEARCOAT_USED
		float cc_NdotV = dot(geo_normal, view);  // Clearcoat layer uses geometric normal.
		float cc_cNdotV = clamp(cc_NdotV, MIN_NDOTV, 1.0);  
		float cc_NdotV5 = SchlickFresnel(cc_cNdotV);
		float cc_F = mix(0.04, 1.0, cc_NdotV5) * clearcoat;  // Clearcoat layer has an IOR of 1.5 (4% reflectance).
		float cc_attenuation = 1.0 - cc_F;

		// Attenuate underlying diffuse/specular by clearcoat Fresnel.
		indirect_diffuse *= cc_attenuation;
		indirect_specular *= cc_attenuation;

		// Clearcoat layer can just use Fresnel rather than the full BRDF.
		indirect_specular += cc_indirect_specular * cc_F * ao;
#endif // LIGHT_CLEARCOAT_USED
#endif // SPECULAR_TOON
	}
#endif // !AMBIENT_LIGHT_DISABLED

#endif // SPECULAR_DISABLED


	/////////////////////////
	////  Direct Light  ////

	vec3 diffuse_light = indirect_diffuse;
	vec3 specular_light = indirect_specular;  // Always defined, but never output when SPECULAR_DISABLED is defined, in which case anything modifying it is compiled out.

	// Get Per-Vertex Lighting //
#ifdef USE_VERTEX_LIGHTING
#if (USE_VERTEX_LIGHTING == 0)

	// Per-vertex lighting brightness is interpolated non-linearly, so multiply the interpolated values by their brightness to linearize.
	diffuse_light += diffuse_light_interp.rgb * dot(diffuse_light_interp.rgb, vec3(1.0/3.0));
#ifndef SPECULAR_DISABLED
	specular_light += specular_light_interp.rgb * dot(specular_light_interp.rgb, vec3(1.0/3.0)) * indirect_brdf;
#endif // !SPECULAR_DISABLED

#else  // USE_VERTEX_LIGHTING == 1

	// Per-vertex SH brightness is interpolated non-linearly, so multiply evaluated SH by its brightness to linearize.
	// This has the added benefit of smoothing-out the SH terminator.
#if defined(DIFFUSE_LAMBERT_WRAP)
	vec3 diffuse_sh = sh_l1_evaluate(sh_r_interp, sh_g_interp, sh_b_interp, normal * (1.0 - roughness * 0.75)) * sqrt(1.0 + roughness * 0.75);  // Coarse fit but pretty close.
#elif defined(DIFFUSE_TOON)
	vec3 diffuse_sh = sh_l1_evaluate(sh_r_interp, sh_g_interp, sh_b_interp, normal * (1.0 - roughness * 0.5)) * (1.0 + roughness * 0.5) * sqrt(1.0 + roughness * 0.5);  // VERY coarse fit but at least matches at low roughness.
#else  // DIFFUSE_LAMBERT
	vec3 diffuse_sh = sh_l1_evaluate(sh_r_interp, sh_g_interp, sh_b_interp, normal);
#endif // DIFFUSE_MODE
	diffuse_light += diffuse_sh * dot(diffuse_sh, vec3(1.0/3.0)) * ((1.0 / M_PI) * inversesqrt(M_PI));

#ifndef SPECULAR_DISABLED
#if 0
	// Direct specular from dominant SH direction.
	// Doesn't handle overlapping lights well.
	vec3 sh_vec = (sh_r_interp.wyz + sh_g_interp.wyz + sh_b_interp.wyz) / (sh_r_interp.x + sh_g_interp.x + sh_b_interp.x + 0.000001);
	float sh_len = dot(sh_vec, sh_vec) + 0.000001;
	float sh_len_rcp = inversesqrt(sh_len);
	sh_vec *= sh_len_rcp;
	sh_len *= sh_len_rcp * inversesqrt(3.0);  // 0-1 range

	float sh_fade = clamp(sh_len * 4.0 - 3.0, 0.0, 1.0);
	sh_fade *= sh_fade;
	sh_fade = 1.0 - sh_fade * sh_fade;
	sh_fade = 1.0 - sh_fade * sh_fade;

	//float roughness_sqr = mix(1.0, roughness * roughness, sh_len);
	float roughness_sqr = roughness * roughness;

	vec3 sh_H = normalize(sh_vec + view);
	float sh_NdotL = clamp(dot(normal, sh_vec), 0.0, 1.0);
	float sh_NdotH = clamp(dot(normal, sh_H), MIN_NDOTH, 1.0);
	float sh_LdotH5 = SchlickFresnel(clamp(dot(sh_vec, sh_H), 0.0, 1.0));
	float sh_D = D_GGX(sh_NdotH, roughness_sqr);
	float sh_V = V_GGX(sh_NdotL, NdotV, roughness_sqr);
	vec3 specular_sh = sh_l1_evaluate_rad(sh_r_interp, sh_g_interp, sh_b_interp, sh_vec);
	specular_sh *= dot(specular_sh, vec3(1.0/3.0)) * (sh_spec_scale_interp * sh_spec_scale_interp);
	specular_light += specular_sh * (sh_D * sh_V * sh_NdotL * ((1.0 / M_PI) * sqrt(M_PI)) * sh_fade) * (energy_compensation * (f0 + (f90 - f0) * sh_LdotH5));
#else
	// SH radiance as specular.
	float roughness_sqr = roughness * roughness;
	vec3 specular_sh = sh_l1_evaluate_spec(sh_r_interp, sh_g_interp, sh_b_interp, radiance_vec, roughness_sqr);
	specular_sh *= dot(specular_sh, vec3(1.0/3.0)) * (sh_spec_scale_interp * sh_spec_scale_interp);
	specular_light += specular_sh * ((1.0 / M_PI) * inversesqrt(M_PI)) * indirect_brdf;
#endif
#endif // !SPECULAR_DISABLED

#endif // USE_VERTEX_LIGHTING == 0/1
#endif // USE_VERTEX_LIGHTING


	// Remap minimum roughness before analytical specularity is calculated.
	// This limits the severity of specular aliasing and ensures that highlights are never imperceptibly small,
	// without affecting the sharpness of indirect reflections and the like.
	roughness = sqrt(roughness * roughness * (1.0 - MIN_ROUGHNESS_SQR) + MIN_ROUGHNESS_SQR);
#ifdef LIGHT_CLEARCOAT_USED
	clearcoat_roughness = clearcoat_roughness * clearcoat_roughness * (CLEARCOAT_ROUGHNESS_SQR - MIN_ROUGHNESS_SQR) + MIN_ROUGHNESS_SQR;  // Pre-squared.
#endif // LIGHT_CLEARCOAT_USED


	// Directional Lights //
	{
		// Shadows and lighting are done in two passes to reduce register pressure.
#ifndef SHADOWS_DISABLED
		uint shadow0 = 0, shadow1 = 0;
		float shadowmask = 1.0;
#ifdef USE_LIGHTMAP
		uint shadowmask_mode = LIGHTMAP_SHADOWMASK_MODE_NONE;
		if (bool(instances.data[instance_index].flags & INSTANCE_FLAGS_USE_LIGHTMAP))
		{
			const uint idx = instances.data[instance_index].gi_offset & 0xFFFF;
			shadowmask_mode = lightmaps.data[idx].flags;

			if (shadowmask_mode != LIGHTMAP_SHADOWMASK_MODE_NONE)
			{
				const uint slice = instances.data[instance_index].gi_offset >> 16;
				const vec2 scaled_uv = uv2 * instances.data[instance_index].lightmap_uv_scale.zw + instances.data[instance_index].lightmap_uv_scale.xy;
				const vec3 uvw = vec3(scaled_uv, float(slice));

				if (sc_use_lightmap_bicubic_filter())
					shadowmask = textureArray_bicubic(lightmap_textures[MAX_LIGHTMAP_TEXTURES + idx], uvw, lightmaps.data[idx].light_texture_size).x;
				else
					shadowmask = textureLod(sampler2DArray(lightmap_textures[MAX_LIGHTMAP_TEXTURES + idx], SAMPLER_LINEAR_CLAMP), uvw, 0.0).x;
			}
		}

		if (shadowmask_mode != LIGHTMAP_SHADOWMASK_MODE_ONLY)
		{
#endif // USE_LIGHTMAP

#ifndef USE_VERTEX_LIGHTING
			// Directional Light Shadows //
			for (uint i = 0; i < scene_data.directional_light_count; i++)
			{
				DirectionalLightData light_data = directional_lights.data[i];

				if (!bool(light_data.mask & instances.data[instance_index].layer_mask))
					continue;  // Not masked, skip.

				if (light_data.bake_mode == LIGHT_BAKE_STATIC && bool(instances.data[instance_index].flags & INSTANCE_FLAGS_USE_LIGHTMAP))
					continue;  // Statically baked light and object uses lightmap, skip.

				float shadow = 1.0;
				if (light_data.shadow_opacity > 0.001 && (-vertex.z < light_data.shadow_split_offsets[3]))
				{
					float depth_z = -vertex.z;
					vec3 light_dir = light_data.direction;
					vec3 base_normal_bias = geo_normal * (1.0 - max(0.0, dot(light_dir, -geo_normal)));

#define BIAS_FUNC(m_var, m_idx) \
	m_var.xyz += light_dir * light_data.shadow_bias[m_idx]; \
	vec3 normal_bias = base_normal_bias * light_data.shadow_normal_bias[m_idx]; \
	normal_bias -= light_dir * dot(light_dir, normal_bias); \
	m_var.xyz += normal_bias;

					if (sc_use_directional_soft_shadows() && light_data.softshadow_angle > 0.001)
					{
						// Contact-hardening PCSS //
						const uint split_idx = uint(dot(vec3(greaterThan(vec3(depth_z), light_data.shadow_split_offsets.xyz)), vec3(1.0)));

						vec4 v = vec4(vertex, 1.0);
						BIAS_FUNC(v, split_idx)
						vec4 pssm_coord = (light_data.shadow_matrix[split_idx] * v);
						pssm_coord.xyz *= 1.0 / pssm_coord.w;

						float test_radius = (dot(light_data.direction, v.xyz) - light_data.shadow_range_begin[split_idx]) * light_data.softshadow_angle;
						vec2 tex_scale = light_data.uv_scale[split_idx].xy * test_radius;

						shadow = sample_directional_soft_shadow(directional_shadow_atlas, pssm_coord.xyz, tex_scale * light_data.soft_shadow_scale, scene_data.taa_frame_count);

						uint max_blend_split = light_data.shadow_split_offsets[3] > 0.0 ? 2 : 0;  // Final cascade does not blend.
						if (light_data.blend_splits && depth_z < light_data.shadow_split_offsets[max_blend_split])
						{
							vec4 v = vec4(vertex, 1.0);
							BIAS_FUNC(v, (split_idx+1))
							pssm_coord = (light_data.shadow_matrix[split_idx+1] * v);
							pssm_coord.xyz *= 1.0 / pssm_coord.w;

							test_radius = (dot(light_data.direction, v.xyz) - light_data.shadow_range_begin[split_idx+1]) * light_data.softshadow_angle;
							tex_scale = light_data.uv_scale[split_idx+1].xy * test_radius;

							float shadow2 = sample_directional_soft_shadow(directional_shadow_atlas, pssm_coord.xyz, tex_scale * light_data.soft_shadow_scale, scene_data.taa_frame_count);
							
							float pssm_blend = smoothstep(light_data.shadow_split_offsets[split_idx] * 0.9, light_data.shadow_split_offsets[split_idx], depth_z);  // Blend over last 10% of lower cascade.
							shadow = mix(shadow, shadow2, pssm_blend);
						}
					}
					else
					{ 
						// Standard PCF Shadows //
						const uint split_idx = uint(dot(vec3(greaterThan(vec3(depth_z), light_data.shadow_split_offsets.xyz)), vec3(1.0)));

						vec4 v = vec4(vertex, 1.0);
						BIAS_FUNC(v, split_idx)
						vec4 pssm_coord = (light_data.shadow_matrix[split_idx] * v);
						pssm_coord.xyz *= 1.0 / pssm_coord.w;
						
						float blur_factor = light_data.shadow_split_offsets[0] / light_data.shadow_split_offsets[split_idx];  // Adjust shadow blur with reference to the first split to reduce discrepancy between shadow splits.
						shadow = sample_directional_pcf_shadow(directional_shadow_atlas, scene_data.directional_shadow_pixel_size * light_data.soft_shadow_scale * blur_factor, pssm_coord, scene_data.taa_frame_count);

						uint max_blend_split = light_data.shadow_split_offsets[3] > 0.0 ? 2 : 0;  // Final cascade does not blend.
						if (light_data.blend_splits && depth_z < light_data.shadow_split_offsets[max_blend_split])
						{
							vec4 v = vec4(vertex, 1.0);
							BIAS_FUNC(v, (split_idx+1))
							pssm_coord = (light_data.shadow_matrix[split_idx+1] * v);
							pssm_coord.xyz *= 1.0 / pssm_coord.w;

							blur_factor = light_data.shadow_split_offsets[0] / light_data.shadow_split_offsets[split_idx+1];
							float shadow2 = sample_directional_pcf_shadow(directional_shadow_atlas, scene_data.directional_shadow_pixel_size * light_data.soft_shadow_scale * blur_factor, pssm_coord, scene_data.taa_frame_count);
							
							float pssm_blend = smoothstep(light_data.shadow_split_offsets[split_idx] * 0.9, light_data.shadow_split_offsets[split_idx], depth_z);  // Blend over last 10% of lower cascade.
							shadow = mix(shadow, shadow2, pssm_blend);
						}
					}

#ifdef USE_LIGHTMAP
					if (shadowmask_mode == LIGHTMAP_SHADOWMASK_MODE_REPLACE)
						shadow = mix(shadow, shadowmask, smoothstep(light_data.fade_from, light_data.fade_to, vertex.z));
					else if (shadowmask_mode == LIGHTMAP_SHADOWMASK_MODE_OVERLAY)
						shadow = shadowmask * mix(shadow, 1.0, smoothstep(light_data.fade_from, light_data.fade_to, vertex.z));
					else
					{
#endif // USE_LIGHTMAP
						shadow = mix(shadow, 1.0, smoothstep(light_data.fade_from, light_data.fade_to, vertex.z));
#ifdef USE_LIGHTMAP
					}
#endif // USE_LIGHTMAP

#undef BIAS_FUNC
				}

				if (i < 4)
					shadow0 |= uint(clamp(shadow * 255.0, 0.0, 255.0)) << (i * 8);
				else
					shadow1 |= uint(clamp(shadow * 255.0, 0.0, 255.0)) << ((i - 4) * 8);
			}
#endif // !USE_VERTEX_LIGHTING

#ifdef USE_LIGHTMAP
		}
		else  // shadowmask_mode == LIGHTMAP_SHADOWMASK_MODE_ONLY
		{ 
			shadow0 |= uint(clamp(shadowmask * 255.0, 0.0, 255.0));
		}
#endif // USE_LIGHTMAP

#endif // !SHADOWS_DISABLED

#ifndef USE_VERTEX_LIGHTING
		// Directional Light Shading //
		for (uint i = 0; i < scene_data.directional_light_count; i++)
		{
			DirectionalLightData light_data = directional_lights.data[i];
			
			if (!bool(light_data.mask & instances.data[instance_index].layer_mask))
				continue;  // Not masked, skip.

			if (light_data.bake_mode == LIGHT_BAKE_STATIC && bool(instances.data[instance_index].flags & INSTANCE_FLAGS_USE_LIGHTMAP))
				continue;  // Statically baked light and object uses lightmap, skip.

#ifdef LIGHT_TRANSMITTANCE_USED
			float transmittance_z = transmittance_depth;
#ifndef SHADOWS_DISABLED
			if (light_data.shadow_opacity > 0.001 && (-vertex.z < light_data.shadow_split_offsets[3]))
			{
				// Get transmittance depth from shadow map.
				const uint split_idx = uint(dot(vec3(greaterThan(-vertex.zzz, light_data.shadow_split_offsets.xyz)), vec3(1.0)));

				vec4 trans_vertex = vec4(vertex - geo_normal * light_data.shadow_transmittance_bias[split_idx], 1.0);
				vec4 trans_coord = light_data.shadow_matrix[split_idx] * trans_vertex;
				trans_coord.xyz *= 1.0 / trans_coord.w;

				float shadow_z = textureLod(sampler2D(directional_shadow_atlas, SAMPLER_LINEAR_CLAMP), trans_coord.xy, 0.0).r;
				transmittance_z = (trans_coord.z - shadow_z) * light_data.shadow_z_range[split_idx];
			}
#endif // !SHADOWS_DISABLED
#endif // LIGHT_TRANSMITTANCE_USED

			float shadow = 1.0;
#ifndef SHADOWS_DISABLED
			// Unpack bit-packed shadow.
			if (i < 4)
				shadow = float(shadow0 >> (i * 8u) & 0xFFu) / 255.0;
			else
				shadow = float(shadow1 >> ((i - 4u) * 8u) & 0xFFu) / 255.0;
			shadow = mix(1.0, shadow, light_data.shadow_opacity);
#endif // !SHADOWS_DISABLED

			blur_shadow(shadow);

#ifdef DEBUG_DRAW_PSSM_SPLITS
			vec3 tint = vec3(1.0, 1.0, 0.0);
			if (-vertex.z < light_data.shadow_split_offsets.x)
				tint = vec3(1.0, 0.0, 0.0);
			else if (-vertex.z < light_data.shadow_split_offsets.y)
				tint = vec3(0.0, 1.0, 0.0);
			else if (-vertex.z < light_data.shadow_split_offsets.z)
				tint = vec3(0.0, 0.0, 1.0);
			tint = mix(tint, vec3(1.0), shadow);
			shadow = 1.0;
#endif // DEBUG_DRAW_PSSM_SPLITS

			light_compute(
					normal, light_data.direction, view, light_data.size,
#ifndef DEBUG_DRAW_PSSM_SPLITS
					light_data.color * light_data.energy,
#else
					light_data.color * light_data.energy * tint,
#endif // !DEBUG_DRAW_PSSM_SPLITS
					true, shadow, f0, f90, roughness, light_data.specular,
#if defined(LIGHT_CODE_USED) || defined(LIGHT_RIM_USED)
					albedo,
#endif // LIGHT_CODE_USED || LIGHT_RIM_USED
#ifdef LIGHT_CODE_USED
					metallic,
#endif // LIGHT_CODE_USED
					alpha, screen_uv, energy_compensation, direct_ao,
#ifdef LIGHT_BACKLIGHT_USED
					backlight,
#endif // LIGHT_BACKLIGHT_USED
#ifdef LIGHT_TRANSMITTANCE_USED
					transmittance_color, transmittance_depth,
					transmittance_boost, transmittance_z,
#endif // LIGHT_TRANSMITTANCE_USED
#ifdef LIGHT_RIM_USED
					rim, rim_tint,
#endif // LIGHT_RIM_USED
#ifdef LIGHT_CLEARCOAT_USED
					clearcoat, clearcoat_roughness, geo_normal,
#endif // LIGHT_CLEARCOAT_USED
#ifdef LIGHT_ANISOTROPY_USED
					aniso_tangent, aniso_bitangent, anisotropy,
#endif // LIGHT_ANISOTROPY_USED
					diffuse_light, specular_light
			);
		}
#endif // !USE_VERTEX_LIGHTING
	}


#ifndef USE_VERTEX_LIGHTING

	// Omni Lights //
	{
		const uint cluster_omni_offset = cluster_offset;

		uint item_min, item_max, item_from, item_to;
		cluster_get_item_range(cluster_omni_offset + implementation_data.max_cluster_element_count_div_32 + cluster_z, item_min, item_max, item_from, item_to);

		item_from = subgroupBroadcastFirst(subgroupMin(item_from));
		item_to = subgroupBroadcastFirst(subgroupMax(item_to));

		for (uint i = item_from; i < item_to; i++)
		{
			uint mask = cluster_buffer.data[cluster_omni_offset + i];
			mask &= cluster_get_range_clip_mask(i, item_min, item_max);

			uint merged_mask = subgroupBroadcastFirst(subgroupOr(mask));
			while (merged_mask != 0)
			{
				uint bit = findMSB(merged_mask);
				merged_mask &= ~(1u << bit);

				if (((1u << bit) & mask) == 0)
					continue;

				const uint light_index = 32 * i + bit;

				if (!bool(omni_lights.data[light_index].mask & instances.data[instance_index].layer_mask))
					continue;  // Not masked, skip.

				if (omni_lights.data[light_index].bake_mode == LIGHT_BAKE_STATIC && bool(instances.data[instance_index].flags & INSTANCE_FLAGS_USE_LIGHTMAP))
					continue;  // Statically baked light and object uses lightmap, skip.

				light_process_omni(
						light_index, vertex, view, normal, vertex_ddx, vertex_ddy,
						f0, f90, roughness, scene_data.taa_frame_count,
#if defined(LIGHT_CODE_USED) || defined(LIGHT_RIM_USED)
						albedo,
#endif // LIGHT_CODE_USED || LIGHT_RIM_USED
#ifdef LIGHT_CODE_USED
						metallic,
#endif // LIGHT_CODE_USED
						alpha, screen_uv, energy_compensation, direct_ao,
#ifdef LIGHT_BACKLIGHT_USED
						backlight,
#endif // LIGHT_BACKLIGHT_USED
#ifdef LIGHT_TRANSMITTANCE_USED
						transmittance_color, transmittance_depth, transmittance_boost,
#endif // LIGHT_TRANSMITTANCE_USED
#ifdef LIGHT_RIM_USED
						rim, rim_tint,
#endif // LIGHT_RIM_USED
#ifdef LIGHT_CLEARCOAT_USED
						clearcoat, clearcoat_roughness, geo_normal,
#endif // LIGHT_CLEARCOAT_USED
#ifdef LIGHT_ANISOTROPY_USED
						aniso_tangent, aniso_bitangent, anisotropy,
#endif // LIGHT_ANISOTROPY_USED
						diffuse_light, specular_light
				);
			}
		}
	}

	// Spot Lights //
	{
		const uint cluster_spot_offset = cluster_offset + implementation_data.cluster_type_size;

		uint item_min, item_max, item_from, item_to;
		cluster_get_item_range(cluster_spot_offset + implementation_data.max_cluster_element_count_div_32 + cluster_z, item_min, item_max, item_from, item_to);

		item_from = subgroupBroadcastFirst(subgroupMin(item_from));
		item_to = subgroupBroadcastFirst(subgroupMax(item_to));

		for (uint i = item_from; i < item_to; i++)
		{
			uint mask = cluster_buffer.data[cluster_spot_offset + i];
			mask &= cluster_get_range_clip_mask(i, item_min, item_max);

			uint merged_mask = subgroupBroadcastFirst(subgroupOr(mask));
			while (merged_mask != 0)
			{
				uint bit = findMSB(merged_mask);
				merged_mask &= ~(1u << bit);

				if (((1u << bit) & mask) == 0)
					continue;

				const uint light_index = 32 * i + bit;

				if (!bool(spot_lights.data[light_index].mask & instances.data[instance_index].layer_mask))
					continue;  // Not masked.

				if (spot_lights.data[light_index].bake_mode == LIGHT_BAKE_STATIC && bool(instances.data[instance_index].flags & INSTANCE_FLAGS_USE_LIGHTMAP))
					continue;  // Statically baked light and object uses lightmap, skip.

				light_process_spot(
						light_index, vertex, view, normal, vertex_ddx, vertex_ddy,
						f0, f90, roughness, scene_data.taa_frame_count,
#if defined(LIGHT_CODE_USED) || defined(LIGHT_RIM_USED)
						albedo,
#endif // LIGHT_CODE_USED || LIGHT_RIM_USED
#ifdef LIGHT_CODE_USED
						metallic,
#endif // LIGHT_CODE_USED
						alpha, screen_uv, energy_compensation, direct_ao,
#ifdef LIGHT_BACKLIGHT_USED
						backlight,
#endif // LIGHT_BACKLIGHT_USED
#ifdef LIGHT_TRANSMITTANCE_USED
						transmittance_color, transmittance_depth, transmittance_boost,
#endif // LIGHT_TRANSMITTANCE_USED
#ifdef LIGHT_RIM_USED
						rim, rim_tint,
#endif // LIGHT_RIM_USED
#ifdef LIGHT_CLEARCOAT_USED
						clearcoat, clearcoat_roughness, geo_normal,
#endif // LIGHT_CLEARCOAT_USED
#ifdef LIGHT_ANISOTROPY_USED
						aniso_tangent, aniso_bitangent, anisotropy,
#endif // LIGHT_ANISOTROPY_USED
						diffuse_light, specular_light
				);
			}
		}
	}

	// Area Lights //
	if (sc_cluster_has_area_light())
	{
		const uint cluster_area_offset = cluster_offset + implementation_data.cluster_type_size * 2;

		uint item_min, item_max, item_from, item_to;
		cluster_get_item_range(cluster_area_offset + implementation_data.max_cluster_element_count_div_32 + cluster_z, item_min, item_max, item_from, item_to);

		item_from = subgroupBroadcastFirst(subgroupMin(item_from));
		item_to = subgroupBroadcastFirst(subgroupMax(item_to));

		for (uint i = item_from; i < item_to; i++)
		{
			uint mask = cluster_buffer.data[cluster_area_offset + i];
			mask &= cluster_get_range_clip_mask(i, item_min, item_max);

			uint merged_mask = subgroupBroadcastFirst(subgroupOr(mask));
			while (merged_mask != 0)
			{
				uint bit = findMSB(merged_mask);
				merged_mask &= ~(1u << bit);

				if (((1u << bit) & mask) == 0)
					continue;

				const uint light_index = 32 * i + bit;

				if (!bool(area_lights.data[light_index].mask & instances.data[instance_index].layer_mask))
					continue;  // Not masked, skip.

				if (area_lights.data[light_index].bake_mode == LIGHT_BAKE_STATIC && bool(instances.data[instance_index].flags & INSTANCE_FLAGS_USE_LIGHTMAP))
					continue;  // Statically baked light and object uses lightmap, skip.

				light_process_area(
						light_index, vertex, view, normal, vertex_ddx, vertex_ddy,
						f0, f90, roughness, scene_data.taa_frame_count,
#if (defined(LIGHT_CODE_USED) && defined(AREA_LIGHT_CODE_USED)) || defined(LIGHT_RIM_USED)
						albedo,
#endif // (LIGHT_CODE_USED && AREA_LIGHT_CODE_USED) || LIGHT_RIM_USED
#if defined(LIGHT_CODE_USED) && defined(AREA_LIGHT_CODE_USED)
						metallic,
#endif // LIGHT_CODE_USED && AREA_LIGHT_CODE_USED
						alpha, screen_uv, energy_compensation, direct_ao,
#ifdef LIGHT_BACKLIGHT_USED
						backlight,
#endif // LIGHT_BACKLIGHT_USED
#ifdef LIGHT_TRANSMITTANCE_USED
						transmittance_color, transmittance_depth, transmittance_boost,
#endif // LIGHT_TRANSMITTANCE_USED
#ifdef LIGHT_RIM_USED
						rim, rim_tint,
#endif // LIGHT_RIM_USED
#ifdef LIGHT_CLEARCOAT_USED
						clearcoat, clearcoat_roughness, geo_normal,
#endif // LIGHT_CLEARCOAT_USED
#ifdef LIGHT_ANISOTROPY_USED
						aniso_tangent, aniso_bitangent, anisotropy,
#endif // LIGHT_ANISOTROPY_USED
						diffuse_light, specular_light
				);
			}
		}
	}
#endif // !USE_VERTEX_LIGHTING

#endif // !MODE_RENDER_PREPASS && !MODE_UNSHADED


	// Finalize emission.
	emission *= scene_data.emissive_exposure_normalization;


#if !defined(MODE_RENDER_PREPASS) && defined(USE_SHADOW_TO_OPACITY)
	alpha = min(alpha, clamp(length(indirect_diffuse), 0.0, 1.0));

#ifdef ALPHA_SCISSOR_USED
#ifdef MODE_RENDER_MATERIAL
	if (alpha < alpha_scissor_threshold)
		alpha = 0.0;
	else
		alpha = 1.0;
#else  // MODE_RENDER_MATERIAL
	if (alpha < alpha_scissor_threshold)
		discard;
#endif // MODE_RENDER_MATERIAL
#endif // ALPHA_SCISSOR_USED

#endif // !MODE_RENDER_PREPASS && USE_SHADOW_TO_OPACITY


#ifdef MODE_RENDER_PREPASS

#ifdef MODE_RENDER_SDF
	// Process SDFGI //
	{
		const vec3 local_pos = (implementation_data.sdf_to_bounds * vec4(vertex, 1.0)).xyz;
		const ivec3 grid_pos = implementation_data.sdf_offset + ivec3(local_pos * vec3(implementation_data.sdf_size));

		uint albedo16 = 0x1u; // Solid flag.
		albedo16 |= clamp(uint(albedo.r * 31.0), 0u, 31u) << 11;
		albedo16 |= clamp(uint(albedo.g * 31.0), 0u, 31u) << 6;
		albedo16 |= clamp(uint(albedo.b * 31.0), 0u, 31u) << 1;

		imageStore(albedo_volume_grid, grid_pos, uvec4(albedo16));

		uint facing_bits = 0;
		const vec3 aniso_dir[6] = vec3[](
				vec3( 1, 0, 0),
				vec3( 0, 1, 0),
				vec3( 0, 0, 1),
				vec3(-1, 0, 0),
				vec3( 0,-1, 0),
				vec3( 0, 0,-1));
		vec3 cam_normal = mat3(inv_view_matrix) * normalize(normal_interp);

		float closest_dist = -1e20;
		for (int i = 0; i < 6; i++)
		{
			float d = dot(cam_normal, aniso_dir[i]);
			if (d > closest_dist)
			{
				closest_dist = d;
				facing_bits = (1 << i);
			}
		}

		// Store facing bits.
#ifdef NO_IMAGE_ATOMICS
		imageStore(geom_facing_grid, grid_pos, uvec4(imageLoad(geom_facing_grid, grid_pos).r | facing_bits));
#else
		imageAtomicOr(geom_facing_grid, grid_pos, facing_bits);
#endif // NO_IMAGE_ATOMICS

		if (dot(emission, emission) > 0.000001)
		{
			float lumas[6];
			vec3 light_total = vec3(0.0);

			for (int i = 0; i < 6; i++)
			{
				float strength = max(0.0, dot(cam_normal, aniso_dir[i]));
				vec3 light = emission * strength;
				light_total += light;
				lumas[i] = max(light.r, max(light.g, light.b));
			}

			float luma_total_rcp = 1.0 / max(light_total.r, max(light_total.g, light_total.b));

			uint light_aniso = 0;
			for (int i = 0; i < 6; i++)
			{
				light_aniso |= min(31, uint((lumas[i] * luma_total_rcp) * 31.0)) << (i * 5);
			}

			// Compress to RGBE9995 to save space.
			const float pow2to9 = 512.0;
			const float B = 15.0;
			const float N = 9.0;

			float cRed = clamp(light_total.r, 0.0, 65408.0);
			float cGreen = clamp(light_total.g, 0.0, 65408.0);
			float cBlue = clamp(light_total.b, 0.0, 65408.0);
			float cMax = max(cRed, max(cGreen, cBlue));

			float expp = max(-B - 1.0, floor(log2(cMax))) + 1.0 + B;
			float sMax = floor((cMax * exp2(-(expp - B - N))) + 0.5);

			float exps = expp + 1.0;
			if (0.0 <= sMax && sMax < pow2to9)
				exps = expp;

			float ns = exp2(-(exps - B - N));
			float sRed = floor((cRed * ns) + 0.5f);
			float sGreen = floor((cGreen * ns) + 0.5f);
			float sBlue = floor((cBlue * ns) + 0.5f);
			
			// Store as 8985 to have 2 extra neighbor bits.
			uint light_rgbe = ((uint(sRed) & 0x1FFu) >> 1) | ((uint(sGreen) & 0x1FFu) << 8) | (((uint(sBlue) & 0x1FFu) >> 1) << 17) | ((uint(exps) & 0x1Fu) << 25);
			imageStore(emission_grid, grid_pos, uvec4(light_rgbe));
			imageStore(emission_aniso_grid, grid_pos, uvec4(light_aniso));
		}
	}
#endif // MODE_RENDER_SDF


#ifdef MODE_RENDER_MATERIAL
	albedo_output_buffer.rgb = albedo;
	albedo_output_buffer.a = alpha;

	normal_output_buffer.rgb = encode24(normal) * 0.5 + 0.5;
	normal_output_buffer.a = 0.0;
	depth_output_buffer.r = -vertex.z;

	orm_output_buffer.r = ao;
	orm_output_buffer.g = roughness;
	orm_output_buffer.b = metallic;
	orm_output_buffer.a = sss_strength;

	emission_output_buffer.rgb = emission;
	emission_output_buffer.a = 0.0;
#endif // MODE_RENDER_MATERIAL


#ifdef MODE_RENDER_NORMAL_ROUGHNESS
	normal_roughness_output_buffer = vec4(encode24(normal) * 0.5 + 0.5, roughness);

	// We encode the dynamic/static flag into roughness.
	// Values over 0.5 are dynamic, under 0.5 are static.
	normal_roughness_output_buffer.w = normal_roughness_output_buffer.w * (127.0 / 255.0);
	if (bool(instances.data[instance_index].flags & INSTANCE_FLAGS_DYNAMIC))
		normal_roughness_output_buffer.w = 1.0 - normal_roughness_output_buffer.w;

#ifdef MODE_RENDER_VOXEL_GI
	if (bool(instances.data[instance_index].flags & INSTANCE_FLAGS_USE_VOXEL_GI))
	{
		// Process VoxelGI instances.
		uint index1 = instances.data[instance_index].gi_offset & 0xFFFF;
		uint index2 = instances.data[instance_index].gi_offset >> 16;
		voxel_gi_buffer.x = index1 & 0xFFu;
		voxel_gi_buffer.y = index2 & 0xFFu;
	}
	else
	{
		voxel_gi_buffer.x = 0xFF;
		voxel_gi_buffer.y = 0xFF;
	}
#endif // MODE_RENDER_VOXEL_GI
#endif // MODE_RENDER_NORMAL_ROUGHNESS


#else  // MODE_RENDER_PREPASS


#ifndef MODE_UNSHADED
	// Finalize diffuse contribution.
	diffuse_light *= albedo;
#endif // !MODE_UNSHADED


#ifndef FOG_DISABLED
	fog = vec4(unpackHalf2x16(fog_rg), unpackHalf2x16(fog_ba));
#endif // !FOG_DISABLED


#ifdef MODE_SEPARATE_SPECULAR
	diffuse_buffer = vec4(0.0);
	specular_buffer = vec4(0.0);

#ifdef MODE_UNSHADED
	diffuse_buffer = vec4(emission + albedo, 0.0);
#else  // MODE_UNSHADED

#ifdef SSS_MODE_SKIN
	sss_strength = -sss_strength;
#endif // SSS_MODE_SKIN
	diffuse_buffer = vec4(diffuse_light, sss_strength);
#ifndef SPECULAR_DISABLED
	specular_buffer = vec4(specular_light, metallic);
#endif // !SPECULAR_DISABLED

#endif // MODE_UNSHADED

#ifndef FOG_DISABLED
	diffuse_buffer.rgb = diffuse_buffer.rgb * fog.a + fog.rgb;
#ifndef SPECULAR_DISABLED
	specular_buffer.rgb = specular_buffer.rgb * fog.a;
#endif // !SPECULAR_DISABLED
#endif // !FOG_DISABLED

#else  // MODE_SEPARATE_SPECULAR

	alpha *= scene_data.pass_alpha_multiplier;
#ifdef MODE_UNSHADED
	out_color = vec4(emission + albedo, alpha);
#else
	out_color = vec4(
			emission
			+ diffuse_light
#ifndef SPECULAR_DISABLED
			+ specular_light
#endif // !SPECULAR_DISABLED
			, alpha);
#endif // MODE_UNSHADED

#ifndef FOG_DISABLED
	out_color.rgb = out_color.rgb * fog.a + fog.rgb;
#endif // !FOG_DISABLED

#if defined(PREMUL_ALPHA_USED) && !defined(MODE_RENDER_PREPASS)
	out_color.rgb *= premul_alpha;
#endif // PREMUL_ALPHA_USED  && !MODE_RENDER_PREPASS

#endif // MODE_SEPARATE_SPECULAR


#endif // MODE_RENDER_PREPASS


#ifdef MOTION_VECTORS
	vec2 position_clip = (screen_position.xy / screen_position.w) - scene_data.taa_jitter;
	vec2 prev_position_clip = (prev_screen_position.xy / prev_screen_position.w) - scene_data_block.prev_data.taa_jitter;

	vec2 position_uv = position_clip * vec2(0.5, 0.5);
	vec2 prev_position_uv = prev_position_clip * vec2(0.5, 0.5);

	motion_buffer = prev_position_uv - position_uv;
#endif // MOTION_VECTORS
}


///////////////////////////////////////
////  FRAGMENT STAGE ENTRY POINT  ////
void main()
{
#ifdef UBERSHADER
	bool front_facing = gl_FrontFacing;
	if (uc_cull_mode() == POLYGON_CULL_BACK && !front_facing)
		discard;
	else if (uc_cull_mode() == POLYGON_CULL_FRONT && front_facing)
		discard;
#endif // UBERSHADER

#ifdef MODE_DUAL_PARABOLOID
	if (dp_clip > 0.0)
		discard;
#endif // MODE_DUAL_PARABOLOID

	fragment_shader(scene_data_block.data);
}
