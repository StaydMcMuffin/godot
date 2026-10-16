// Simplified versions of light functions intended for the vertex shader.

// This annotation macro must be placed before any loops that rely on specialization constants as their upper bound.
// Drivers may choose to unroll these loops based on the possible range of the value that can be deduced from the
// spec constant, which can lead to their code generation taking a much longer time than desired.
#ifdef UBERSHADER
#extension GL_EXT_control_flow_attributes : require
// Prefer to not unroll loops on the ubershader to reduce code size as much as possible.
#define SPEC_CONSTANT_LOOP_ANNOTATION [[dont_unroll]]
#else
// Don't make an explicit hint on specialized shaders.
#define SPEC_CONSTANT_LOOP_ANNOTATION
#endif


float sqr (in float x)	{ return x * x; }
vec2  sqr (in vec2 v)	{ return v * v; }
vec3  sqr (in vec3 v)	{ return v * v; }
vec4  sqr (in vec4 v)	{ return v * v; }
float length2 (in vec2 v)	{ return dot(v, v); }
float length2 (in vec3 v)	{ return dot(v, v); }
float length2 (in vec4 v)	{ return dot(v, v); }


// Converts GGX roughness to Blinn-Phong shininess.
// Roughly approximates `2.0 / roughness * roughness - 2.0` with a much lower high end.
// Range is ~[0.05,656].
half roughness_to_shininess(half roughness)
{
	half s = 1.5 - roughness * 0.667;
	s *= s; s *= s; s *= s; s *= s; // pow(s, 16)
	return s;
}


float D_GGX (in float NdotH, in float alpha)
{
	alpha = alpha * 0.99 + 0.01;  // Soft-limit minimum roughness to lessen per-vertex aliasing.
	float alpha_sqr = alpha * alpha;
	float denom = NdotH * NdotH * (alpha_sqr - 1.0) + 1.0;
	return alpha_sqr / (M_PI * denom * denom);
}


#ifndef SHADOWS_DISABLED
half sample_pcf_shadow_vertex(texture2D shadow, vec2 shadow_pixel_size, vec3 coord)
{
	// If only one sample is taken, take it from the center.
	if (sc_soft_shadow_samples() == 0)
		return half(textureProj(sampler2DShadow(shadow, shadow_sampler), vec4(coord.xy, coord.z, 1.0)));

	float avg = 0.0;

	SPEC_CONSTANT_LOOP_ANNOTATION
	for (uint i = 0; i < sc_soft_shadow_samples(); i++)
	{
		avg += textureProj(sampler2DShadow(shadow, shadow_sampler), vec4(coord.xy + shadow_pixel_size * scene_data_block.data.soft_shadow_kernel[i].xy, coord.z, 1.0));
	}

	return half(avg * (1.0 / float(sc_soft_shadow_samples())));
}


half sample_omni_pcf_shadow_vertex(texture2D shadow, float blur_scale, vec2 coord, vec4 uv_rect, vec2 flip_offset, float depth)
{
	// If only one sample is taken, take it from the center.
	if (sc_soft_shadow_samples() == 0)
	{
		vec2 pos = coord * 0.5 + 0.5;
		pos = uv_rect.xy + pos * uv_rect.zw;
		return half(textureProj(sampler2DShadow(shadow, shadow_sampler), vec4(pos, depth, 1.0)));
	}

	float avg = 0.0;
	vec2 offset_scale = blur_scale * 2.0 * scene_data_block.data.shadow_atlas_pixel_size / uv_rect.zw;

	SPEC_CONSTANT_LOOP_ANNOTATION
	for (uint i = 0; i < sc_soft_shadow_samples(); i++)
	{
		vec2 offset = offset_scale * scene_data_block.data.soft_shadow_kernel[i].xy;
		vec2 sample_coord = coord + offset;

		float sample_coord_length_squared = dot(sample_coord, sample_coord);
		bool do_flip = sample_coord_length_squared > 1.0;

		if (do_flip)
		{
			float len = sqrt(sample_coord_length_squared);
			sample_coord = sample_coord * (2.0 / len - 1.0);
		}

		sample_coord = sample_coord * 0.5 + 0.5;
		sample_coord = uv_rect.xy + sample_coord * uv_rect.zw;

		if (do_flip)
			sample_coord += flip_offset;
		
		avg += textureProj(sampler2DShadow(shadow, shadow_sampler), vec4(sample_coord, depth, 1.0));
	}

	return half(avg * (1.0 / float(sc_soft_shadow_samples())));
}


half sample_directional_pcf_shadow_vertex(texture2D shadow, vec2 shadow_pixel_size, vec4 coord)
{
	// If only one sample is taken, take it from the center.
	if (sc_directional_soft_shadow_samples() == 0)
		return half(textureProj(sampler2DShadow(shadow, shadow_sampler), vec4(coord.xy, coord.z, 1.0)));

	float avg = 0.0;

	SPEC_CONSTANT_LOOP_ANNOTATION
	for (uint i = 0; i < sc_directional_soft_shadow_samples(); i++)
	{
		avg += textureProj(sampler2DShadow(shadow, shadow_sampler), vec4(coord.xy + shadow_pixel_size * scene_data_block.data.directional_soft_shadow_kernel[i].xy, coord.z, 1.0));
	}

	return half(avg * (1.0 / float(sc_directional_soft_shadow_samples())));
}
#endif // !SHADOWS_DISABLED


