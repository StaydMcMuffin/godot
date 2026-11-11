// Helper functions for generating and evaluating L1 spherical harmonics coefficients.
#ifndef SH_INCLUDE

// Copied from `modules/lightmapper_rd/lm_compute.glsl`
#define BASIS_L0			0.282095
#define BASIS_L1			0.488603

// Copied from `scene_forward_clustered.glsl`
#define BASIS_A0			0.886227	// sqrt(1.0/(4.0*PI))  * PI
#define BASIS_A1			1.023327	// sqrt(3.0/(4.0*PI))  * PI*2.0/3.0
#define BASIS_A2_0			0.858086	// sqrt(15.0/(4.0*PI)) * PI*1.0/4.0
#define BASIS_A2_1			0.247708	// sqrt(5.0/(16.0*PI)) * PI*1.0/4.0
#define BASIS_A2_2			0.429043	// sqrt(15.0/(16.0*PI))* PI*1.0/4.0

#define BASIS_B1			BASIS_A1 * (3.0 / 2.0)
#define BASIS_Z3			(sqrt(5.0 / (16.0 * M_PI)))


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

/// Evaluate the irradiance of a set of L1 coefficients in a given direction (lightmap SH version).
vec3 sh_l1_evaluate (
		in vec3 dir,
		in vec3 sh_l0,
		in vec3 sh_l1_x, in vec3 sh_l1_y, in vec3 sh_l1_z
	)
{
	vec3 out_sh = sh_l0;
	out_sh += sh_l1_x * dir.x;
	out_sh += sh_l1_y * dir.y;
	out_sh += sh_l1_z * dir.z;
	return max(vec3(0.0), out_sh);
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

vec3 sh_l1_evaluate_geomerics (
		in vec3 dir,
		in vec3 sh_l0,
		in vec3 sh_l1_x, in vec3 sh_l1_y, in vec3 sh_l1_z
	)
{
	vec4 sh_r, sh_g, sh_b;
	sh_r.xyz = vec3(sh_l1_x.r, sh_l1_y.r, sh_l1_z.r);
	sh_r.w = dot(sh_r.xyz, sh_r.xyz) + 0.000001;
	sh_r *= inversesqrt(sh_r.w);
	sh_g.xyz = vec3(sh_l1_x.g, sh_l1_y.g, sh_l1_z.g);
	sh_g.w = dot(sh_g.xyz, sh_g.xyz) + 0.000001;
	sh_g *= inversesqrt(sh_g.w);
	sh_b.xyz = vec3(sh_l1_x.b, sh_l1_y.b, sh_l1_z.b);
	sh_b.w = dot(sh_b.xyz, sh_b.xyz) + 0.000001;
	sh_b *= inversesqrt(sh_b.w);

	vec3 sh_v = vec3(
			(1.0 - sh_r.w) / (1.0 + sh_r.w),
			(1.0 - sh_g.w) / (1.0 + sh_g.w),
			(1.0 - sh_b.w) / (1.0 + sh_b.w)
	);

	vec3 out_sh;
	float cosine, sharpness;
	
	cosine = dot(dir, sh_r.xyz) * 0.5 + 0.5;
	sharpness = sh_r.w * 2.0 + 1.0;
	out_sh.r = (sh_r.w <= 0.000001) ? sh_l0.r : sh_l0.r * (pow(cosine, sharpness) * (sharpness + 1.0) * (1.0 - sh_v.r) + sh_v.r);
	
	cosine = dot(dir, sh_g.xyz) * 0.5 + 0.5;
	sharpness = sh_g.w * 2.0 + 1.0;
	out_sh.g = (sh_g.w <= 0.000001) ? sh_l0.g : sh_l0.g * (pow(cosine, sharpness) * (sharpness + 1.0) * (1.0 - sh_v.g) + sh_v.g);
	
	cosine = dot(dir, sh_b.xyz) * 0.5 + 0.5;
	sharpness = sh_b.w * 2.0 + 1.0;
	out_sh.b = (sh_b.w <= 0.000001) ? sh_l0.b : sh_l0.b * (pow(cosine, sharpness) * (sharpness + 1.0) * (1.0 - sh_v.b) + sh_v.b);
	
	return max(vec3(0.0), out_sh) * (0.886227 + 1.023327);
}

/// Evalutate a set of L1 SH coefficients in the given direction, with hallucinated ZH3 band.
/// From "ZH3: Quadratic Zonal Harmonics" ( https://torust.me/ZH3.p )
vec3 sh_l1_evaluate_zh3 (
		in vec3 dir,
		in vec3 sh_l0,
		in vec3 sh_l1_x, in vec3 sh_l1_y, in vec3 sh_l1_z
	)
{
	
	const vec3 lum = vec3(0.212639, 0.715169, 0.072192);
	vec3 zonal_axis = normalize(vec3(
		dot(sh_l1_x, lum),
		dot(sh_l1_y, lum),
		dot(sh_l1_z, lum)
	));
	vec3 ratio = vec3(
		abs(dot(vec3(sh_l1_x[0], sh_l1_y[0], sh_l1_z[0]), zonal_axis)),
		abs(dot(vec3(sh_l1_x[1], sh_l1_y[1], sh_l1_z[1]), zonal_axis)),
		abs(dot(vec3(sh_l1_x[2], sh_l1_y[2], sh_l1_z[2]), zonal_axis))
	) / (vec3(sh_l0.r, sh_l0.g, sh_l0.b) + 0.000001);
	vec3 zl2_coeff = sh_l0.rgb * (vec3(0.08) * ratio + vec3(0.6) * ratio * ratio);
	
	float z = dot(zonal_axis, dir);
	float zh_dir = BASIS_Z3 * (3.0 * z * z - 1.0);
	
	vec3 out_sh = sh_l0;
	out_sh += sh_l1_x * dir.x;
	out_sh += sh_l1_y * dir.y;
	out_sh += sh_l1_z * dir.z;
	return max(vec3(0.0), out_sh + (0.25 * zl2_coeff * zh_dir));
}

/// Calculate the "hallucinated" ZH3 band for a set of L1 SH coefficients.
void sh_l1_get_zh3_band (
		in vec3 sh_l0,
		in vec3 sh_l1_x, in vec3 sh_l1_y, in vec3 sh_l1_z,
		out vec3 zonal_axis, out vec3 zl2_coeff
	)
{
	const vec3 lum = vec3(0.212639, 0.715169, 0.072192);
	zonal_axis = normalize(vec3(
		dot(sh_l1_x, lum),
		dot(sh_l1_y, lum),
		dot(sh_l1_z, lum)
	));
	vec3 ratio = vec3(
		abs(dot(vec3(sh_l1_x[0], sh_l1_y[0], sh_l1_z[0]), zonal_axis)),
		abs(dot(vec3(sh_l1_x[1], sh_l1_y[1], sh_l1_z[1]), zonal_axis)),
		abs(dot(vec3(sh_l1_x[2], sh_l1_y[2], sh_l1_z[2]), zonal_axis))
	) / (vec3(sh_l0.r, sh_l0.g, sh_l0.b) + 0.0001);
	zl2_coeff = sh_l0.rgb * (vec3(0.08) * ratio + vec3(0.6) * ratio * ratio) * 0.25;
}

/// Evalutate a set of L1+ZH3 SH coefficients in the given direction.
vec3 sh_l1_evaluate_zh3 (
		in vec3 dir,
		in vec3 sh_l0,
		in vec3 sh_l1_x, in vec3 sh_l1_y, in vec3 sh_l1_z,
		in vec3 zonal_axis, in vec3 zl2_coeff
	)
{	
	float z = dot(zonal_axis, dir);
	float zh_dir = BASIS_Z3 * (3.0 * z * z - 1.0);
	
	vec3 out_sh = sh_l0;
	out_sh += sh_l1_x * dir.x;
	out_sh += sh_l1_y * dir.y;
	out_sh += sh_l1_z * dir.z;
	return max(vec3(0.0), out_sh + zl2_coeff * zh_dir);
}

/// Evaluate a set of L2 SH coefficients in the given direction.
vec3 sh_l2_evaluate(in vec4 sh[9], in vec3 dir)
{
	return max(vec3(0.0),
			BASIS_A0 * sh[0].rgb +
			
			BASIS_A1 * sh[1].rgb * dir.y +
			BASIS_A1 * sh[2].rgb * dir.z +
			BASIS_A1 * sh[3].rgb * dir.x +

			BASIS_A2_0 * sh[4].rgb * dir.x * dir.y +
			BASIS_A2_0 * sh[5].rgb * dir.y * dir.z +
			BASIS_A2_1 * sh[6].rgb * (3.0 * dir.z * dir.z - 1.0) +
			BASIS_A2_0 * sh[7].rgb * dir.x * dir.z +
			BASIS_A2_2 * sh[8].rgb * (dir.x * dir.x - dir.y * dir.y)
	);
}

#define SH_INCLUDE
#endif // SH_INCLUDE
