// Helper functions for generating and evaluating L1 spherical harmonics coefficients.


// Copied from `modules/lightmapper_rd/lm_compute.glsl`
#define BASIS_L0			0.282095
#define BASIS_L1			0.488603

// Copied from `scene_forward_clustered.glsl`
#define BASIS_A0			0.886227
#define BASIS_A1			1.023327
#define BASIS_B1			BASIS_A1 * (3.0 / 2.0)


/// Project a scalar value into the L1 basis in a given direction.
vec4 sh_l1_project(in vec3 dir, in float scale)
{
	return vec4(
	    BASIS_L0,
	    BASIS_L1 * dir.y,
	    BASIS_L1 * dir.z,
	    BASIS_L1 * dir.x
	) * scale;
}

/// Project an RGB color value into the L1 basis in a given direction, then add it to the given accumulators.
void sh_l1_project(
		in vec3 dir, in vec3 color,
		inout vec4 sh_r, inout vec4 sh_g, inout vec4 sh_b
	)
{
	vec4 proj = vec4(
		BASIS_L0,
		BASIS_L1 * dir.y,
		BASIS_L1 * dir.z,
		BASIS_L1 * dir.x
	);
	sh_r += proj * color.r;
	sh_g += proj * color.g;
	sh_b += proj * color.b;
}

/// Evaluate the irradiance of a set of L1 coefficients in a given direction.
float sh_l1_evaluate(in vec4 sh, in vec3 dir)
{
	vec4 delta = vec4(
		BASIS_A0,
		BASIS_A1 * dir.y,
		BASIS_A1 * dir.z,
		BASIS_A1 * dir.x
	);
	return max(dot(sh, delta), 0.0);
}
vec3 sh_l1_evaluate(in vec4 sh_r, in vec4 sh_g, in vec4 sh_b, in vec3 dir)
{
	vec4 delta = vec4(
		BASIS_A0,
		BASIS_A1 * dir.y,
		BASIS_A1 * dir.z,
		BASIS_A1 * dir.x
	);
	return max(vec3(
		dot(sh_r, delta),
		dot(sh_g, delta),
		dot(sh_b, delta)
	), vec3(0.0));
}

/// Evaluate the radiance of a set of L1 coefficients in a given direction.
float sh_l1_evaluate_rad(in vec4 sh, in vec3 dir)
{
	vec4 delta = vec4(
		BASIS_A0,
		BASIS_B1 * dir.y,
		BASIS_B1 * dir.z,
		BASIS_B1 * dir.x
	);
	return max(dot(sh, delta), 0.0);
}
vec3 sh_l1_evaluate_rad(in vec4 sh_r, in vec4 sh_g, in vec4 sh_b, in vec3 dir)
{
	vec4 delta = vec4(
		BASIS_A0,
		BASIS_B1 * dir.y,
		BASIS_B1 * dir.z,
		BASIS_B1 * dir.x
	);
	return max(vec3(
		dot(sh_r, delta),
		dot(sh_g, delta),
		dot(sh_b, delta)
	), vec3(0.0));
}

/// Blend between evaluating the radiance and irradiance of a set of L1 coefficients based on roughness.
float sh_l1_evaluate_spec(in vec4 sh, in vec3 dir, in float roughness)
{
	const float BASIS_S1 = mix(BASIS_B1, BASIS_A1, roughness);
	vec4 delta = vec4(
		BASIS_A0,
		BASIS_S1 * dir.y,
		BASIS_S1 * dir.z,
		BASIS_S1 * dir.x
	);
	return max(dot(sh, delta), 0.0);
}
vec3 sh_l1_evaluate_spec(in vec4 sh_r, in vec4 sh_g, in vec4 sh_b, in vec3 dir, in float roughness)
{
	const float BASIS_S1 = mix(BASIS_B1, BASIS_A1, roughness);
	vec4 delta = vec4(
		BASIS_A0,
		BASIS_S1 * dir.y,
		BASIS_S1 * dir.z,
		BASIS_S1 * dir.x
	);
	return max(vec3(
		dot(sh_r, delta),
		dot(sh_g, delta),
		dot(sh_b, delta)
	), vec3(0.0));
}
