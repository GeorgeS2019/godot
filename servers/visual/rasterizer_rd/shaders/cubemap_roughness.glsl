/* clang-format off */
[vertex]

#version 450

VERSION_DEFINES

layout(location = 0) out highp vec2 uv_interp;
/* clang-format on */

void main() {

	vec2 base_arr[4] = vec2[](vec2(0.0, 0.0), vec2(0.0, 1.0), vec2(1.0, 1.0), vec2(1.0, 0.0));
	uv_interp = base_arr[gl_VertexIndex];
	gl_Position = vec4(uv_interp * 2.0 - 1.0, 0.0, 1.0);
}

/* clang-format off */
[fragment]

#version 450

VERSION_DEFINES

#ifdef MODE_SOURCE_PANORAMA
layout(set = 0, binding = 0) uniform sampler2D source_panorama;
/* clang-format on */
#endif

#ifdef MODE_SOURCE_CUBEMAP
layout(set = 0, binding = 0) uniform samplerCube source_cube;
#endif

layout(push_constant, binding = 1, std430) uniform Params {
	uint face_id;
	uint sample_count;
	float roughness;
	bool use_direct_write;
}
params;

layout(location = 0) in vec2 uv_interp;

layout(location = 0) out vec4 frag_color;

#define M_PI 3.14159265359

vec3 texelCoordToVec(vec2 uv, uint faceID) {
	mat3 faceUvVectors[6];
	/*
	// -x
	faceUvVectors[0][0] = vec3(0.0, 0.0, 1.0);  // u -> +z
	faceUvVectors[0][1] = vec3(0.0, -1.0, 0.0); // v -> -y
	faceUvVectors[0][2] = vec3(-1.0, 0.0, 0.0); // -x face

	// +x
	faceUvVectors[1][0] = vec3(0.0, 0.0, -1.0); // u -> -z
	faceUvVectors[1][1] = vec3(0.0, -1.0, 0.0); // v -> -y
	faceUvVectors[1][2] = vec3(1.0, 0.0, 0.0);  // +x face

	// -y
	faceUvVectors[2][0] = vec3(1.0, 0.0, 0.0);  // u -> +x
	faceUvVectors[2][1] = vec3(0.0, 0.0, -1.0); // v -> -z
	faceUvVectors[2][2] = vec3(0.0, -1.0, 0.0); // -y face

	// +y
	faceUvVectors[3][0] = vec3(1.0, 0.0, 0.0);  // u -> +x
	faceUvVectors[3][1] = vec3(0.0, 0.0, 1.0);  // v -> +z
	faceUvVectors[3][2] = vec3(0.0, 1.0, 0.0);  // +y face

	// -z
	faceUvVectors[4][0] = vec3(-1.0, 0.0, 0.0); // u -> -x
	faceUvVectors[4][1] = vec3(0.0, -1.0, 0.0); // v -> -y
	faceUvVectors[4][2] = vec3(0.0, 0.0, -1.0); // -z face

	// +z
	faceUvVectors[5][0] = vec3(1.0, 0.0, 0.0);  // u -> +x
	faceUvVectors[5][1] = vec3(0.0, -1.0, 0.0); // v -> -y
	faceUvVectors[5][2] = vec3(0.0, 0.0, 1.0);  // +z face
	*/

	// -x
	faceUvVectors[1][0] = vec3(0.0, 0.0, 1.0); // u -> +z
	faceUvVectors[1][1] = vec3(0.0, -1.0, 0.0); // v -> -y
	faceUvVectors[1][2] = vec3(-1.0, 0.0, 0.0); // -x face

	// +x
	faceUvVectors[0][0] = vec3(0.0, 0.0, -1.0); // u -> -z
	faceUvVectors[0][1] = vec3(0.0, -1.0, 0.0); // v -> -y
	faceUvVectors[0][2] = vec3(1.0, 0.0, 0.0); // +x face

	// -y
	faceUvVectors[3][0] = vec3(1.0, 0.0, 0.0); // u -> +x
	faceUvVectors[3][1] = vec3(0.0, 0.0, -1.0); // v -> -z
	faceUvVectors[3][2] = vec3(0.0, -1.0, 0.0); // -y face

	// +y
	faceUvVectors[2][0] = vec3(1.0, 0.0, 0.0); // u -> +x
	faceUvVectors[2][1] = vec3(0.0, 0.0, 1.0); // v -> +z
	faceUvVectors[2][2] = vec3(0.0, 1.0, 0.0); // +y face

	// -z
	faceUvVectors[5][0] = vec3(-1.0, 0.0, 0.0); // u -> -x
	faceUvVectors[5][1] = vec3(0.0, -1.0, 0.0); // v -> -y
	faceUvVectors[5][2] = vec3(0.0, 0.0, -1.0); // -z face

	// +z
	faceUvVectors[4][0] = vec3(1.0, 0.0, 0.0); // u -> +x
	faceUvVectors[4][1] = vec3(0.0, -1.0, 0.0); // v -> -y
	faceUvVectors[4][2] = vec3(0.0, 0.0, 1.0); // +z face

	// out = u * s_faceUv[0] + v * s_faceUv[1] + s_faceUv[2].
	vec3 result = (faceUvVectors[faceID][0] * uv.x) + (faceUvVectors[faceID][1] * uv.y) + faceUvVectors[faceID][2];
	return normalize(result);
}

