using System;
using System.Collections;
using Bgfx;

namespace Tessera;

/// Shaders, uniforms and the shadow atlas shared by every RenderView.
static class RenderResources
{
	public const int MaxLights = 16;
	public const int CascadeCount = 4;
	/// The shadow map's size in pixels (four cascades in a 2 x 2 grid). Set before the first frame is drawn; phones
	/// use a smaller one (Gfx.UseMobileQuality).
	public static int32 ShadowAtlasSize = 4096;
	public static int32 ShadowTileSize => ShadowAtlasSize / 2;

	public static bool Ready;
	public static bgfx.ProgramHandle MeshProgram;
	public static bgfx.ProgramHandle ShadowProgram;
	public static bgfx.ProgramHandle SkyProgram;
	public static bgfx.ProgramHandle TonemapProgram;
	public static bgfx.ProgramHandle BloomDownProgram, BloomBlurProgram;
	public static bgfx.UniformHandle sBloom, uBloomParams;
	// Screen effects (docs/post-processing.md).
	public static bgfx.ProgramHandle DepthProgram, AoProgram, AoApplyProgram, DofBlurProgram, DofCombineProgram, MotionBlurProgram;
	public static bgfx.UniformHandle sDepth, sAo, sBlur, sLut;
	public static bgfx.UniformHandle uDepthViewProj, uDepthParams, uAoParams, uDofParams, uMotionParams, uPrevViewProj;
	public static bgfx.UniformHandle uPostRight, uPostUp, uPostForward, uPostEye, uGradeParams, uGradeFilter;
	public static bgfx.ProgramHandle LineProgram;

	public static bgfx.UniformHandle sAlbedo, sShadowMap, sColor;
	public static bgfx.UniformHandle uWind, uWindZone, uWindPush, uSway, uBender, uBenderPush;
	public static bgfx.UniformHandle uCamPos, uSunDir, uSunColor, uAmbientSky, uAmbientGround, uFogColor;
	public static bgfx.UniformHandle uMaterial, uEmissive, uUvTransform, uSurface, uParams, uPbr, sTexture1, sTexture2, sNormalMap, sMetalRoughMap, sOcclusionMap, sEmissiveMap;
	public static bgfx.UniformHandle sLightmap, sLightmapDirection, sLightmapShadowmask, uLightmapTransform, uLightmapDecode;
	public static bgfx.UniformHandle uLightPosRange, uLightColor, uLightDirSpot, uLightParams, uLightCount;
	public static bgfx.UniformHandle uShadowMtx, uCascadeSplits, uShadowParams;
	public static bgfx.UniformHandle uSkyZenith, uSkyHorizon, uSkyGround, uPostParams;

	public static bgfx.TextureHandle ShadowMap;
	public static bgfx.FrameBufferHandle ShadowFrameBuffer;