void light_compute_vertex(
		vec3 N, vec3 L, vec3 V, float W, vec3 light_color,
		float roughness, float specular_amount,
		inout vec3 diffuse_light, inout vec3 specular_light
	)
{
	float cos_W = 0.0; float cos_W_norm = 1.0; float W_norm = 1.0;
	if (W > 0.0)
	{
		cos_W = max(0.0, 1.0 - inversesqrt(1.0 + W * W));
		//cos_W = max(0.0, W * inversesqrt(1.0 + W * W));
		cos_W_norm = 1.0 / (1.0 + cos_W);
		W_norm = 1.0 / (1.0 + W);
	}

	float NdotL = clamp((W + dot(N, L)) * W_norm, -1.0, 1.0);
	float cNdotL = max(NdotL, 0.0);

#if defined(DIFFUSE_LAMBERT_WRAP)
	// Energy conserving lambert wrap shader.
	// https://web.archive.org/web/20210228210901/http://blog.stevemcauley.com/2011/12/03/energy-conserving-wrapped-diffuse/
	float diffuse = max(0.0, (NdotL + roughness) / ((1.0 + roughness) * (1.0 + roughness)));
#elif defined(DIFFUSE_TOON)
	float softness = roughness * 0.9 + 0.1;  // Enforce minimum 10% softness to reduce per-vertex aliasing.
	float diffuse = smoothstep(-softness, softness, NdotL);
#else  // DIFFUSE_LAMBERT
	float diffuse = cNdotL;
#endif // DIFFUSE_MODE
	diffuse_light += light_color * diffuse * (1.0 / M_PI);

#ifndef SPECULAR_DISABLED
#if defined(SPECULAR_TOON)
	vec3 R = normalize(-reflect(L, N));
	float RdotV = (W + dot(R, V)) * W_norm;
	float mid = 1.0 - roughness; mid *= mid;
	float softness = roughness * 0.49 + 0.01;  // Enforce minimum 1% softness to slightly reduce per-vertex aliasing.
	float intensity = smoothstep(max(-1.0, mid - softness), min(1.0, mid + softness), RdotV) * mid;
	diffuse_light += light_color * (intensity * specular_amount);  // Toon shading writes to diffuse_light, so specularity is affected by diffuse color.
#else  // SPECULAR_SCHLICK_GGX
	hvec3 H = normalize(V + L);
	float cNdotH = clamp((W + dot(N, H)) * W_norm, 0.0001, 1.0);
#if 0
	// Normalized Blinn (TODO: make Blinn selectable alongside GGX and Toon)
	float shininess = roughness_to_shininess(roughness);
	float blinn = pow(cNdotH, shininess);
	blinn *= (shininess + 8.0) * (1.0 / (8.0 * M_PI)) * cNdotL;
	specular_light += light_color * (blinn * specular_amount);
#else
	float ggx = D_GGX(cNdotH, roughness * roughness) * cNdotL;
	specular_light += light_color * (ggx * specular_amount);
#endif
#endif // SPECULAR_MODE
#endif // !SPECULAR_DISABLED
}


float get_distance_attenuation (
		in float distance, in float inv_range, in float area, in float decay)
{
	float linear_distance = clamp(distance * inv_range, 0.0, 1.0);
	float falloff = sqr(1.0 - sqr(sqr(linear_distance)));  // Frostbite range falloff.
	
	float distance2 = distance * distance; float area2 = area * area;
#if 1
	// Common ad-hoc sphere light attenuation, with power curve.
	// NOTE: This formula is normally energy-conserving, but to support `decay` power we scale the result back up
	//       then re-apply normalization by scaling `energy` on the CPU side.
	float attenuation = pow((1.0 + area2 * 0.5) / (distance2 + area2 * 0.5), decay * 0.5);
#else
	// From "Point Light Attenuation Without Singularity" by Cem Yuksel
	// ( http://www.cemyuksel.com/research/pointlightattenuation/pointlightattenuation.pdf )
	float attenuation = (1.0 + area * area)  / (distance2 + area2 + distance * sqrt(distance2 + area2));
	attenuation = pow(attenuation, decay * 0.5);
#endif

	return attenuation * falloff;
}