vec3 ImportanceSampleGGX(vec2 Xi, float Roughness, vec3 N) {
	float a = Roughness * Roughness; // DISNEY'S ROUGHNESS [see Burley'12 siggraph]

	// Compute distribution direction
	float Phi = 2.0 * M_PI * Xi.x;
	float CosTheta = sqrt((1.0 - Xi.y) / (1.0 + (a * a - 1.0) * Xi.y));
	float SinTheta = sqrt(1.0 - CosTheta * CosTheta);

	// Convert to spherical direction
	vec3 H;
	H.x = SinTheta * cos(Phi);
	H.y = SinTheta * sin(Phi);
	H.z = CosTheta;

	vec3 UpVector = abs(N.z) < 0.999 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
	vec3 TangentX = normalize(cross(UpVector, N));
	vec3 TangentY = cross(N, TangentX);

	// Tangent to world space
	return TangentX * H.x + TangentY * H.y + N * H.z;
}

// http://graphicrants.blogspot.com.au/2013/08/specular-brdf-reference.html
float GGX(float NdotV, float a) {
	float k = a / 2.0;
	return NdotV / (NdotV * (1.0 - k) + k);
}

// http://graphicrants.blogspot.com.au/2013/08/specular-brdf-reference.html
float G_Smith(float a, float nDotV, float nDotL) {
	return GGX(nDotL, a * a) * GGX(nDotV, a * a);
}

float radicalInverse_VdC(uint bits) {
	bits = (bits << 16u) | (bits >> 16u);
	bits = ((bits & 0x55555555u) << 1u) | ((bits & 0xAAAAAAAAu) >> 1u);
	bits = ((bits & 0x33333333u) << 2u) | ((bits & 0xCCCCCCCCu) >> 2u);
	bits = ((bits & 0x0F0F0F0Fu) << 4u) | ((bits & 0xF0F0F0F0u) >> 4u);
	bits = ((bits & 0x00FF00FFu) << 8u) | ((bits & 0xFF00FF00u) >> 8u);
	return float(bits) * 2.3283064365386963e-10; // / 0x100000000
}

vec2 Hammersley(uint i, uint N) {
	return vec2(float(i) / float(N), radicalInverse_VdC(i));
}

#ifdef MODE_SOURCE_PANORAMA

vec4 texturePanorama(vec3 normal, sampler2D pano) {

	vec2 st = vec2(
			atan(normal.x, -normal.z),
			acos(normal.y));

	if (st.x < 0.0)
		st.x += M_PI * 2.0;

	st /= vec2(M_PI * 2.0, M_PI);

	return textureLod(pano, st, 0.0);
}

#endif

void main() {

	vec2 uv = (uv_interp * 2.0) - 1.0;
	vec3 N = texelCoordToVec(uv, params.face_id);

	//vec4 color = color_interp;

	if (params.use_direct_write) {

#ifdef MODE_SOURCE_PANORAMA

		frag_color = vec4(texturePanorama(N, source_panorama).rgb, 1.0);
#endif

#ifdef MODE_SOURCE_CUBEMAP
		frag_color = vec4(texture(source_cube, N).rgb, 1.0);
#endif

	} else {

		vec4 sum = vec4(0.0, 0.0, 0.0, 0.0);

		for (uint sampleNum = 0u; sampleNum < params.sample_count; sampleNum++) {
			vec2 xi = Hammersley(sampleNum, params.sample_count);

			vec3 H = ImportanceSampleGGX(xi, params.roughness, N);
			vec3 V = N;
			vec3 L = (2.0 * dot(V, H) * H - V);

			float ndotl = clamp(dot(N, L), 0.0, 1.0);

			if (ndotl > 0.0) {
#ifdef MODE_SOURCE_PANORAMA
				sum.rgb += texturePanorama(L, source_panorama).rgb * ndotl;
#endif

#ifdef MODE_SOURCE_CUBEMAP
				sum.rgb += textureLod(source_cube, L, 0.0).rgb * ndotl;
#endif
				sum.a += ndotl;
			}
		}
		sum /= sum.a;

		frag_color = vec4(sum.rgb, 1.0);
	}
}
