using System;
using System.Collections;
using System.IO;
using System.Threading;
using Tessera;
using Bgfx;

namespace Tessera.Editor;

/// The Graph tab's pictures of a shader graph: the whole surface lit on a ball, and each node's value on a ball of its
/// own, unlit. The graph's preview shader (ShaderGraphCode with previews) is compiled on another thread, for the
/// backend the editor draws with only, once the graph has stopped changing for a moment. All the balls are drawn in
/// one picture, a grid of cells, and each node shows its own cell of it. The picture is drawn again a few times a
/// second, so nodes that use Time move.
class ShaderGraphPreview
{
	/// RenderView.ViewCount views from here: after the reflection captures, before ImGui's (250).
	const uint16 ViewBase = 200;
	/// The picture's size of one cell, in pixels.
	public const int32 CellSize = 128;
	const int32 MaxCells = 100;
	/// How long the graph must stay unchanged before it is compiled, and how often it is looked at for changes.
	const double SettleSeconds = 0.35;
	const double CheckSeconds = 0.2;
	const double RedrawSeconds = 1.0 / 15;
	/// The preview shader's name: what its materials' Shader names, and what its compiled files are called.
	const String ShaderName = "tessera_graph_preview";

	RenderView mView ~ delete _;
	Scene mScene ~ delete _;
	Camera mCamera;
	List<MeshRenderer> mBalls = new .() ~ delete _;
	int32 mColumns = 1, mRows = 1;

	// The preview shader last written from the graph, and its node slots; what is compiling; what is shown.
	String mWritten = new .() ~ delete _;
	Dictionary<int32, int32> mWrittenSlots = new .() ~ delete _;
	String mCompiling = new .() ~ delete _;
	Dictionary<int32, int32> mCompilingSlots = new .() ~ delete _;
	Dictionary<int32, int32> mShownSlots = new .() ~ delete _;
	bool mHasPicture;
	double mWrittenAt, mCheckedAt, mDrawnAt;

	Thread mThread;
	bool mFinished;
	bool mSucceeded;
	String mLog = new .() ~ delete _;
	String mFolder = new .() ~ delete _;

	/// What went wrong the last time the graph was compiled, or empty.
	public String problem = new .() ~ delete _;

	public ~this()
	{
		if (mThread != null)
		{
			mThread.Join();
			delete mThread;
		}
	}

	/// The picture the cells are in (a bgfx texture), when there is one.
	public bool TryGetPicture(out uint16 texture)
	{
		texture = uint16.MaxValue;
		if (!mHasPicture || mView == null)
			return false;
		texture = mView.OutputTexture;
		return true;
	}

	/// Where a node's cell is in the picture (its texture coordinates); false when the node has none.
	public bool CellOf(int32 nodeId, out ImGui.Vec2 from, out ImGui.Vec2 to)
	{
		from = to = default;
		if (!mShownSlots.TryGetValue(nodeId, let slot))
			return false;
		Cell(slot, out from, out to);
		return true;
	}

	/// The cell of the whole surface, lit.
	public void SurfaceCell(out ImGui.Vec2 from, out ImGui.Vec2 to) => Cell(0, out from, out to);

	void Cell(int32 slot, out ImGui.Vec2 from, out ImGui.Vec2 to)
	{
		let column = slot % mColumns, row = slot / mColumns;
		from = .((float)column / mColumns, (float)row / mRows);
		to = .((float)(column + 1) / mColumns, (float)(row + 1) / mRows);
	}

	/// Called each frame the graph is on screen: notices changes, compiles once they settle, picks up a finished
	/// compile, and draws the picture again now and then.
	public void Update(NodeGraph graph)
	{
		if (!Gfx.Initialized)
			return;
		let now = Time.RealTime;
		if (now - mCheckedAt >= CheckSeconds)
		{
			mCheckedAt = now;
			let writer = scope ShaderGraphCode();
			let text = scope String();
			if (writer.Write(graph, text, true) && text != mWritten)
			{
				mWritten.Set(text);
				mWrittenSlots.Clear();
				for (let (node, slot) in writer.previewSlots)
					mWrittenSlots[node] = slot;
				mWrittenAt = now;
			}
			else if (!writer.problems.IsEmpty)
				problem.Set(writer.problems.Split('\n').GetNext().GetValueOrDefault());
		}
		Collect();
		if (mThread == null && !mWritten.IsEmpty && mWritten != mCompiling && now - mWrittenAt >= SettleSeconds)
			Start();
		if (mHasPicture && now - mDrawnAt >= RedrawSeconds)
		{
			mDrawnAt = now;
			Draw();
		}
	}