void light_process_omni_vertex(
		uint idx, vec3 vertex, hvec3 eye_vec, hvec3 normal, half roughness,
		inout hvec3 diffuse_light, inout hvec3 specular_light)
{
	vec3 light_dir = omni_lights.data[idx].position - vertex;
	float light_len = dot(light_dir, light_dir);
	float light_len_rcp = inversesqrt(light_len);
	light_dir *= light_len_rcp; light_len *= light_len_rcp;

	float area_radius = max(0.001, omni_lights.data[idx].size);
	float omni_attenuation = get_distance_attenuation(light_len, omni_lights.data[idx].inv_radius, area_radius, omni_lights.data[idx].attenuation);
	area_radius *= light_len_rcp;
	
#ifndef SHADOWS_DISABLED
	if (omni_attenuation > HALF_FLT_MIN && omni_lights.data[idx].shadow_opacity > 0.001)
	{
		vec2 texel_size = scene_data_block.data.shadow_atlas_pixel_size;
		vec4 uv_rect = omni_lights.data[idx].atlas_rect;
		uv_rect.xy += texel_size;
		uv_rect.zw -= texel_size * 2.0;

		vec3 shadow_dir = (omni_lights.data[idx].shadow_matrix * vec4(vertex, 1.0)).xyz;
		float shadow_len = dot(shadow_dir, shadow_dir);
		float shadow_len_rcp = inversesqrt(shadow_len);
		shadow_len *= shadow_len_rcp;
		shadow_dir *= shadow_len_rcp;

		vec3 local_normal = normalize(mat3(omni_lights.data[idx].shadow_matrix) * vec3(normal));
		vec3 normal_bias = local_normal * omni_lights.data[idx].shadow_normal_bias * (1.0 - abs(dot(local_normal, shadow_dir)));

		vec2 flip_offset = omni_lights.data[idx].direction.xy;  // Omni lights use direction.xy to store the offset between the two paraboloid regions.
		vec3 shadow_sample = normalize(shadow_dir + normal_bias);
		if (shadow_sample.z >= 0.0)
		{
			uv_rect.xy += flip_offset;
			flip_offset *= -1.0;
		}

		shadow_sample.z = 1.0 + abs(shadow_sample.z);
		vec2 pos = shadow_sample.xy / shadow_sample.z;
		float depth = shadow_len - omni_lights.data[idx].shadow_bias;
		depth *= omni_lights.data[idx].inv_radius;
		depth = 1.0 - depth;
		float shadow_blur_scale = omni_lights.data[idx].soft_shadow_scale / shadow_sample.z;
		shadow_blur_scale += sqrt(shadow_blur_scale);  // Boost shadow filter scale to reduce per-vertex aliasing.
		omni_attenuation *= mix(half(1.0), sample_omni_pcf_shadow_vertex(shadow_atlas, shadow_blur_scale, pos, uv_rect, flip_offset, depth), half(omni_lights.data[idx].shadow_opacity));
	}
#endif // !SHADOWS_DISABLED

	light_compute_vertex(
			normal, light_dir, eye_vec, area_radius,
			omni_lights.data[idx].color * omni_attenuation,
			roughness, omni_lights.data[idx].specular_amount,
			diffuse_light, specular_light
	);
}


void light_process_spot_vertex(
		uint idx, vec3 vertex, hvec3 eye_vec, hvec3 normal, half roughness,
		inout hvec3 diffuse_light, inout hvec3 specular_light)
{
	vec3 light_dir = spot_lights.data[idx].position - vertex;
	float light_len = dot(light_dir, light_dir);
	float light_len_rcp = inversesqrt(light_len);
	light_dir *= light_len_rcp; light_len *= light_len_rcp;

	float area_radius = max(0.001, spot_lights.data[idx].size);
	float spot_attenuation = get_distance_attenuation(light_len, spot_lights.data[idx].inv_radius, area_radius, spot_lights.data[idx].attenuation);
	area_radius *= light_len_rcp;

	vec3 spot_dir = spot_lights.data[idx].direction;
	float spot = clamp(acos(dot(-vec3(light_dir), spot_dir)) * spot_lights.data[idx].cone_angle, 0.0, 1.0);
	spot = 1.0 - pow(spot, spot_lights.data[idx].cone_attenuation);
	spot_attenuation *= half(spot * spot);

#ifndef SHADOWS_DISABLED
	if (spot_attenuation > HALF_FLT_MIN && spot_lights.data[idx].shadow_opacity > 0.001)
	{
		vec3 normal_bias = vec3(normal) * light_len * spot_lights.data[idx].shadow_normal_bias * (1.0 - abs(dot(normal, light_dir)));
		vec4 v = vec4(vertex + normal_bias, 1.0);

		vec4 splane = (spot_lights.data[idx].shadow_matrix * v);
		splane.z += spot_lights.data[idx].shadow_bias;
		splane /= splane.w;

		vec3 shadow_uv = vec3(splane.xy * spot_lights.data[idx].atlas_rect.zw + spot_lights.data[idx].atlas_rect.xy, splane.z);
		float shadow_blur_scale = spot_lights.data[idx].soft_shadow_scale;
		shadow_blur_scale += sqrt(shadow_blur_scale);  // Boost shadow filter scale to reduce per-vertex aliasing.
		spot_attenuation *= mix(half(1.0), sample_pcf_shadow_vertex(shadow_atlas, scene_data_block.data.shadow_atlas_pixel_size * shadow_blur_scale, shadow_uv), half(spot_lights.data[idx].shadow_opacity));
	}
#endif // !SHADOWS_DISABLED

	light_compute_vertex(
			normal, light_dir, eye_vec, area_radius,
			spot_lights.data[idx].color * spot_attenuation,
			roughness, spot_lights.data[idx].specular_amount,
			diffuse_light, specular_light
	);
}