	public static void EnsureCreated()
	{
		if (Ready)
			return;
		MeshProgram = Gfx.LoadProgram("vs_mesh", "fs_mesh");
		ShadowProgram = Gfx.LoadProgram("vs_shadow", "fs_shadow");
		SkyProgram = Gfx.LoadProgram("vs_fullscreen", "fs_sky");
		TonemapProgram = Gfx.LoadProgram("vs_fullscreen", "fs_tonemap");
		BloomDownProgram = Gfx.LoadProgram("vs_fullscreen", "fs_bloom_down");
		BloomBlurProgram = Gfx.LoadProgram("vs_fullscreen", "fs_bloom_blur");
		sBloom = bgfx.create_uniform("s_bloom", .Sampler, 1);
		uBloomParams = bgfx.create_uniform("u_bloomParams", .Vec4, 1);
		DepthProgram = Gfx.LoadProgram("vs_depth", "fs_depth");
		AoProgram = Gfx.LoadProgram("vs_fullscreen", "fs_ao");
		AoApplyProgram = Gfx.LoadProgram("vs_fullscreen", "fs_ao_apply");
		DofBlurProgram = Gfx.LoadProgram("vs_fullscreen", "fs_dof_blur");
		DofCombineProgram = Gfx.LoadProgram("vs_fullscreen", "fs_dof_combine");
		MotionBlurProgram = Gfx.LoadProgram("vs_fullscreen", "fs_motion_blur");
		sDepth = bgfx.create_uniform("s_depth", .Sampler, 1);
		sAo = bgfx.create_uniform("s_ao", .Sampler, 1);
		sBlur = bgfx.create_uniform("s_blur", .Sampler, 1);
		sLut = bgfx.create_uniform("s_lut", .Sampler, 1);
		uDepthViewProj = bgfx.create_uniform("u_depthViewProj", .Mat4, 1);
		uDepthParams = bgfx.create_uniform("u_depthParams", .Vec4, 1);
		uAoParams = bgfx.create_uniform("u_aoParams", .Vec4, 1);
		uDofParams = bgfx.create_uniform("u_dofParams", .Vec4, 1);
		uMotionParams = bgfx.create_uniform("u_motionParams", .Vec4, 1);
		uPrevViewProj = bgfx.create_uniform("u_prevViewProj", .Mat4, 1);
		uPostRight = bgfx.create_uniform("u_postRight", .Vec4, 1);
		uPostUp = bgfx.create_uniform("u_postUp", .Vec4, 1);
		uPostForward = bgfx.create_uniform("u_postForward", .Vec4, 1);
		uPostEye = bgfx.create_uniform("u_postEye", .Vec4, 1);
		uGradeParams = bgfx.create_uniform("u_gradeParams", .Vec4, 1);
		uGradeFilter = bgfx.create_uniform("u_gradeFilter", .Vec4, 1);
		LineProgram = Gfx.LoadProgram("vs_debug", "fs_debug");

		sAlbedo = bgfx.create_uniform("s_albedo", .Sampler, 1);
		sShadowMap = bgfx.create_uniform("s_shadowMap", .Sampler, 1);
		sColor = bgfx.create_uniform("s_color", .Sampler, 1);
		uCamPos = bgfx.create_uniform("u_camPos", .Vec4, 1);
		uSunDir = bgfx.create_uniform("u_sunDir", .Vec4, 1);
		uSunColor = bgfx.create_uniform("u_sunColor", .Vec4, 1);
		uAmbientSky = bgfx.create_uniform("u_ambientSky", .Vec4, 1);
		uAmbientGround = bgfx.create_uniform("u_ambientGround", .Vec4, 1);
		uFogColor = bgfx.create_uniform("u_fogColor", .Vec4, 1);
		uMaterial = bgfx.create_uniform("u_material", .Vec4, 1);
		uEmissive = bgfx.create_uniform("u_emissive", .Vec4, 1);
		uUvTransform = bgfx.create_uniform("u_uvTransform", .Vec4, 1);
		uSurface = bgfx.create_uniform("u_surface", .Vec4, 1);
		uWind = bgfx.create_uniform("u_wind", .Vec4, 1);
		uWindZone = bgfx.create_uniform("u_windZone", .Vec4, 4);
		uWindPush = bgfx.create_uniform("u_windPush", .Vec4, 4);
		uSway = bgfx.create_uniform("u_sway", .Vec4, 1);
		uBender = bgfx.create_uniform("u_bender", .Vec4, 8);
		uBenderPush = bgfx.create_uniform("u_benderPush", .Vec4, 8);
		uParams = bgfx.create_uniform("u_params", .Vec4, ShaderAsset.MaxValues);
		sTexture1 = bgfx.create_uniform("s_texture1", .Sampler, 1);
		sTexture2 = bgfx.create_uniform("s_texture2", .Sampler, 1);
		uPbr = bgfx.create_uniform("u_pbr", .Vec4, 1);
		sLightmap = bgfx.create_uniform("s_lightmap", .Sampler, 1);
		sLightmapDirection = bgfx.create_uniform("s_lightmapDirection", .Sampler, 1);
		sLightmapShadowmask = bgfx.create_uniform("s_lightmapShadowmask", .Sampler, 1);
		uLightmapTransform = bgfx.create_uniform("u_lightmapTransform", .Vec4, 1);
		uLightmapDecode = bgfx.create_uniform("u_lightmapDecode", .Vec4, 1);
		sNormalMap = bgfx.create_uniform("s_normalMap", .Sampler, 1);
		sMetalRoughMap = bgfx.create_uniform("s_metalRoughMap", .Sampler, 1);
		sOcclusionMap = bgfx.create_uniform("s_occlusionMap", .Sampler, 1);
		sEmissiveMap = bgfx.create_uniform("s_emissiveMap", .Sampler, 1);
		uLightPosRange = bgfx.create_uniform("u_lightPosRange", .Vec4, MaxLights);
		uLightColor = bgfx.create_uniform("u_lightColor", .Vec4, MaxLights);
		uLightDirSpot = bgfx.create_uniform("u_lightDirSpot", .Vec4, MaxLights);
		uLightParams = bgfx.create_uniform("u_lightParams", .Vec4, MaxLights);
		uLightCount = bgfx.create_uniform("u_lightCount", .Vec4, 1);
		uShadowMtx = bgfx.create_uniform("u_shadowMtx", .Mat4, CascadeCount);
		uCascadeSplits = bgfx.create_uniform("u_cascadeSplits", .Vec4, 1);
		uShadowParams = bgfx.create_uniform("u_shadowParams", .Vec4, 1);
		uSkyZenith = bgfx.create_uniform("u_skyZenith", .Vec4, 1);
		uSkyHorizon = bgfx.create_uniform("u_skyHorizon", .Vec4, 1);
		uSkyGround = bgfx.create_uniform("u_skyGround", .Vec4, 1);
		uPostParams = bgfx.create_uniform("u_postParams", .Vec4, 1);

		// Depth render target sampled with hardware comparison (PCF).
		let shadowFlags = Gfx.TextureRenderTarget | Gfx.SamplerCompareLequal | Gfx.SamplerClamp;
		ShadowMap = bgfx.create_texture_2d((uint16)ShadowAtlasSize, (uint16)ShadowAtlasSize, false, 1, .D32F, shadowFlags, null, 0);
		ShadowFrameBuffer = bgfx.create_frame_buffer_from_handles(1, &ShadowMap, true);
		Ready = true;
	}

	public static void Destroy()
	{
		if (!Ready)
			return;
		bgfx.destroy_uniform(sLightmap);
		bgfx.destroy_uniform(sLightmapDirection);
		bgfx.destroy_uniform(sLightmapShadowmask);
		bgfx.destroy_uniform(uLightmapTransform);
		bgfx.destroy_uniform(uLightmapDecode);
		bgfx.destroy_program(MeshProgram);
		bgfx.destroy_program(ShadowProgram);
		bgfx.destroy_program(SkyProgram);
		bgfx.destroy_program(TonemapProgram);
		bgfx.destroy_program(BloomDownProgram);
		bgfx.destroy_program(BloomBlurProgram);
		bgfx.destroy_program(DepthProgram);
		bgfx.destroy_program(AoProgram);
		bgfx.destroy_program(AoApplyProgram);
		bgfx.destroy_program(DofBlurProgram);
		bgfx.destroy_program(DofCombineProgram);
		bgfx.destroy_program(MotionBlurProgram);
		bgfx.destroy_program(LineProgram);
		bgfx.destroy_frame_buffer(ShadowFrameBuffer);
		Ready = false;
	}
}

/// Renders a scene from one viewpoint into a texture (editor panels) or the backbuffer (players).
///