	/// Compiles the last written shader on another thread.
	void Start()
	{
		mCompiling.Set(mWritten);
		mCompilingSlots.Clear();
		for (let (node, slot) in mWrittenSlots)
			mCompilingSlots[node] = slot;
		if (mFolder.IsEmpty)
		{
			Path.GetTempPath(mFolder);
			mFolder.AppendF("/tessera-graph-preview-{}", (int)Platform.BfpProcess_GetCurrentId());
		}
		mLog.Clear();
		mFinished = false;
		let engineRoot = new String(Project.Current.EngineRoot);
		mThread = new Thread(new () =>
			{
				mSucceeded = ShaderCompiler.CompilePreview(engineRoot, mCompiling, ShaderName, mFolder, mLog);
				delete engineRoot;
				Interlocked.Store(ref mFinished, true);
			});
		mThread.Start(false);
	}

	/// Takes in a finished compile: the new program, and a ball for each node.
	void Collect()
	{
		if (mThread == null || !Interlocked.Load(ref mFinished))
			return;
		mThread.Join();
		DeleteAndNullify!(mThread);
		if (!mSucceeded)
		{
			let first = scope String();
			for (let line in mLog.Split('\n', .RemoveEmptyEntries))
			{
				first.Set(line);
				break;
			}
			problem.Set(first.IsEmpty ? "The preview did not compile." : first);
			return;
		}
		problem.Clear();
		let shader = ShaderAsset.FromCompiled(ShaderName, mCompiling, scope $"{mFolder}/{Gfx.ShaderFolder}");
		// Loaded now, before another compile can write over the files.
		if (shader.Program.idx == uint16.MaxValue)
		{
			problem.Set("The preview's compiled shader could not be loaded.");
			return;
		}
		mShownSlots.Clear();
		for (let (node, slot) in mCompilingSlots)
			mShownSlots[node] = slot;
		Layout(Math.Min(mShownSlots.Count + 1, MaxCells));
		mHasPicture = true;
		mDrawnAt = 0;
	}

	/// The scene the balls are in, made the first time.
	void EnsureScene()
	{
		if (mView != null)
			return;
		mView = new RenderView(ViewBase);
		mView.CapturesReflections = false;
		mView.ShowAmbientOcclusion = false;
		mView.ShowDepthOfField = false;
		mView.ShowMotionBlur = false;
		mScene = new Scene();
		mScene.Environment.ambientIntensity = 0.75f;
		mScene.Environment.fogDensity = 0;
		// A plain dark grey behind the balls, so that colours read against it as they do on the canvas.
		mScene.Environment.skyZenith = mScene.Environment.skyHorizon = mScene.Environment.skyGround = .(0.12f, 0.12f, 0.13f);
		mCamera = mScene.CreateGameObject("Preview Camera").AddComponent<Camera>();
		mCamera.orthographic = true;
		let lamp = mScene.CreateGameObject("Preview Light");
		lamp.Transform.SetParent(mCamera.Transform, false);
		// Over the viewer's left shoulder, as the Project panel's material balls are lit.
		lamp.Transform.LocalRotation = Quaternion.Euler(28, 38, 0);
		let light = lamp.AddComponent<Light>();
		light.castShadows = false;
		light.intensity = 1.6f;
	}

	/// A grid of cells for so many balls: the first lit (the whole surface), the others each showing one node.
	void Layout(int cells)
	{
		EnsureScene();
		mColumns = (int32)Math.Max(Math.Ceiling(Math.Sqrt((double)cells)), 1);
		mRows = (int32)Math.Max((cells + mColumns - 1) / mColumns, 1);
		while (mBalls.Count < cells)
		{
			let index = mBalls.Count;
			let ball = mScene.CreateGameObject(scope $"Ball {index}").AddComponent<MeshRenderer>();
			ball.mesh.Set("builtin:sphere");
			ball.flatShading = false;
			let materialName = scope $"graphpreview:{index}";
			let material = Material.Create(materialName);
			material.shader.Set(ShaderName);
			material.color = .White;
			material.roughness = 0.5f;
			material.flatShading = false;
			material.unlit = index > 0;
			material.previewOutput = (int32)index;
			material.Changed();
			ball.material.Set(materialName);
			mBalls.Add(ball);
		}
		for (int i < mBalls.Count)
		{
			let ball = mBalls[i];
			ball.GameObject.SetActive(i < cells);
			// Cell (column, row) is one metre square, counted from the top left; the ball nearly fills it.
			ball.Transform.Position = .((i % mColumns) + 0.5f, -((i / mColumns) + 0.5f), 0);
			ball.Transform.LocalScale = .(0.9f, 0.9f, 0.9f);
		}
		mCamera.orthographicSize = mRows * 0.5f;
		mCamera.nearClip = 0.1f;
		mCamera.farClip = 20;
		mCamera.Transform.Position = .(mColumns * 0.5f, -mRows * 0.5f, -5);
		mCamera.Transform.Rotation = .Identity;
		mView.Resize(mColumns * CellSize, mRows * CellSize);
	}

	void Draw()
	{
		mView.Render(mScene, mCamera.GetCameraData((float)mColumns / mRows));
	}
}
