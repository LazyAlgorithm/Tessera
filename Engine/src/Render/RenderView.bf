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
		let shadowFlags = (uint64)0x0000001000000000 | 0x00020000 | 0x0000002a;
		ShadowMap = bgfx.create_texture_2d((uint16)ShadowAtlasSize, (uint16)ShadowAtlasSize, false, 1, .D32F, shadowFlags, null, 0);
		ShadowFrameBuffer = bgfx.create_frame_buffer_from_handles(1, &ShadowMap, true);
		Ready = true;
	}

	public static void Destroy()
	{
		if (!Ready)
			return;
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
/// Pipeline: four shadow cascades for the sun, an HDR multisampled forward pass with sky,
/// instanced opaque geometry and debug lines, see-through geometry, the viewmodel (a first-person camera's arms and
/// weapon, over everything: Camera.viewmodelLayer), the screen effects the scene asks for (ambient occlusion, depth of
/// field and motion blur, from a depth pass: docs/post-processing.md), bloom, then a tonemapping resolve with colour
/// grading. Each RenderView uses ViewCount (17) consecutive bgfx view ids starting at ViewBase: shadows 0 to 3, scene
/// 4, see-through 5, viewmodel 6, depth 7, ambient occlusion 8 and 9, depth of field 10 and 11, motion blur 12, bloom
/// 13 to 15, tonemap 16.
class RenderView
{
	struct RenderItem
	{
		public uint64 key;
		public Mesh mesh;
		public MeshRenderer renderer;
		/// The material this item is drawn with: a part's own (MeshRenderer.RuntimeParts) or the renderer's.
		public Material material;
		public Matrix4 world;
		public Vector3 center;
		public float radius;
		/// Multiplies the renderer's colour for this one item (Foliage gives each plant a shade of its own).
		public Color tint;
	}

	[CRepr]
	struct InstanceData
	{
		public Matrix4 world;
		public Color color;
	}

	/// How many bgfx view ids one RenderView uses, from ViewBase. Give each RenderView a ViewBase this far apart.
	public const int ViewCount = 17;
	const int cDepthView = 7, cAoView = 8, cAoApplyView = 9, cDofBlurView = 10, cDofCombineView = 11, cMotionView = 12, cBloomView = 13, cTonemapView = 16;

	public uint16 ViewBase;
	/// Which of the scene's screen effects this view shows (the editor's Scene view leaves out depth of field and
	/// motion blur, which get in the way of editing).
	public bool ShowAmbientOcclusion = true;
	public bool ShowDepthOfField = true;
	public bool ShowMotionBlur = true;
	public bool ToBackbuffer;
	/// How much of the output's resolution the 3D scene is drawn at: below 1 it is drawn smaller and stretched to
	/// fit, which costs much less on a phone's many pixels. The interface is drawn afterwards at full resolution.
	public static float RenderScale = 1;
	/// The most pixels the 3D scene is drawn at across the window's short side (its height held sideways, its width
	/// held upright), however sharp the screen (0: no limit). Phones have very sharp screens and modest graphics
	/// chips: the scene is drawn at this and scaled up, the interface stays sharp. The same either way up.
	public static int32 MaxSceneHeight = 0;
	/// Multisampled edges on the scene. Off saves a lot on phones.
	public static bool Antialias = true;
	public bool DrawGizmos;
	public bool DrawShadows = true;

	// Statistics from the last Render call.
	public int32 DrawCalls;
	public int32 Instances;
	public int32 Triangles;
	public int32 VisibleRenderers;

	int32 mWidth;
	int32 mHeight;
	// The size drawn to (the window, or the output texture); the scene is mWidth x mHeight, RenderScale of it.
	int32 mOutWidth, mOutHeight;
	float mBuiltScale;
	bool mBuiltAntialias;
	bgfx.TextureHandle mSceneColor = .() { idx = uint16.MaxValue };
	bgfx.FrameBufferHandle mSceneFb = .() { idx = uint16.MaxValue };
	bgfx.TextureHandle mOutputColor = .() { idx = uint16.MaxValue };
	bgfx.FrameBufferHandle mOutputFb = .() { idx = uint16.MaxValue };
	// Bloom works at a quarter of the size: one target to shrink into and blur down, one to blur across.
	bgfx.TextureHandle[2] mBloomColor = .(.() { idx = uint16.MaxValue }, .() { idx = uint16.MaxValue });
	bgfx.FrameBufferHandle[2] mBloomFb = .(.() { idx = uint16.MaxValue }, .() { idx = uint16.MaxValue });
	int32 mBloomWidth, mBloomHeight;
	// The screen effects', made the first time a scene uses one: the depth pass (distance in front of the camera,
	// with a depth buffer of its own), two full-size pictures to pass the image between, half-size ambient occlusion
	// and depth of field.
	bgfx.TextureHandle mDepthColor = .() { idx = uint16.MaxValue };
	bgfx.FrameBufferHandle mDepthFb = .() { idx = uint16.MaxValue };
	bgfx.TextureHandle[2] mPostColor = .(.() { idx = uint16.MaxValue }, .() { idx = uint16.MaxValue });
	bgfx.FrameBufferHandle[2] mPostFb = .(.() { idx = uint16.MaxValue }, .() { idx = uint16.MaxValue });
	bgfx.TextureHandle mAoColor = .() { idx = uint16.MaxValue };
	bgfx.FrameBufferHandle mAoFb = .() { idx = uint16.MaxValue };
	bgfx.TextureHandle mDofColor = .() { idx = uint16.MaxValue };
	bgfx.FrameBufferHandle mDofFb = .() { idx = uint16.MaxValue };
	int32 mHalfWidth, mHalfHeight;
	// Last frame's camera, for motion blur.
	Matrix4 mPrevViewProj;
	Vector3 mPrevPosition;
	bool mHasPrev;
	Vector4 mPostRight, mPostUp, mPostForward, mPostEye;

	List<RenderItem> mItems = new .() ~ delete _;
	List<RenderItem> mShadowItems = new .() ~ delete _;
	List<RenderItem> mTransparentItems = new .() ~ delete _;
	/// Foliage, in runs of one kind of plant: drawn like mItems, but already in order and far too many to sort.
	List<RenderItem> mFoliageItems = new .() ~ delete _;
	List<int32> mFoliageVisible = new .() ~ delete _;
	Vector4 mWind;
	Vector4[4] mWindZone, mWindPush;
	Vector4[8] mBender, mBenderPush;
	// The viewmodel's (Camera.viewmodelLayer): solid, and see-through.
	List<RenderItem> mViewmodelItems = new .() ~ delete _;
	List<RenderItem> mViewmodelTransparent = new .() ~ delete _;

	// Frame constants, re-sent with every draw because bgfx orders uniform updates by sorted draw.
	Vector4 mCamPos, mSunDir, mSunColor, mAmbientSky, mAmbientGround, mFogColor, mLightCount, mCascadeSplits, mShadowParams;
	Vector4[RenderResources.MaxLights] mLightPosRange, mLightColor, mLightDirSpot, mLightParams;
	Matrix4[RenderResources.CascadeCount] mShadowMtx;
	Matrix4[RenderResources.CascadeCount] mCascadeViewProj;
	Matrix4[RenderResources.CascadeCount] mCascadeView;
	Matrix4[RenderResources.CascadeCount] mCascadeProj;
	Vector3[RenderResources.CascadeCount] mCascadeCenter;
	float[RenderResources.CascadeCount] mCascadeRadius;
	Vector3 mLightRight, mLightUp;
	bool mHasSun;

	public this(uint16 viewBase)
	{
		ViewBase = viewBase;
	}

	public ~this()
	{
		ReleaseTargets();
	}

	/// The size of the picture drawn (the scene inside may be drawn smaller: RenderScale).
	public int32 Width => mOutWidth;
	public int32 Height => mOutHeight;
	/// Texture holding the finished image when not rendering to the backbuffer.
	public uint16 OutputTexture => mOutputColor.idx;

	void ReleaseTargets()
	{
		if (!Gfx.Initialized)
			return;
		if (mSceneFb.Valid)
			bgfx.destroy_frame_buffer(mSceneFb);
		if (mOutputFb.Valid)
			bgfx.destroy_frame_buffer(mOutputFb);
		mSceneFb.idx = uint16.MaxValue;
		mOutputFb.idx = uint16.MaxValue;
		for (int i < 2)
		{
			if (mBloomFb[i].Valid)
				bgfx.destroy_frame_buffer(mBloomFb[i]);
			mBloomFb[i].idx = uint16.MaxValue;
		}
		ReleaseEffectTargets();
	}

	void ReleaseEffectTargets()
	{
		void Release(ref bgfx.FrameBufferHandle fb)
		{
			if (fb.Valid)
				bgfx.destroy_frame_buffer(fb);
			fb.idx = uint16.MaxValue;
		}
		Release(ref mDepthFb);
		Release(ref mPostFb[0]);
		Release(ref mPostFb[1]);
		Release(ref mAoFb);
		Release(ref mDofFb);
	}

	/// Makes the screen effects' targets, at the scene's size, the first time they are needed.
	void EnsureEffectTargets()
	{
		if (mDepthFb.Valid)
			return;
		let rt = (uint64)0x0000001000000000;
		let clamp = (uint64)0x0000002a;
		let point = (uint64)0x00000040 | 0x00000100;
		let writeOnly = (uint64)0x0000008000000000;
		// Distance in front of the camera: 32-bit where it can be drawn to (precise far away), else 16-bit.
		let depthFormat = bgfx.is_texture_valid(0, false, 1, .R32F, rt | clamp | point) ? bgfx.TextureFormat.R32F : bgfx.TextureFormat.R16F;
		bgfx.TextureHandle[2] depthTextures;
		depthTextures[0] = bgfx.create_texture_2d((uint16)mWidth, (uint16)mHeight, false, 1, depthFormat, rt | clamp | point, null, 0);
		depthTextures[1] = bgfx.create_texture_2d((uint16)mWidth, (uint16)mHeight, false, 1, .D32F, rt | writeOnly, null, 0);
		mDepthColor = depthTextures[0];
		mDepthFb = bgfx.create_frame_buffer_from_handles(2, &depthTextures, true);
		for (int i < 2)
		{
			mPostColor[i] = bgfx.create_texture_2d((uint16)mWidth, (uint16)mHeight, false, 1, .RGBA16F, rt | clamp, null, 0);
			mPostFb[i] = bgfx.create_frame_buffer_from_handles(1, &mPostColor[i], true);
		}
		mHalfWidth = Math.Max(mWidth / 2, 4);
		mHalfHeight = Math.Max(mHeight / 2, 4);
		mAoColor = bgfx.create_texture_2d((uint16)mHalfWidth, (uint16)mHalfHeight, false, 1, .RGBA8, rt | clamp, null, 0);
		mAoFb = bgfx.create_frame_buffer_from_handles(1, &mAoColor, true);
		mDofColor = bgfx.create_texture_2d((uint16)mHalfWidth, (uint16)mHalfHeight, false, 1, .RGBA16F, rt | clamp, null, 0);
		mDofFb = bgfx.create_frame_buffer_from_handles(1, &mDofColor, true);
	}

	public void Resize(int32 width, int32 height)
	{
		let outWidth = Math.Max(width, 8);
		let outHeight = Math.Max(height, 8);
		var scale = Math.Clamp(RenderScale, 0.25f, 1.0f);
		if (MaxSceneHeight > 0)
			scale = Math.Max(Math.Min(scale, (float)MaxSceneHeight / Math.Min(outWidth, outHeight)), 0.25f);
		if (outWidth == mOutWidth && outHeight == mOutHeight && scale == mBuiltScale && Antialias == mBuiltAntialias && mSceneFb.Valid)
			return;
		ReleaseTargets();
		mOutWidth = outWidth;
		mOutHeight = outHeight;
		mBuiltScale = scale;
		mBuiltAntialias = Antialias;
		let w = Math.Max((int32)(outWidth * scale), 8);
		let h = Math.Max((int32)(outHeight * scale), 8);
		mWidth = w;
		mHeight = h;

		let clamp = (uint64)0x0000002a;
		// Multisampling also makes the texture a render target; without it the texture has to say so itself.
		let msaa4 = Antialias ? (uint64)0x0000003000000000 : 0;
		let target = Antialias ? msaa4 : (uint64)0x0000001000000000;
		let writeOnly = (uint64)0x0000008000000000;
		let rt = (uint64)0x0000001000000000;
		bgfx.TextureHandle[2] sceneTextures;
		sceneTextures[0] = bgfx.create_texture_2d((uint16)w, (uint16)h, false, 1, .RGBA16F, target | clamp, null, 0);
		sceneTextures[1] = bgfx.create_texture_2d((uint16)w, (uint16)h, false, 1, .D32F, msaa4 | writeOnly, null, 0);
		mSceneColor = sceneTextures[0];
		mSceneFb = bgfx.create_frame_buffer_from_handles(2, &sceneTextures, true);

		mBloomWidth = Math.Max(w / 4, 4);
		mBloomHeight = Math.Max(h / 4, 4);
		for (int i < 2)
		{
			mBloomColor[i] = bgfx.create_texture_2d((uint16)mBloomWidth, (uint16)mBloomHeight, false, 1, .RGBA16F, rt | clamp, null, 0);
			mBloomFb[i] = bgfx.create_frame_buffer_from_handles(1, &mBloomColor[i], true);
		}

		if (!ToBackbuffer)
		{
			mOutputColor = bgfx.create_texture_2d((uint16)outWidth, (uint16)outHeight, false, 1, .RGBA8, rt | clamp, null, 0);
			mOutputFb = bgfx.create_frame_buffer_from_handles(1, &mOutputColor, true);
		}
	}

	static Vector4 Linear(Color c, float scale = 1.0f)
	{
		return .(Math.Pow(Math.Max(c.r, 0), 2.2f) * scale, Math.Pow(Math.Max(c.g, 0), 2.2f) * scale, Math.Pow(Math.Max(c.b, 0), 2.2f) * scale, c.a);
	}

	public void Render(Scene scene, CameraData camera)
	{
		if (!mSceneFb.Valid)
			return;
		RenderResources.EnsureCreated();
		DrawCalls = 0;
		Instances = 0;
		Triangles = 0;

		let viewProj = camera.projection * camera.view;
		let frustum = Frustum(viewProj, Gfx.HomogeneousDepth);
		let env = scene.Environment;

		// ---- gather lights ----
		Light sun = null;
		int lightCount = 0;
		for (let light in scene.Lights)
		{
			if (!light.IsActiveAndEnabled || !light.GameObject.InActiveWorld)
				continue;
			if (light.type == .Directional)
			{
				if (sun == null)
					sun = light;
				continue;
			}
			if (lightCount >= RenderResources.MaxLights)
				continue;
			let position = light.Transform.Position;
			let color = Linear(light.color, light.intensity);
			mLightPosRange[lightCount] = .(position, light.range);
			mLightColor[lightCount] = .(color.x, color.y, color.z, light.type == .Spot ? 1.0f : 0.0f);
			let outer = Math.Cos(light.spotAngle * 0.5f * Mathf.Deg2Rad);
			let inner = Math.Cos(light.spotAngle * 0.5f * 0.8f * Mathf.Deg2Rad);
			mLightDirSpot[lightCount] = .(light.Transform.Forward, outer);
			mLightParams[lightCount] = .(inner, 0, 0, 0);
			lightCount++;
		}
		mLightCount = .(lightCount, 0, 0, 0);

		mHasSun = sun != null;
		var lightDirection = Vector3(0.3f, -1.0f, 0.2f).Normalized;
		if (mHasSun)
		{
			lightDirection = sun.Transform.Forward;
			let c = Linear(sun.color, sun.intensity);
			mSunColor = .(c.x, c.y, c.z, 1);
			mSunDir = .(-lightDirection, sun.shadowStrength);
		}
		else
		{
			mSunColor = .(0, 0, 0, 1);
			mSunDir = .(-lightDirection, 0);
		}
		let castShadows = DrawShadows && mHasSun && sun.castShadows;

		mCamPos = .(camera.position, 1);
		mAmbientSky = Linear(env.ambientSky, env.ambientIntensity);
		mAmbientGround = Linear(env.ambientGround, env.ambientIntensity);
		let fog = Linear(env.fogColor);
		mFogColor = .(fog.x, fog.y, fog.z, env.fogDensity);

		// ---- gather renderers ----
		mItems.Clear();
		mShadowItems.Clear();
		mTransparentItems.Clear();
		mViewmodelItems.Clear();
		mViewmodelTransparent.Clear();
		let shadowRange = env.shadowDistance + 60.0f;
		for (let renderer in scene.Renderers)
		{
			// Outside the scene's world state: not drawn and casts no shadow.
			if (!renderer.IsActiveAndEnabled || !renderer.GameObject.InActiveWorld)
				continue;
			// A renderer with parts draws each with its own material; otherwise its one mesh (a "part" of its own).
			let parts = renderer.RuntimeParts;
			let partCount = (parts != null && parts.Count > 0) ? parts.Count : 1;
			for (int partIndex < partCount)
			{
				let mesh = parts != null && parts.Count > 0 ? parts[partIndex].mesh : renderer.ActiveMesh;
				if (mesh == null || !mesh.HasGpuData)
					continue;
				RenderItem item;
				item.tint = .White;
				item.mesh = mesh;
				item.renderer = renderer;
				item.material = (parts != null && parts.Count > 0 && parts[partIndex].material != null) ? parts[partIndex].material : renderer.ActiveMaterial;
				item.world = renderer.Transform.LocalToWorld;
				item.world.m[12] += renderer.VisualOffset.x;
				item.world.m[13] += renderer.VisualOffset.y;
				item.world.m[14] += renderer.VisualOffset.z;
				let bounds = mesh.Bounds.Transformed(item.world);
				item.center = bounds.Center;
				item.radius = bounds.Extents.Length;
				item.key = MakeKey(renderer, mesh, item.material);
				// A color alpha below 1, or a Transparent material, makes the object see-through: it is drawn after
				// everything solid, blended, and (being glass-like) does not cast a shadow.
				let itemMaterial = item.material;
				let transparent = itemMaterial != null ? (itemMaterial.IsTransparent || (itemMaterial.blend == .Opaque && renderer.color.a * itemMaterial.color.a < 0.999f)) : renderer.color.a < 0.999f;
				// The viewmodel: drawn in a pass of its own after the world (no culling: it is a few things at the eye).
				let viewmodel = DrawsAsViewmodel(camera, renderer.GameObject);
				if (viewmodel)
				{
					if (!renderer.shadowOnly)
						(transparent ? mViewmodelTransparent : mViewmodelItems).Add(item);
				}
				else if (!renderer.shadowOnly && frustum.Intersects(bounds))
				{
					if (transparent)
						mTransparentItems.Add(item);
					else
						mItems.Add(item);
				}
				if (!transparent && castShadows && renderer.castShadows && (!viewmodel || camera.viewmodelCastsShadows) && (item.center - camera.position).Length - item.radius < shadowRange)
					mShadowItems.Add(item);
			}
		}
		// ---- foliage: every plant near enough and in view, one item each ----
		mFoliageItems.Clear();
		for (let foliage in Foliage.All)
		{
			if (foliage.GameObject == null || foliage.GameObject.IsDestroyed || foliage.Scene != scene || !foliage.IsActiveAndEnabled || !foliage.GameObject.InActiveWorld)
				continue;
			let mesh = foliage.Mesh;
			if (mesh == null || !mesh.HasGpuData)
				continue;
			mFoliageVisible.Clear();
			foliage.Visible(camera.position, frustum, mFoliageVisible);
			if (mFoliageVisible.Count == 0)
				continue;
			let proxy = foliage.Proxy;
			let material = foliage.ActiveMaterial;
			let key = MakeKey(proxy, mesh, material);
			let meshRadius = mesh.Bounds.Extents.Length;
			let shadows = castShadows && foliage.castShadows;
			for (let index in mFoliageVisible)
			{
				RenderItem item;
				item.key = key;
				item.mesh = mesh;
				item.renderer = proxy;
				item.material = material;
				Color tint;
				float scale;
				item.world = foliage.WorldOf(index, out tint, out scale);
				item.tint = tint;
				item.center = .(item.world.m[12], item.world.m[13] + mesh.Bounds.Center.y * scale, item.world.m[14]);
				item.radius = meshRadius * scale;
				mFoliageItems.Add(item);
				if (shadows && (item.center - camera.position).Length - item.radius < shadowRange)
					mShadowItems.Add(item);
			}
		}
		Wind.Gather(scene, camera.position, out mWind, ref mWindZone, ref mWindPush);
		FoliageBender.Gather(scene, camera.position, ref mBender, ref mBenderPush);
		VisibleRenderers = (int32)(mItems.Count + mViewmodelItems.Count);
		mItems.Sort(scope (a, b) => a.key <=> b.key);
		mViewmodelItems.Sort(scope (a, b) => a.key <=> b.key);
		mShadowItems.Sort(scope (a, b) => a.key <=> b.key);

		// ---- shadow cascades ----
		if (castShadows)
		{
			ComputeCascades(camera, lightDirection, env.shadowDistance);
			for (int cascade < RenderResources.CascadeCount)
			{
				let view = (uint16)(ViewBase + cascade);
				let tile = RenderResources.ShadowTileSize;
				bgfx.set_view_name(view, "Shadow", 6);
				bgfx.set_view_frame_buffer(view, RenderResources.ShadowFrameBuffer);
				bgfx.set_view_rect(view, (int16)((cascade % 2) * tile), (int16)((cascade / 2) * tile), (uint16)tile, (uint16)tile, 0, 1);
				bgfx.set_view_clear(view, 0x0002, 0, 1.0f, 0);
				bgfx.set_view_transform(view, &mCascadeView[cascade], &mCascadeProj[cascade]);
				bgfx.touch(view);
				SubmitShadowCascade(view, cascade);
			}
			mShadowParams = .(1.0f / RenderResources.ShadowAtlasSize, 0.0005f, 1.0f, mCascadeRadius[0] * 2.0f / RenderResources.ShadowTileSize * 1.5f);
		}
		else
		{
			mShadowParams = .(1.0f / RenderResources.ShadowAtlasSize, 0, 0, 0);
			mCascadeSplits = .(0, 0, 0, 0);
		}

		// ---- HDR scene ----
		let sceneView = (uint16)(ViewBase + 4);
		var viewMatrix = camera.view;
		var projMatrix = camera.projection;
		bgfx.set_view_name(sceneView, "Scene", 5);
		bgfx.set_view_frame_buffer(sceneView, mSceneFb);
		bgfx.set_view_rect(sceneView, 0, 0, (uint16)mWidth, (uint16)mHeight, 0, 1);
		bgfx.set_view_clear(sceneView, 0x0003, 0x000000ff, 1.0f, 0);
		bgfx.set_view_transform(sceneView, &viewMatrix, &projMatrix);
		bgfx.touch(sceneView);

		SubmitSky(sceneView, env);
		SubmitMeshes(sceneView, mItems);
		SubmitMeshes(sceneView, mFoliageItems);
		SubmitParticles(sceneView, scene, frustum);
		SubmitLines(sceneView, DebugDraw.Lines);
		if (DrawGizmos)
		{
			SubmitLines(sceneView, Gizmos.Triangles, true);
			SubmitLines(sceneView, Gizmos.Lines);
		}

		// ---- see-through geometry: its own view so draws stay in back-to-front order ----
		if (mTransparentItems.Count > 0)
		{
			let transparentView = (uint16)(ViewBase + 5);
			bgfx.set_view_name(transparentView, "Transparent", 11);
			bgfx.set_view_frame_buffer(transparentView, mSceneFb);
			bgfx.set_view_rect(transparentView, 0, 0, (uint16)mWidth, (uint16)mHeight, 0, 1);
			bgfx.set_view_clear(transparentView, 0, 0, 1.0f, 0);
			bgfx.set_view_transform(transparentView, &viewMatrix, &projMatrix);
			bgfx.set_view_mode(transparentView, .Sequential);
			let eye = camera.position;
			mTransparentItems.Sort(scope (a, b) => (b.center - eye).LengthSquared <=> (a.center - eye).LengthSquared);
			for (int i < mTransparentItems.Count)
				SubmitBatch(transparentView, mTransparentItems, i, 1, false, true);
		}

		// ---- the viewmodel: over everything, with its own field of view and near clip ----
		if (mViewmodelItems.Count + mViewmodelTransparent.Count > 0)
		{
			let viewmodelView = (uint16)(ViewBase + 6);
			var viewmodelProjection = camera.viewmodelProjection;
			bgfx.set_view_name(viewmodelView, "Viewmodel", 9);
			bgfx.set_view_frame_buffer(viewmodelView, mSceneFb);
			bgfx.set_view_rect(viewmodelView, 0, 0, (uint16)mWidth, (uint16)mHeight, 0, 1);
			// Depth only: the world stays in the picture, and nothing in it can hide the viewmodel.
			bgfx.set_view_clear(viewmodelView, 0x0002, 0, 1.0f, 0);
			bgfx.set_view_transform(viewmodelView, &viewMatrix, &viewmodelProjection);
			// Solid first, then see-through parts back to front, in that order.
			bgfx.set_view_mode(viewmodelView, .Sequential);
			bgfx.touch(viewmodelView);
			SubmitMeshes(viewmodelView, mViewmodelItems);
			let eye = camera.position;
			mViewmodelTransparent.Sort(scope (a, b) => (b.center - eye).LengthSquared <=> (a.center - eye).LengthSquared);
			for (int i < mViewmodelTransparent.Count)
				SubmitBatch(viewmodelView, mViewmodelTransparent, i, 1, false, true);
		}

		// ---- screen effects: ambient occlusion, depth of field, motion blur (docs/post-processing.md) ----
		// Each reads the picture so far and writes the next one; bloom and the tonemap read the last.
		var picture = mSceneColor;
		// The scene sets how much of each; the player's settings (ScreenEffects) can turn each off.
		let ao = ScreenEffects.AmbientOcclusion && ShowAmbientOcclusion && env.ambientOcclusion > 0.001f;
		let dof = ScreenEffects.DepthOfField && ShowDepthOfField && env.depthOfField > 0.001f;
		let motionAmount = Math.Clamp(env.motionBlur, 0.0f, 1.0f) * Math.Clamp(ScreenEffects.MotionBlurAmount, 0.0f, 2.0f);
		let motion = ScreenEffects.MotionBlur && ShowMotionBlur && motionAmount > 0.001f;
		let worldViewProj = camera.projection * camera.view;
		if (ao || dof || motion)
		{
			EnsureEffectTargets();
			SetPostCamera(camera);
			SubmitDepthPass((uint16)(ViewBase + cDepthView), camera);
			int next = 0;
			if (ao)
			{
				Vector4 aoParams = .(Math.Max(env.occlusionRadius, 0.05f), Math.Clamp(env.ambientOcclusion, 0.0f, 2.0f), 1.0f / mWidth, 1.0f / mHeight);
				SetPostUniforms();
				bgfx.set_uniform(RenderResources.uAoParams, &aoParams, 1);
				bgfx.set_texture(0, RenderResources.sDepth, mDepthColor, uint32.MaxValue);
				EffectPass((uint16)(ViewBase + cAoView), "Ambient occlusion", mAoFb, mHalfWidth, mHalfHeight, RenderResources.AoProgram);

				Vector4 applyParams = .(0, 0, 1.0f / mHalfWidth, 1.0f / mHalfHeight);
				SetPostUniforms();
				bgfx.set_uniform(RenderResources.uAoParams, &applyParams, 1);
				bgfx.set_texture(0, RenderResources.sColor, picture, uint32.MaxValue);
				bgfx.set_texture(1, RenderResources.sAo, mAoColor, uint32.MaxValue);
				bgfx.set_texture(2, RenderResources.sDepth, mDepthColor, uint32.MaxValue);
				EffectPass((uint16)(ViewBase + cAoApplyView), "Occlusion apply", mPostFb[next], mWidth, mHeight, RenderResources.AoApplyProgram);
				picture = mPostColor[next];
				next ^= 1;
			}
			if (dof)
			{
				Vector4 dofParams = .(env.autoFocus ? -1.0f : Math.Max(env.focusDistance, 0.0f), Math.Max(env.focusRange, 0.01f),
					Math.Clamp(env.depthOfField, 0.0f, 2.0f) * SceneEnvironment.DepthOfFieldReach, (float)mHeight / mWidth);
				SetPostUniforms();
				bgfx.set_uniform(RenderResources.uDofParams, &dofParams, 1);
				bgfx.set_texture(0, RenderResources.sColor, picture, uint32.MaxValue);
				bgfx.set_texture(1, RenderResources.sDepth, mDepthColor, uint32.MaxValue);
				EffectPass((uint16)(ViewBase + cDofBlurView), "Depth of field blur", mDofFb, mHalfWidth, mHalfHeight, RenderResources.DofBlurProgram);

				SetPostUniforms();
				bgfx.set_uniform(RenderResources.uDofParams, &dofParams, 1);
				bgfx.set_texture(0, RenderResources.sColor, picture, uint32.MaxValue);
				bgfx.set_texture(1, RenderResources.sDepth, mDepthColor, uint32.MaxValue);
				bgfx.set_texture(2, RenderResources.sBlur, mDofColor, uint32.MaxValue);
				EffectPass((uint16)(ViewBase + cDofCombineView), "Depth of field", mPostFb[next], mWidth, mHeight, RenderResources.DofCombineProgram);
				picture = mPostColor[next];
				next ^= 1;
			}
			if (motion)
			{
				// A cut (a respawn, a new camera) is not a movement to smear.
				var previous = (mHasPrev && (camera.position - mPrevPosition).Length < 5) ? mPrevViewProj : worldViewProj;
				Vector4 motionParams = .(motionAmount, 0.06f, 0, 0);
				SetPostUniforms();
				bgfx.set_uniform(RenderResources.uMotionParams, &motionParams, 1);
				bgfx.set_uniform(RenderResources.uPrevViewProj, &previous, 1);
				bgfx.set_texture(0, RenderResources.sColor, picture, uint32.MaxValue);
				bgfx.set_texture(1, RenderResources.sDepth, mDepthColor, uint32.MaxValue);
				EffectPass((uint16)(ViewBase + cMotionView), "Motion blur", mPostFb[next], mWidth, mHeight, RenderResources.MotionBlurProgram);
				picture = mPostColor[next];
				next ^= 1;
			}
		}
		mPrevViewProj = worldViewProj;
		mPrevPosition = camera.position;
		mHasPrev = true;

		// ---- bloom: keep what is bright at a quarter size, blur it across and down ----
		let bloom = Math.Max(env.bloom, 0);
		if (bloom > 0.001f)
		{
			void Pass(uint16 view, StringView name, bgfx.FrameBufferHandle target, bgfx.TextureHandle source, bgfx.ProgramHandle program, Vector4 parameters)
			{
				var values = parameters;
				bgfx.set_view_name(view, name.Ptr, (int32)name.Length);
				bgfx.set_view_frame_buffer(view, target);
				bgfx.set_view_rect(view, 0, 0, (uint16)mBloomWidth, (uint16)mBloomHeight, 0, 1);
				bgfx.set_view_clear(view, 0, 0, 1.0f, 0);
				bgfx.set_uniform(RenderResources.uBloomParams, &values, 1);
				bgfx.set_texture(0, RenderResources.sColor, source, uint32.MaxValue);
				SubmitFullscreen(view, program, Gfx.StateWriteRGB | Gfx.StateWriteA);
			}
			let threshold = Math.Max(env.bloomThreshold, 0);
			Pass((uint16)(ViewBase + cBloomView), "Bloom bright", mBloomFb[0], picture, RenderResources.BloomDownProgram, .(threshold, Math.Max(threshold * 0.5f, 0.05f), 1.0f / mWidth, 1.0f / mHeight));
			Pass((uint16)(ViewBase + cBloomView + 1), "Bloom across", mBloomFb[1], mBloomColor[0], RenderResources.BloomBlurProgram, .(0, 0, 1.0f / mBloomWidth, 0));
			Pass((uint16)(ViewBase + cBloomView + 2), "Bloom down", mBloomFb[0], mBloomColor[1], RenderResources.BloomBlurProgram, .(0, 0, 0, 1.0f / mBloomHeight));
		}

		// ---- tonemap resolve, with colour grading ----
		let postView = (uint16)(ViewBase + cTonemapView);
		bgfx.set_view_name(postView, "Tonemap", 7);
		bgfx.set_view_frame_buffer(postView, mOutputFb);
		bgfx.set_view_rect(postView, 0, 0, (uint16)mOutWidth, (uint16)mOutHeight, 0, 1);
		bgfx.set_view_clear(postView, 0, 0, 1.0f, 0);
		Vector4 postParams = .(env.exposure * Math.Clamp(ScreenEffects.Brightness, 0.25f, 4.0f), Math.Max(env.vignette, 0), Math.Max(env.saturation, 0), bloom > 0.001f ? bloom : 0);
		bgfx.set_uniform(RenderResources.uPostParams, &postParams, 1);
		let lookup = PostProcess.GetLookup(env.colorLookup, let lookupSize);
		Vector4 gradeParams = .(Math.Max(env.contrast, 0), Math.Clamp(env.temperature, -1.0f, 1.0f), Math.Clamp(env.tint, -1.0f, 1.0f), Math.Clamp(env.colorLookupStrength, 0.0f, 1.0f));
		let filter = Linear(env.colorFilter);
		Vector4 gradeFilter = .(filter.x, filter.y, filter.z, (float)lookupSize);
		bgfx.set_uniform(RenderResources.uGradeParams, &gradeParams, 1);
		bgfx.set_uniform(RenderResources.uGradeFilter, &gradeFilter, 1);
		bgfx.set_texture(0, RenderResources.sColor, picture, uint32.MaxValue);
		// With no bloom the sampler still needs something; its contribution is multiplied by zero.
		bgfx.set_texture(1, RenderResources.sBloom, bloom > 0.001f ? mBloomColor[0] : picture, uint32.MaxValue);
		bgfx.set_texture(2, RenderResources.sLut, lookup, uint32.MaxValue);
		SubmitFullscreen(postView, RenderResources.TonemapProgram, Gfx.StateWriteRGB | Gfx.StateWriteA);
	}

	/// The camera's frame for the screen effects' shaders (Engine/shaders/post.sh): its right, up and forward in the
	/// world (the rows of the view matrix), the projection's spread, and which way texture v runs.
	void SetPostCamera(CameraData camera)
	{
		let view = camera.view;
		let projection = camera.projection;
		mPostRight = .(view.m[0], view.m[4], view.m[8], 1.0f / projection.m[0]);
		mPostUp = .(view.m[1], view.m[5], view.m[9], 1.0f / projection.m[5]);
		mPostForward = .(view.m[2], view.m[6], view.m[10], camera.orthographic ? 1 : 0);
		mPostEye = .(camera.position, Gfx.OriginBottomLeft ? 1 : -1);
	}

	void SetPostUniforms()
	{
		bgfx.set_uniform(RenderResources.uPostRight, &mPostRight, 1);
		bgfx.set_uniform(RenderResources.uPostUp, &mPostUp, 1);
		bgfx.set_uniform(RenderResources.uPostForward, &mPostForward, 1);
		bgfx.set_uniform(RenderResources.uPostEye, &mPostEye, 1);
	}

	/// One full-screen step of the screen effects into a target (its uniforms and textures already set).
	void EffectPass(uint16 view, StringView name, bgfx.FrameBufferHandle target, int32 width, int32 height, bgfx.ProgramHandle program)
	{
		bgfx.set_view_name(view, name.Ptr, (int32)name.Length);
		bgfx.set_view_frame_buffer(view, target);
		bgfx.set_view_rect(view, 0, 0, (uint16)width, (uint16)height, 0, 1);
		bgfx.set_view_clear(view, 0, 0, 1.0f, 0);
		SubmitFullscreen(view, program, Gfx.StateWriteRGB | Gfx.StateWriteA);
	}

	/// The depth pass: how far in front of the camera each solid surface is, for the screen effects. The world's
	/// solid objects first, then the viewmodel's over them, marked -1 so the effects leave it alone. Nothing drawn is
	/// the sky, 60000 (SKY_DEPTH in post.sh).
	void SubmitDepthPass(uint16 view, CameraData camera)
	{
		var viewMatrix = camera.view;
		var projMatrix = camera.projection;
		bgfx.set_palette_color_rgba32f(cDepthPalette, 60000.0f, 0, 0, 1);
		bgfx.set_view_name(view, "Depth", 5);
		bgfx.set_view_frame_buffer(view, mDepthFb);
		bgfx.set_view_rect(view, 0, 0, (uint16)mWidth, (uint16)mHeight, 0, 1);
		bgfx.set_view_clear_mrt(view, 0x0003, 1.0f, 0, cDepthPalette, cDepthPalette, cDepthPalette, cDepthPalette, cDepthPalette, cDepthPalette, cDepthPalette, cDepthPalette);
		bgfx.set_view_transform(view, &viewMatrix, &projMatrix);
		bgfx.set_view_mode(view, .Sequential);
		bgfx.touch(view);
		let worldViewProj = projMatrix * viewMatrix;
		let viewmodelViewProj = camera.viewmodelProjection * viewMatrix;
		for (int pass < 3)
		{
			let items = pass == 0 ? mItems : (pass == 1 ? mViewmodelItems : mFoliageItems);
			int start = 0;
			while (start < items.Count)
			{
				int end = start + 1;
				while (end < items.Count && items[end].mesh == items[start].mesh && items[end].material == items[start].material && items[end].renderer.windSway == items[start].renderer.windSway)
					end++;
				SubmitDepthBatch(view, items, start, end - start, pass == 1 ? viewmodelViewProj : worldViewProj, pass == 1);
				start = end;
			}
		}
	}

	const uint8 cDepthPalette = 15;

	void SubmitDepthBatch(uint16 view, List<RenderItem> items, int start, int count, Matrix4 viewProj, bool viewmodel)
	{
		let stride = (uint16)sizeof(InstanceData);
		let drawCount = Math.Min(count, (int)bgfx.get_avail_instance_data_buffer((uint32)count, stride));
		if (drawCount <= 0)
			return;
		bgfx.InstanceDataBuffer buffer = default;
		bgfx.alloc_instance_data_buffer(&buffer, (uint32)drawCount, stride);
		let data = (InstanceData*)buffer.data;
		for (int i < drawCount)
		{
			data[i].world = items[start + i].world;
			data[i].color = .(1, 1, 1, 1);
		}
		let first = items[start];
		let mesh = first.mesh;
		if (mesh.IsDynamic)
			bgfx.set_dynamic_vertex_buffer(0, mesh.DynamicBuffer, 0, (uint32)mesh.VertexCount);
		else
			bgfx.set_vertex_buffer(0, mesh.VertexBuffer, 0, (uint32)mesh.VertexCount);
		bgfx.set_index_buffer(mesh.IndexBuffer, 0, (uint32)mesh.IndexCount);
		bgfx.set_instance_data_buffer(&buffer, 0, (uint32)drawCount);
		var matrix = viewProj;
		Vector4 depthParams = .(viewmodel ? 1 : 0, 0, 0, 0);
		SetWindUniforms(first.renderer.windSway);
		bgfx.set_uniform(RenderResources.uDepthViewProj, &matrix, 1);
		bgfx.set_uniform(RenderResources.uDepthParams, &depthParams, 1);
		uint64 cull = Gfx.StateCullCcw;
		if (first.material != null && first.material.doubleSided)
			cull = 0;
		// The viewmodel is over everything, so it is not depth tested.
		uint64 depth = Gfx.StateWriteZ | Gfx.StateDepthLess;
		if (viewmodel)
			depth = 0;
		bgfx.set_state(Gfx.StateWriteRGB | Gfx.StateWriteA | depth | cull, 0);
		bgfx.submit(view, RenderResources.DepthProgram, 0, 0xff);
	}

	/// Whether an object is drawn in the viewmodel pass for this camera (Camera.viewmodelLayer) rather than with the world.
	public static bool DrawsAsViewmodel(CameraData camera, GameObject gameObject) => camera.hasViewmodel && gameObject != null && gameObject.Layer == camera.viewmodelLayer;

	static uint64 MakeKey(MeshRenderer renderer, Mesh mesh, Material material)
	{
		uint64 key = (uint64)(int)Internal.UnsafeCastToPtr(mesh);
		// With a material, the material is what draws differ by.
		let shared = material;
		key = key * 1099511628211 ^ (uint64)renderer.TextureOverride.idx;
		key = key * 1099511628211 ^ (uint64)(uint32)(renderer.windSway * 100.0f);
		if (shared != null)
		{
			key = key * 1099511628211 ^ (uint64)(int)Internal.UnsafeCastToPtr(shared);
			key = key * 1099511628211 ^ (uint64)shared.Revision;
			return key;
		}
		key = key * 1099511628211 ^ (uint64)(uint32)(renderer.metallic * 255.0f);
		key = key * 1099511628211 ^ (uint64)(uint32)(renderer.roughness * 255.0f);
		key = key * 1099511628211 ^ (uint64)((renderer.flatShading ? 1 : 0) | (renderer.unlit ? 2 : 0));
		key = key * 1099511628211 ^ (uint64)renderer.ActiveTexture.idx;
		if (renderer.emissiveIntensity > 0)
		{
			key = key * 1099511628211 ^ (uint64)renderer.emissive.ToABGR();
			key = key * 1099511628211 ^ (uint64)(uint32)(renderer.emissiveIntensity * 64.0f);
		}
		return key;
	}

	void ComputeCascades(CameraData camera, Vector3 lightDirection, float shadowDistance)
	{
		let near = Math.Max(camera.near, 0.05f);
		let far = Math.Max(Math.Min(camera.far, shadowDistance), near + 1.0f);
		float[RenderResources.CascadeCount + 1] splits = default;
		splits[0] = near;
		for (int i = 1; i <= RenderResources.CascadeCount; i++)
		{
			let p = (float)i / RenderResources.CascadeCount;
			let logSplit = near * Math.Pow(far / near, p);
			let uniformSplit = near + (far - near) * p;
			splits[i] = Mathf.Lerp(uniformSplit, logSplit, 0.8f);
		}
		if (camera.orthographic)
		{
			// One cascade covers an orthographic view; clip-space w is constant there.
			mCascadeSplits = .(1.0e9f, 1.0e9f, 1.0e9f, 1.0e9f);
			for (int i = 1; i <= RenderResources.CascadeCount; i++)
				splits[i] = far;
		}
		else
		{
			mCascadeSplits = .(splits[1], splits[2], splits[3], splits[4]);
		}

		let v = camera.view.m;
		let camRight = Vector3(v[0], v[4], v[8]);
		let camUp = Vector3(v[1], v[5], v[9]);
		let camForward = Vector3(v[2], v[6], v[10]);
		let tanHalf = Math.Tan(camera.fieldOfView * 0.5f * Mathf.Deg2Rad);

		let lightForward = lightDirection.Normalized;
		var lightRight = Vector3.Cross(Vector3.Up, lightForward);
		if (lightRight.LengthSquared < 1.0e-6f)
			lightRight = Vector3.Cross(Vector3.Right, lightForward);
		lightRight = lightRight.Normalized;
		let lightUp = Vector3.Cross(lightForward, lightRight);
		mLightRight = lightRight;
		mLightUp = lightUp;

		let casterDistance = 150.0f;
		for (int cascade < RenderResources.CascadeCount)
		{
			let zn = splits[cascade];
			let zf = splits[cascade + 1];
			Vector3[8] corners = default;
			for (int i < 8)
			{
				let z = (i & 4) != 0 ? zf : zn;
				float halfH, halfW;
				if (camera.orthographic)
				{
					halfH = camera.orthographicSize;
					halfW = halfH * camera.aspect;
				}
				else
				{
					halfH = z * tanHalf;
					halfW = halfH * camera.aspect;
				}
				corners[i] = camera.position + camForward * z
					+ camRight * ((i & 1) != 0 ? halfW : -halfW)
					+ camUp * ((i & 2) != 0 ? halfH : -halfH);
			}
			var center = Vector3.Zero;
			for (int i < 8)
				center = center + corners[i];
			center = center / 8.0f;
			float radius = 0;
			for (int i < 8)
				radius = Math.Max(radius, (corners[i] - center).Length);
			radius = Math.Ceiling(radius * 8.0f) / 8.0f;

			// Snap to shadow texels so the cascade does not shimmer as the camera moves.
			let texel = radius * 2.0f / RenderResources.ShadowTileSize;
			let cx = Vector3.Dot(center, lightRight);
			let cy = Vector3.Dot(center, lightUp);
			center = center + lightRight * (Math.Floor(cx / texel) * texel - cx) + lightUp * (Math.Floor(cy / texel) * texel - cy);

			let eye = center - lightForward * (radius + casterDistance);
			let lightView = Matrix4.LookAt(eye, center, lightUp);
			let lightProj = Matrix4.Ortho(-radius, radius, -radius, radius, 0.0f, radius * 2.0f + casterDistance, Gfx.HomogeneousDepth);
			mCascadeView[cascade] = lightView;
			mCascadeProj[cascade] = lightProj;
			mCascadeViewProj[cascade] = lightProj * lightView;
			mCascadeCenter[cascade] = center;
			mCascadeRadius[cascade] = radius;

			// Clip space to atlas UV for this cascade's tile.
			let tx = (float)(cascade % 2);
			let ty = (float)(cascade / 2);
			Matrix4 bias = default;
			bias.m[0] = 0.25f;
			bias.m[12] = 0.25f + tx * 0.5f;
			if (Gfx.OriginBottomLeft)
			{
				bias.m[5] = 0.25f;
				bias.m[13] = 0.75f - ty * 0.5f;
			}
			else
			{
				bias.m[5] = -0.25f;
				bias.m[13] = 0.25f + ty * 0.5f;
			}
			bias.m[10] = Gfx.HomogeneousDepth ? 0.5f : 1.0f;
			bias.m[14] = Gfx.HomogeneousDepth ? 0.5f : 0.0f;
			bias.m[15] = 1.0f;
			mShadowMtx[cascade] = bias * mCascadeViewProj[cascade];
		}
	}

	void SubmitShadowCascade(uint16 view, int cascade)
	{
		let center = mCascadeCenter[cascade];
		let radius = mCascadeRadius[cascade];
		List<RenderItem> visible = scope .();
		for (let item in mShadowItems)
		{
			let offset = item.center - center;
			if (Mathf.Abs(Vector3.Dot(offset, mLightRight)) > radius + item.radius)
				continue;
			if (Mathf.Abs(Vector3.Dot(offset, mLightUp)) > radius + item.radius)
				continue;
			visible.Add(item);
		}
		int start = 0;
		while (start < visible.Count)
		{
			int end = start + 1;
			while (end < visible.Count && visible[end].mesh == visible[start].mesh && visible[end].renderer.windSway == visible[start].renderer.windSway)
				end++;
			SubmitBatch(view, visible, start, end - start, true);
			start = end;
		}
	}

	void SubmitMeshes(uint16 view, List<RenderItem> items)
	{
		int start = 0;
		while (start < items.Count)
		{
			int end = start + 1;
			while (end < items.Count && items[end].key == items[start].key)
				end++;
			SubmitBatch(view, items, start, end - start, false);
			start = end;
		}
	}

	void SubmitBatch(uint16 view, List<RenderItem> items, int start, int count, bool shadowPass, bool transparent = false)
	{
		let stride = (uint16)sizeof(InstanceData);
		let available = (int)bgfx.get_avail_instance_data_buffer((uint32)count, stride);
		let drawCount = Math.Min(count, available);
		if (drawCount <= 0)
			return;
		bgfx.InstanceDataBuffer buffer = default;
		bgfx.alloc_instance_data_buffer(&buffer, (uint32)drawCount, stride);
		let data = (InstanceData*)buffer.data;
		for (int i < drawCount)
		{
			let item = items[start + i];
			data[i].world = item.world;
			data[i].color = .(item.renderer.color.r * item.tint.r, item.renderer.color.g * item.tint.g, item.renderer.color.b * item.tint.b, item.renderer.color.a * item.tint.a);
			let tint = item.material;
			if (tint != null)
				data[i].color = .(data[i].color.r * tint.color.r, data[i].color.g * tint.color.g, data[i].color.b * tint.color.b, data[i].color.a * tint.color.a);
		}

		let first = items[start];
		let mesh = first.mesh;
		if (mesh.IsDynamic)
			bgfx.set_dynamic_vertex_buffer(0, mesh.DynamicBuffer, 0, (uint32)mesh.VertexCount);
		else
			bgfx.set_vertex_buffer(0, mesh.VertexBuffer, 0, (uint32)mesh.VertexCount);
		bgfx.set_index_buffer(mesh.IndexBuffer, 0, (uint32)mesh.IndexCount);
		bgfx.set_instance_data_buffer(&buffer, 0, (uint32)drawCount);

		if (shadowPass)
		{
			SetWindUniforms(first.renderer.windSway);
			bgfx.set_state(Gfx.StateWriteZ | Gfx.StateDepthLess, 0);
			bgfx.submit(view, RenderResources.ShadowProgram, 0, 0xff);
			return;
		}

		let renderer = first.renderer;
		SetFrameUniforms();
		// A material, when the renderer (or this part) has one, replaces the renderer's own surface settings.
		let shared = first.material;
		Vector4 material = .(renderer.metallic, renderer.roughness, renderer.flatShading ? 1 : 0, renderer.unlit ? 1 : 0);
		var emissive = Linear(renderer.emissive, renderer.emissiveIntensity);
		Vector4 uvTransform = .(1, 1, 0, 0);
		Vector4 surface = .(0, Time.RealTime, renderer.emissiveFromColor ? 1 : 0, 0);
		Vector4[ShaderAsset.MaxValues] values = default;
		StringView[ShaderAsset.MaxTextures] textures = default;
		Vector4 pbr = .(0, 0, 0, 0);
		StringView normalMap = "", metalRoughMap = "", occlusionMap = "", emissiveMap = "";
		var texture = Gfx.WhiteTexture;
		var program = RenderResources.MeshProgram;
		uint64 cull = Gfx.StateCullCcw;
		if (shared != null)
		{
			material = .(shared.metallic, shared.roughness, shared.flatShading ? 1 : 0, shared.unlit ? 1 : 0);
			emissive = Linear(shared.emissive, shared.emissiveIntensity);
			uvTransform = .(shared.tiling.x, shared.tiling.y, shared.offset.x, shared.offset.y);
			if (shared.blend == .Cutout)
				surface.x = Math.Max(shared.cutoff, 0.001f);
			if (shared.doubleSided)
				cull = 0;
			texture = shared.MainTexture;
			normalMap = shared.normalMap;
			metalRoughMap = shared.metallicRoughnessMap;
			occlusionMap = shared.occlusionMap;
			emissiveMap = shared.emissiveMap;
			pbr = .(normalMap.IsEmpty ? 0 : Math.Max(shared.normalStrength, 0.001f), metalRoughMap.IsEmpty ? 0 : 1, occlusionMap.IsEmpty ? 0 : shared.occlusionStrength, emissiveMap.IsEmpty ? 0 : 1);
			shared.GatherValues(ref values, ref textures);
			let custom = shared.Shader;
			if (custom != null)
			{
				let compiled = custom.Program;
				if (compiled.idx != uint16.MaxValue)
					program = compiled;
			}
		}
		else
			texture = renderer.ActiveTexture;
		if (renderer.TextureOverride.idx != uint16.MaxValue)
			texture = renderer.TextureOverride;
		bgfx.set_uniform(RenderResources.uMaterial, &material, 1);
		bgfx.set_uniform(RenderResources.uEmissive, &emissive, 1);
		bgfx.set_uniform(RenderResources.uUvTransform, &uvTransform, 1);
		bgfx.set_uniform(RenderResources.uSurface, &surface, 1);
		Vector4 sway = .(renderer.windSway, 0, 0, 0);
		bgfx.set_uniform(RenderResources.uSway, &sway, 1);
		bgfx.set_uniform(RenderResources.uParams, &values, ShaderAsset.MaxValues);
		bgfx.set_texture(0, RenderResources.sAlbedo, texture, uint32.MaxValue);
		bgfx.set_texture(1, RenderResources.sShadowMap, RenderResources.ShadowMap, uint32.MaxValue);
		bgfx.set_texture(2, RenderResources.sTexture1, Assets.GetTexture(textures[0]), uint32.MaxValue);
		bgfx.set_texture(3, RenderResources.sTexture2, Assets.GetTexture(textures[1]), uint32.MaxValue);
		bgfx.set_uniform(RenderResources.uPbr, &pbr, 1);
		bgfx.set_texture(4, RenderResources.sNormalMap, Assets.GetTexture(normalMap), uint32.MaxValue);
		bgfx.set_texture(5, RenderResources.sMetalRoughMap, Assets.GetTexture(metalRoughMap), uint32.MaxValue);
		bgfx.set_texture(6, RenderResources.sOcclusionMap, Assets.GetTexture(occlusionMap), uint32.MaxValue);
		bgfx.set_texture(7, RenderResources.sEmissiveMap, Assets.GetTexture(emissiveMap), uint32.MaxValue);
		if (transparent)
			bgfx.set_state(Gfx.StateWriteRGB | Gfx.StateDepthLess | cull | Gfx.StateMsaa | Gfx.StateBlendAlpha, 0);
		else
			bgfx.set_state(Gfx.StateWriteRGB | Gfx.StateWriteA | Gfx.StateWriteZ | Gfx.StateDepthLess | cull | Gfx.StateMsaa, 0);
		bgfx.submit(view, program, 0, 0xff);

		DrawCalls++;
		Instances += (int32)drawCount;
		Triangles += (int32)drawCount * mesh.IndexCount / 3;
	}

	/// Each particle system is one instanced draw of its mesh.
	void SubmitParticles(uint16 view, Scene scene, Frustum frustum)
	{
		let stride = (uint16)sizeof(InstanceData);
		for (let system in scene.Particles)
		{
			if (!system.IsActiveAndEnabled || system.AliveCount == 0 || !system.GameObject.InActiveWorld)
				continue;
			let mesh = Assets.GetMesh(system.mesh);
			if (mesh == null || !mesh.HasGpuData || !frustum.Intersects(system.WorldBounds))
				continue;
			let count = Math.Min(system.AliveCount, (int32)bgfx.get_avail_instance_data_buffer((uint32)system.AliveCount, stride));
			if (count <= 0)
				continue;
			bgfx.InstanceDataBuffer buffer = default;
			bgfx.alloc_instance_data_buffer(&buffer, (uint32)count, stride);
			system.WriteInstances((Matrix4*)buffer.data, count, (int32)stride);

			bgfx.set_vertex_buffer(0, mesh.VertexBuffer, 0, (uint32)mesh.VertexCount);
			bgfx.set_index_buffer(mesh.IndexBuffer, 0, (uint32)mesh.IndexCount);
			bgfx.set_instance_data_buffer(&buffer, 0, (uint32)count);
			SetFrameUniforms();
			Vector4 material = .(0, 0.9f, 1, system.unlit ? 1 : 0);
			Vector4 emissive = .(0, 0, 0, 0);
			bgfx.set_uniform(RenderResources.uMaterial, &material, 1);
			bgfx.set_uniform(RenderResources.uEmissive, &emissive, 1);
			Vector4 uvTransform = .(1, 1, 0, 0);
			Vector4 surface = .(0, Time.RealTime, 0, 0);
			Vector4[ShaderAsset.MaxValues] values = default;
			bgfx.set_uniform(RenderResources.uUvTransform, &uvTransform, 1);
			bgfx.set_uniform(RenderResources.uSurface, &surface, 1);
			bgfx.set_uniform(RenderResources.uParams, &values, ShaderAsset.MaxValues);
			bgfx.set_texture(2, RenderResources.sTexture1, Gfx.WhiteTexture, uint32.MaxValue);
			bgfx.set_texture(3, RenderResources.sTexture2, Gfx.WhiteTexture, uint32.MaxValue);
			Vector4 pbr = .(0, 0, 0, 0);
			bgfx.set_uniform(RenderResources.uPbr, &pbr, 1);
			for (uint8 stage = 4; stage < 8; stage++)
				bgfx.set_texture(stage, stage == 4 ? RenderResources.sNormalMap : (stage == 5 ? RenderResources.sMetalRoughMap : (stage == 6 ? RenderResources.sOcclusionMap : RenderResources.sEmissiveMap)), Gfx.WhiteTexture, uint32.MaxValue);
			bgfx.set_texture(0, RenderResources.sAlbedo, Gfx.WhiteTexture, uint32.MaxValue);
			bgfx.set_texture(1, RenderResources.sShadowMap, RenderResources.ShadowMap, uint32.MaxValue);
			bgfx.set_state(Gfx.StateWriteRGB | Gfx.StateWriteA | Gfx.StateWriteZ | Gfx.StateDepthLess | Gfx.StateCullCcw | Gfx.StateMsaa, 0);
			bgfx.submit(view, RenderResources.MeshProgram, 0, 0xff);
			DrawCalls++;
			Instances += count;
			Triangles += count * mesh.IndexCount / 3;
		}
	}

	/// What the shadow and depth passes need to bend a draw in the wind as the lit pass does: the wind, the time and
	/// how far this draw sways.
	void SetWindUniforms(float amount)
	{
		Vector4 sway = .(amount, 0, 0, 0);
		Vector4 surface = .(0, Time.RealTime, 0, 0);
		bgfx.set_uniform(RenderResources.uSway, &sway, 1);
		bgfx.set_uniform(RenderResources.uSurface, &surface, 1);
		bgfx.set_uniform(RenderResources.uWind, &mWind, 1);
		bgfx.set_uniform(RenderResources.uWindZone, &mWindZone, 4);
		bgfx.set_uniform(RenderResources.uWindPush, &mWindPush, 4);
		bgfx.set_uniform(RenderResources.uBender, &mBender, 8);
		bgfx.set_uniform(RenderResources.uBenderPush, &mBenderPush, 8);
	}

	void SetFrameUniforms()
	{
		bgfx.set_uniform(RenderResources.uCamPos, &mCamPos, 1);
		bgfx.set_uniform(RenderResources.uSunDir, &mSunDir, 1);
		bgfx.set_uniform(RenderResources.uSunColor, &mSunColor, 1);
		bgfx.set_uniform(RenderResources.uAmbientSky, &mAmbientSky, 1);
		bgfx.set_uniform(RenderResources.uAmbientGround, &mAmbientGround, 1);
		bgfx.set_uniform(RenderResources.uFogColor, &mFogColor, 1);
		bgfx.set_uniform(RenderResources.uWind, &mWind, 1);
		bgfx.set_uniform(RenderResources.uWindZone, &mWindZone, 4);
		bgfx.set_uniform(RenderResources.uWindPush, &mWindPush, 4);
		bgfx.set_uniform(RenderResources.uBender, &mBender, 8);
		bgfx.set_uniform(RenderResources.uBenderPush, &mBenderPush, 8);
		bgfx.set_uniform(RenderResources.uLightPosRange, &mLightPosRange, RenderResources.MaxLights);
		bgfx.set_uniform(RenderResources.uLightColor, &mLightColor, RenderResources.MaxLights);
		bgfx.set_uniform(RenderResources.uLightDirSpot, &mLightDirSpot, RenderResources.MaxLights);
		bgfx.set_uniform(RenderResources.uLightParams, &mLightParams, RenderResources.MaxLights);
		bgfx.set_uniform(RenderResources.uLightCount, &mLightCount, 1);
		bgfx.set_uniform(RenderResources.uShadowMtx, &mShadowMtx, RenderResources.CascadeCount);
		bgfx.set_uniform(RenderResources.uCascadeSplits, &mCascadeSplits, 1);
		bgfx.set_uniform(RenderResources.uShadowParams, &mShadowParams, 1);
	}

	void SubmitSky(uint16 view, SceneEnvironment env)
	{
		var zenith = Linear(env.skyZenith);
		var horizon = Linear(env.skyHorizon);
		var ground = Linear(env.skyGround);
		bgfx.set_uniform(RenderResources.uCamPos, &mCamPos, 1);
		bgfx.set_uniform(RenderResources.uSunDir, &mSunDir, 1);
		bgfx.set_uniform(RenderResources.uSunColor, &mSunColor, 1);
		bgfx.set_uniform(RenderResources.uSkyZenith, &zenith, 1);
		bgfx.set_uniform(RenderResources.uSkyHorizon, &horizon, 1);
		bgfx.set_uniform(RenderResources.uSkyGround, &ground, 1);
		SubmitFullscreen(view, RenderResources.SkyProgram, Gfx.StateWriteRGB | Gfx.StateWriteA | Gfx.StateDepthLequal | Gfx.StateMsaa);
	}

	void SubmitFullscreen(uint16 view, bgfx.ProgramHandle program, uint64 state)
	{
		if (bgfx.get_avail_transient_vertex_buffer(3, &Gfx.ScreenLayout) < 3)
			return;
		bgfx.TransientVertexBuffer buffer = default;
		bgfx.alloc_transient_vertex_buffer(&buffer, 3, &Gfx.ScreenLayout);
		let vertices = (ScreenVertex*)buffer.data;
		// One oversized triangle covering the viewport; UV origin follows the backend's texture origin.
		let top = Gfx.OriginBottomLeft ? 1.0f : 0.0f;
		let bottom = Gfx.OriginBottomLeft ? 0.0f : 1.0f;
		vertices[0].position = .(-1, -1, 0);
		vertices[0].uv = .(0, bottom);
		vertices[1].position = .(-1, 3, 0);
		vertices[1].uv = .(0, bottom + (top - bottom) * 2.0f);
		vertices[2].position = .(3, -1, 0);
		vertices[2].uv = .(2, bottom);
		bgfx.set_transient_vertex_buffer(0, &buffer, 0, 3);
		bgfx.set_state(state, 0);
		bgfx.submit(view, program, 0, 0xff);
	}

	/// Draws a batch as line segments, or as unculled triangles that test depth without writing it.
	void SubmitLines(uint16 view, LineBatch batch, bool triangles = false)
	{
		let count = (uint32)batch.Vertices.Count;
		if (count == 0)
			return;
		var available = bgfx.get_avail_transient_vertex_buffer(count, &Gfx.LineLayout);
		available -= available % (triangles ? 3 : 2);
		if (available == 0)
			return;
		bgfx.TransientVertexBuffer buffer = default;
		bgfx.alloc_transient_vertex_buffer(&buffer, available, &Gfx.LineLayout);
		Internal.MemCpy(buffer.data, batch.Vertices.Ptr, (int)available * sizeof(LineVertex));
		bgfx.set_transient_vertex_buffer(0, &buffer, 0, available);
		bgfx.set_state(Gfx.StateWriteRGB | Gfx.StateWriteA | Gfx.StateDepthLequal | (triangles ? 0 : Gfx.StateLines) | Gfx.StateMsaa | Gfx.StateBlendAlpha, 0);
		bgfx.submit(view, RenderResources.LineProgram, 0, 0xff);
	}
}
