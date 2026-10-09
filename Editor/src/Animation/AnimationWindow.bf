using System;
using System.Collections;
using System.IO;
using Tessera;

namespace Tessera.Editor;

/// The Animation window: a timeline for making and editing animation clips (.tanim) on the selected object, laid
/// out like Unity's.
///   Left, top: Preview, Record, first / previous key, play, next / last key, and the frame number. Below that the
///   clip, its sample rate, Add Key and Auto Key. Then the animated children, each unfolding to Position, Rotation
///   and Scale with their values at the time marker; typing a value writes a key.
///   Right: a ruler in seconds:frames, a summary row holding every key, and one row of key diamonds per property.
///   Click or drag the ruler to move the marker; scroll to zoom, middle-drag to pan. Drag a diamond to retime it
///   (it snaps to frames), right-click or press Delete to remove it.
///   With Record or Auto Key on, moving, turning or scaling a child in the Scene view or Inspector writes a key at
///   the marker; Auto Key stays on between sessions.
/// Keys are stored as offsets from the pose the object has in the scene, so one clip suits any character whose
/// children have the same names.
extension EditorApp
{
	bool mShowAnimation;
	bool mDockAnimation = true;
	bool mAnimationFocus;
	AnimationClip mClip;
	String mClipPath = new .() ~ delete _;
	float mClipTime;
	bool mClipRecord;
	/// Auto Key: keys whatever is moved, whenever a clip is open, without arming Record each time. Remembered.
	bool mClipAutoKey;
	bool mClipAutoKeyLoaded;
	bool mClipPlaying;
	bool mClipPreview;
	bool mClipDirty;
	int mClipKeyTrack = -1, mClipKeyIndex = -1;
	bool mClipKeyDragging;
	uint32 mClipAnimatorId;
	float mClipPosedTime = -1;
	/// Preview switched off by hand: the object stays in its scene pose until the marker is moved again.
	bool mClipPreviewOff;
	float mAnimLeftWidth = 330;
	/// Zoom and scroll of the timeline. Zero pixels per second means "fit the clip", done when a clip is opened.
	float mAnimPixelsPerSecond;
	bool mAnimFit;
	float mAnimViewStart;
	float mAnimPanLastX;
	List<String> mAnimExpanded = new .() ~ DeleteContainerAndItems!(_);
	int mAnimMenuTrack = -1, mAnimMenuKey = -1;
	int mAnimDeleteTrack = -1, mAnimDeleteKey = -1;
	bool mAnimOpenKeyMenu;

	/// Opens a clip file in the Animation window. The path is a file on disk.
	public void OpenAnimationClip(StringView fullPath)
	{
		let relative = scope String();
		Assets.MakeRelative(fullPath, relative);
		let clip = AnimationClip.Load(relative);
		if (clip == null)
			return;
		mClip = clip;
		mClipPath.Set(relative);
		mClipTime = 0;
		mClipKeyTrack = mClipKeyIndex = -1;
		mAnimPixelsPerSecond = 0;
		mShowAnimation = true;
		mAnimationFocus = true;
	}

	void CreateClipAsset(StringView name)
	{
		if (!ProjectGenerator.IsValidName(name))
		{
			Log.Error("Clip names use letters, digits and underscores, and start with a letter.");
			return;
		}
		let path = scope $"{mBrowsePath}/{name}.tanim";
		if (File.Exists(path))
		{
			Log.Error(scope $"{path} already exists.");
			return;
		}
		let relative = scope String();
		Assets.MakeRelative(path, relative);
		let clip = AnimationClip.Create(relative, name);
		clip.Save(path);
		OpenAnimationClip(path);
	}

	void SaveClip()
	{
		if (mClip == null || mClipPath.IsEmpty)
			return;
		let full = scope String();
		Assets.ResolvePath(mClipPath, full);
		mClip.Save(full);
		mClipDirty = false;
	}

	/// Puts the animated object back in the pose it has in the scene. Called when previewing stops, so that the
	/// previewed pose is never what gets saved with the scene.
	void EndClipPreview()
	{
		if (!mClipPreview)
			return;
		mClipPreview = false;
		mClipPosedTime = -1;
		let object = mScene != null ? mScene.FindById(mClipAnimatorId) : null;
		let animator = object?.GetComponent<Animator>();
		if (animator != null)
		{
			let rest = scope AnimationClip();
			animator.SampleClip(rest, 0);
		}
	}

	static void Descendants(Transform parent, List<Transform> output)
	{
		for (let child in parent.Children)
		{
			output.Add(child);
			Descendants(child, output);
		}
	}

	/// Makes a clip named after the animated object, beside the project's other animations, and gives it to the
	/// Animator so that it can be played.
	void CreateClipFor(Animator animator)
	{
		let folder = scope String();
		folder.AppendF("{}/Animations", Assets.ProjectPath);
		Directory.CreateDirectory(folder).IgnoreError();
		let baseName = scope String();
		NodeLibrary.Identifier(animator.GameObject.Name, baseName);
		let path = scope String();
		for (int n = 1; n < 1000; n++)
		{
			path.Clear();
			path.AppendF("{}/{}_{}.tanim", folder, baseName, n);
			if (!File.Exists(path))
				break;
		}
		let relative = scope String();
		Assets.MakeRelative(path, relative);
		let name = scope String();
		Path.GetFileNameWithoutExtension(path, name);
		let clip = AnimationClip.Create(relative, name);
		clip.Save(path);
		OpenAnimationClip(path);
		if (mPlay == .Edit && !animator.clips.Contains(relative))
		{
			if (!animator.clips.IsEmpty)
				animator.clips.Append(';');
			animator.clips.Append(relative);
			MarkDirty();
		}
		mAnimClipChoicesFrame = -1000;
	}

	static void DrawKeyDiamond(ImGui.Vec2 center, float radius, Color color)
	{
		ImGui.DrawQuadFilled(.(center.x - radius, center.y), .(center.x, center.y - radius), .(center.x + radius, center.y), .(center.x, center.y + radius), color);
	}

	/// A toolbar button with a drawn picture: 0 record, 1 first key, 2 previous key, 3 play / pause, 4 next key,
	/// 5 last key, 6 add key.
	bool AnimIconButton(char8* id, int icon, bool active, char8* tip)
	{
		let height = ImGui.GetFrameHeight();
		let min = ImGui.GetCursorScreenPos();
		let size = ImGui.Vec2(26, height);
		let pressed = ImGui.InvisibleButton(id, size);
		let hovered = ImGui.IsItemHovered();
		if (hovered)
			ImGui.SetTooltip(tip);
		Color back = hovered ? Color(1, 1, 1, 0.13f) : Color(1, 1, 1, 0.05f);
		if (active)
			back = icon == 0 ? Color(0.62f, 0.13f, 0.13f, 1) : Color(0.24f, 0.40f, 0.60f, 1);
		ImGui.DrawRectFilled(min, .(min.x + size.x, min.y + size.y), back, 2);
		let c = ImGui.Vec2(min.x + 13, min.y + height * 0.5f);
		let ink = Color(0.84f, 0.84f, 0.84f, 1);
		const float r = 4.5f;
		void Left(float x) => ImGui.DrawTriangleFilled(.(x + r * 0.7f, c.y - r), .(x + r * 0.7f, c.y + r), .(x - r * 0.7f, c.y), ink);
		void Right(float x) => ImGui.DrawTriangleFilled(.(x - r * 0.7f, c.y - r), .(x + r * 0.7f, c.y), .(x - r * 0.7f, c.y + r), ink);
		void Bar(float x) => ImGui.DrawRectFilled(.(x - 1, c.y - r), .(x + 1, c.y + r), ink);
		switch (icon)
		{
		case 0: ImGui.DrawCircleFilled(c, 5, active ? Color(1, 0.42f, 0.36f, 1) : Color(0.86f, 0.22f, 0.20f, 1));
		case 1: Bar(c.x - 7); Left(c.x - 2.5f); Left(c.x + 4);
		case 2: Bar(c.x - 4.5f); Left(c.x + 1);
		case 3:
			if (active)
			{
				ImGui.DrawRectFilled(.(c.x - 4, c.y - r), .(c.x - 1.5f, c.y + r), ink);
				ImGui.DrawRectFilled(.(c.x + 1.5f, c.y - r), .(c.x + 4, c.y + r), ink);
			}
			else
				ImGui.DrawTriangleFilled(.(c.x - 4, c.y - 5.5f), .(c.x + 5.5f, c.y), .(c.x - 4, c.y + 5.5f), ink);
		case 4: Right(c.x - 1); Bar(c.x + 4.5f);
		case 5: Right(c.x - 4); Right(c.x + 2.5f); Bar(c.x + 7);
		default:
			DrawKeyDiamond(.(c.x - 2, c.y + 1), 4.5f, ink);
			ImGui.DrawLine(.(c.x + 3, c.y - 4.5f), .(c.x + 9, c.y - 4.5f), ink, 1.5f);
			ImGui.DrawLine(.(c.x + 6, c.y - 7.5f), .(c.x + 6, c.y - 1.5f), ink, 1.5f);
		}
		return pressed;
	}

	/// The rotation angles of a track at a time, for showing in the property list.
	static Vector3 SampleEuler(AnimationClip.Track track, float time)
	{
		let keys = track.keys;
		if (keys.Count == 0)
			return .Zero;
		if (time <= keys[0].time || keys.Count == 1)
			return keys[0].euler;
		for (int i = 1; i < keys.Count; i++)
		{
			if (time <= keys[i].time)
			{
				let t = (time - keys[i - 1].time) / Math.Max(keys[i].time - keys[i - 1].time, 1.0e-5f);
				return Vector3.Lerp(keys[i - 1].euler, keys[i].euler, t);
			}
		}
		return keys.Back.euler;
	}

	bool AnimIsExpanded(StringView bone)
	{
		for (let name in mAnimExpanded)
			if (name == bone)
				return true;
		return false;
	}

	void AnimToggleExpanded(StringView bone)
	{
		for (int i < mAnimExpanded.Count)
		{
			if (mAnimExpanded[i] == bone)
			{
				delete mAnimExpanded[i];
				mAnimExpanded.RemoveAt(i);
				return;
			}
		}
		mAnimExpanded.Add(new String(bone));
	}

	/// One row of key diamonds for a track. Several rows may show the same track, so each has its own id base.
	void DrawTrackKeys(AnimationClip clip, int t, float y, float rowHeight, float sheetLeft, float sheetRight, int32 idBase)
	{
		let track = clip.tracks[t];
		ImGui.PushClipRect(.(sheetLeft, y), .(sheetRight, y + rowHeight));
		for (int k < track.keys.Count)
		{
			let x = sheetLeft + (track.keys[k].time - mAnimViewStart) * mAnimPixelsPerSecond;
			if (x < sheetLeft + 1 || x > sheetRight)
				continue;
			let selected = mClipKeyTrack == t && mClipKeyIndex == k;
			ImGui.SetCursorScreenPos(.(Math.Max(x - 6, sheetLeft), y + 2));
			ImGui.PushID(idBase + (int32)k);
			ImGui.InvisibleButton("##key", .(12, rowHeight - 4));
			let hovered = ImGui.IsItemHovered();
			if (ImGui.IsItemClicked(0))
			{
				mClipKeyTrack = t;
				mClipKeyIndex = k;
				mClipTime = track.keys[k].time;
				mClipPlaying = false;
				mClipPreviewOff = false;
			}
			if (ImGui.IsItemActive() && ImGui.IsMouseDragging(0, 3) && selected)
				mClipKeyDragging = true;
			if (ImGui.IsItemClicked(1))
			{
				mAnimMenuTrack = t;
				mAnimMenuKey = k;
				mAnimOpenKeyMenu = true;
			}
			ImGui.PopID();
			let center = ImGui.Vec2(x, y + rowHeight * 0.5f);
			DrawKeyDiamond(center, 6, .(0.10f, 0.10f, 0.10f, 1));
			DrawKeyDiamond(center, 4.5f, selected ? Color(0.36f, 0.66f, 1, 1) : hovered ? Color(1, 1, 1, 1) : Color(0.80f, 0.80f, 0.80f, 1));
		}
		ImGui.PopClipRect();
	}

	/// Text and, optionally, a button in the middle of the window, as Unity shows when there is nothing to edit.
	bool AnimationMessage(char8* text, char8* button)
	{
		let avail = ImGui.GetContentRegionAvail();
		let pos = ImGui.GetCursorScreenPos();
		let size = ImGui.CalcTextSize(text);
		ImGui.SetCursorScreenPos(.(pos.x + Math.Max((avail.x - size.x) * 0.5f, 8), pos.y + Math.Max(avail.y * 0.5f - 26, 8)));
		ImGui.TextDisabled(text);
		if (button == null)
			return false;
		ImGui.SetCursorScreenPos(.(pos.x + Math.Max((avail.x - 96) * 0.5f, 8), pos.y + Math.Max(avail.y * 0.5f, 34)));
		return ImGui.Button(button, .(96, 0));
	}

	void DrawAnimation()
	{
		if (!mShowAnimation)
		{
			EndClipPreview();
			return;
		}
		// Along the bottom with Project and Console the first time, like a timeline; it can be moved from there.
		if (mDockAnimation && mBottomDock != 0)
		{
			ImGui.SetNextWindowDockID(mBottomDock);
			mDockAnimation = false;
			mAnimationFocus = true;
		}
		if (mAnimationFocus && Time.FrameCount > 30)
		{
			ImGui.SetNextWindowFocus();
			mAnimationFocus = false;
		}
		// The timeline runs edge to edge.
		ImGui.PushStyleVar(ImGui.StyleVar.WindowPadding, ImGui.Vec2(0, 0));
		let open = ImGui.Begin("Animation", &mShowAnimation, ImGui.WindowFlags.NoScrollbar | ImGui.WindowFlags.NoScrollWithMouse);
		ImGui.PopStyleVar();
		if (!open)
		{
			ImGui.End();
			return;
		}
		let editing = mPlay == .Edit;
		let animator = SelectedAnimator();
		if (animator == null)
		{
			EndClipPreview();
			let selected = Selected;
			if (selected == null)
				AnimationMessage("No animatable object selected.", null);
			else
			{
				let text = scope String();
				text.AppendF("To begin animating {}, create an Animator and an Animation Clip.", selected.Name);
				ImGui.BeginDisabled(!editing);
				if (AnimationMessage(text.CStr(), "Create"))
				{
					CreateClipFor(selected.AddComponent<Animator>());
					MarkDirty();
				}
				ImGui.EndDisabled();
			}
			ImGui.End();
			return;
		}
		// A different object: drop the pose previewed on the last one, and show a clip of its own.
		if (animator.GameObject.Id != mClipAnimatorId)
		{
			EndClipPreview();
			mClipAnimatorId = animator.GameObject.Id;
			if (!animator.clips.IsEmpty && (mClipPath.IsEmpty || !animator.clips.Contains(mClipPath)))
			{
				for (var path in animator.clips.Split(';'))
				{
					path.Trim();
					let full = scope String();
					Assets.ResolvePath(path, full);
					if (path.IsEmpty || !File.Exists(full))
						continue;
					if (mClipDirty)
						SaveClip();
					let focus = mAnimationFocus;
					OpenAnimationClip(full);
					mAnimationFocus = focus;
					break;
				}
			}
		}
		if (mClip == null)
		{
			let text = scope String();
			text.AppendF("To begin animating {}, create an Animation Clip.", animator.GameObject.Name);
			if (AnimationMessage(text.CStr(), "Create"))
				CreateClipFor(animator);
			let avail = ImGui.GetContentRegionAvail();
			let pos = ImGui.GetCursorScreenPos();
			ImGui.SetCursorScreenPos(.(pos.x + Math.Max((avail.x - 240) * 0.5f, 8), pos.y + 6));
			ImGui.SetNextItemWidth(240);
			if (mClip == null && ImGui.BeginCombo("##openclip", "or open a clip..."))
			{
				RefreshClipChoices();
				for (let choice in mAnimClipChoices)
				{
					if (ImGui.Selectable(choice.CStr(), false))
					{
						let full = scope String();
						Assets.ResolvePath(choice, full);
						OpenAnimationClip(full);
					}
				}
				ImGui.EndCombo();
			}
			ImGui.End();
			return;
		}

		let clip = mClip;
		let rate = Mathf.Clamp(clip.frameRate, 1, 240);
		float Snap(float time) => (float)Math.Round(Math.Max(time, 0) * rate) / rate;
		let origin = ImGui.GetCursorScreenPos();
		let avail = ImGui.GetContentRegionAvail();
		let rowHeight = ImGui.GetFrameHeight() + 2;
		let footerHeight = rowHeight + 4;
		mAnimLeftWidth = Mathf.Clamp(mAnimLeftWidth, 250, Math.Max(avail.x - 160, 250));
		let leftWidth = mAnimLeftWidth;
		let sheetLeft = origin.x + leftWidth + 3;
		let sheetRight = origin.x + avail.x;
		let sheetWidth = Math.Max(sheetRight - sheetLeft, 40);
		let bottom = origin.y + avail.y;
		if (mAnimPixelsPerSecond <= 0 || mAnimFit)
		{
			// The whole clip stays in view, whatever the window's size, until the view is zoomed or panned.
			mAnimFit = true;
			mAnimPixelsPerSecond = (sheetWidth - 24) / Math.Max(clip.duration * 1.12f, 0.25f);
			mAnimViewStart = -12 / mAnimPixelsPerSecond;
		}
		let mouse = ImGui.GetMousePos();
		let recording = mClipRecord && editing;

		// ---- zoom and pan ----
		let overSheet = ImGui.IsWindowHovered(ImGui.HoveredFlags.ChildWindows) && mouse.x >= sheetLeft && mouse.x <= sheetRight && mouse.y >= origin.y && mouse.y <= bottom - footerHeight;
		if (overSheet && Input.MouseWheel != 0)
		{
			let at = mAnimViewStart + (mouse.x - sheetLeft) / mAnimPixelsPerSecond;
			mAnimPixelsPerSecond = Mathf.Clamp(mAnimPixelsPerSecond * Math.Pow(1.18f, Input.MouseWheel), 8, 8000);
			mAnimViewStart = at - (mouse.x - sheetLeft) / mAnimPixelsPerSecond;
			mAnimFit = false;
		}
		if (overSheet && ImGui.IsMouseClicked(2))
		{
			mAnimPanLastX = mouse.x;
			mAnimFit = false;
		}
		else if (ImGui.IsMouseDown(2) && mAnimPanLastX != 0)
		{
			mAnimViewStart -= (mouse.x - mAnimPanLastX) / mAnimPixelsPerSecond;
			mAnimPanLastX = mouse.x;
		}
		else
			mAnimPanLastX = 0;
		mAnimViewStart = Math.Max(mAnimViewStart, -sheetWidth * 0.5f / mAnimPixelsPerSecond);
		let pixelsPerSecond = mAnimPixelsPerSecond;
		let viewStart = mAnimViewStart;
		float TimeToX(float time) => sheetLeft + (time - viewStart) * pixelsPerSecond;
		float XToTime(float x) => viewStart + (x - sheetLeft) / pixelsPerSecond;

		// Every time that has a key, in order: the summary row, and where previous / next key go.
		List<float> keyTimes = scope .();
		for (let track in clip.tracks)
		{
			for (let key in track.keys)
			{
				int at = 0;
				bool have = false;
				while (at < keyTimes.Count && keyTimes[at] <= key.time + 0.0001f)
				{
					have |= Math.Abs(keyTimes[at] - key.time) < 0.0002f;
					at++;
				}
				if (!have)
					keyTimes.Insert(at, key.time);
			}
		}

		// ---- backgrounds ----
		let panel = Color(0.235f, 0.235f, 0.235f, 1);
		ImGui.DrawRectFilled(origin, .(origin.x + leftWidth, origin.y + rowHeight * 2), panel);
		ImGui.DrawRectFilled(.(sheetLeft, origin.y), .(sheetRight, origin.y + rowHeight), recording ? Color(0.40f, 0.15f, 0.14f, 1) : Color(0.22f, 0.22f, 0.22f, 1));
		ImGui.DrawRectFilled(.(sheetLeft, origin.y + rowHeight), .(sheetRight, origin.y + rowHeight * 2), .(0.19f, 0.19f, 0.19f, 1));
		ImGui.DrawRectFilled(.(origin.x, bottom - footerHeight), .(sheetRight, bottom), panel);
		ImGui.DrawRectFilled(.(origin.x + leftWidth, origin.y), .(sheetLeft, bottom - footerHeight), .(0.11f, 0.11f, 0.11f, 1));
		ImGui.DrawLine(.(origin.x, origin.y + rowHeight * 2 - 1), .(sheetRight, origin.y + rowHeight * 2 - 1), .(0.11f, 0.11f, 0.11f, 1));

		// ---- toolbar, first row: preview, record and transport ----
		ImGui.PushStyleVar(ImGui.StyleVar.ItemSpacing, ImGui.Vec2(2, 2));
		ImGui.BeginDisabled(!editing);
		ImGui.SetCursorScreenPos(.(origin.x + 4, origin.y + 1));
		let previewing = mClipPreview && !mClipPreviewOff;
		if (previewing)
			ImGui.PushStyleColor(ImGui.Col.Button, .(0.24f, 0.40f, 0.60f, 1));
		if (ImGui.Button("Preview", .(0, ImGui.GetFrameHeight())))
		{
			if (previewing)
			{
				EndClipPreview();
				mClipPreviewOff = true;
				mClipRecord = false;
				mClipPlaying = false;
			}
			else
				mClipPreviewOff = false;
		}
		if (previewing)
			ImGui.PopStyleColor();
		if (ImGui.IsItemHovered())
			ImGui.SetTooltip("Show the clip's pose on the object. Off puts the object back in its scene pose.");
		ImGui.SameLine();
		if (AnimIconButton("##record", 0, mClipRecord, "Record: moving, turning or scaling a child writes a key at the time marker."))
		{
			mClipRecord = !mClipRecord;
			mClipPreviewOff = false;
		}
		ImGui.SameLine(0, 8);
		float jump = -1;
		if (AnimIconButton("##first", 1, false, "Go to the first key") && keyTimes.Count > 0)
			jump = keyTimes[0];
		ImGui.SameLine();
		if (AnimIconButton("##previous", 2, false, "Go to the previous key"))
		{
			for (let time in keyTimes)
				if (time < mClipTime - 0.0005f)
					jump = time;
		}
		ImGui.SameLine();
		if (AnimIconButton("##play", 3, mClipPlaying, "Play the clip"))
		{
			mClipPlaying = !mClipPlaying;
			mClipPreviewOff = false;
		}
		ImGui.SameLine();
		if (AnimIconButton("##next", 4, false, "Go to the next key"))
		{
			for (let time in keyTimes)
			{
				if (time > mClipTime + 0.0005f)
				{
					jump = time;
					break;
				}
			}
		}
		ImGui.SameLine();
		if (AnimIconButton("##last", 5, false, "Go to the last key") && keyTimes.Count > 0)
			jump = keyTimes.Back;
		if (jump >= 0)
		{
			mClipTime = jump;
			mClipPlaying = false;
			mClipPreviewOff = false;
		}
		ImGui.SetCursorScreenPos(.(origin.x + leftWidth - 60, origin.y + 1));
		ImGui.SetNextItemWidth(56);
		int32 frame = (int32)Math.Round(mClipTime * rate);
		if (ImGui.DragInt("##frame", ref frame, 0.25f, 0, 1000000))
		{
			mClipTime = Math.Max(frame, 0) / rate;
			mClipPlaying = false;
			mClipPreviewOff = false;
		}
		if (ImGui.IsItemHovered())
			ImGui.SetTooltip("Frame at the time marker");

		// ---- toolbar, second row: clip, sample rate, add key, auto key ----
		ImGui.SetCursorScreenPos(.(origin.x + 4, origin.y + rowHeight + 1));
		ImGui.SetNextItemWidth(Math.Max(leftWidth - 150, 90));
		ImGui.EndDisabled();
		let clipLabel = scope String();
		Path.GetFileNameWithoutExtension(mClipPath, clipLabel);
		bool createClip = false;
		if (ImGui.BeginCombo("##clip", clipLabel.CStr()))
		{
			RefreshClipChoices();
			for (let choice in mAnimClipChoices)
			{
				if (ImGui.Selectable(choice.CStr(), choice == mClipPath))
				{
					if (mClipDirty)
						SaveClip();
					let full = scope String();
					Assets.ResolvePath(choice, full);
					OpenAnimationClip(full);
				}
			}
			ImGui.Separator();
			createClip = ImGui.Selectable("Create New Clip...", false);
			ImGui.EndCombo();
		}
		if (createClip)
		{
			if (mClipDirty)
				SaveClip();
			CreateClipFor(animator);
		}
		if (mClip != clip)
		{
			// Another clip was chosen: start over with it next frame.
			ImGui.PopStyleVar();
			ImGui.End();
			return;
		}
		ImGui.BeginDisabled(!editing);
		if (!mClipAutoKeyLoaded)
		{
			// The choice is kept between sessions, with the editor's other settings.
			mClipAutoKeyLoaded = true;
			let saved = scope String();
			let file = scope String();
			RecentProjects.GetConfigFolder(file);
			file.Append("animation_autokey.txt");
			mClipAutoKey = (File.ReadAllText(file, saved) case .Ok) && saved.StartsWith("1");
		}
		ImGui.SetCursorScreenPos(.(origin.x + leftWidth - 142, origin.y + rowHeight + 1));
		ImGui.SetNextItemWidth(40);
		int32 samples = (int32)rate;
		if (ImGui.DragInt("##samples", ref samples, 0.25f, 1, 240))
		{
			clip.frameRate = Mathf.Clamp(samples, 1, 240);
			mClipDirty = true;
		}
		if (ImGui.IsItemHovered())
			ImGui.SetTooltip("Samples: frames per second. Keys sit on these frames.");
		ImGui.SameLine();
		if (AnimIconButton("##addkey", 6, false, "Add a key at the time marker for the selected child,\nor for every animated child when the Animator's object is selected."))
			KeySelectedChild(animator);
		ImGui.SameLine();
		if (mClipAutoKey)
			ImGui.PushStyleColor(ImGui.Col.Button, .(0.75f, 0.45f, 0.10f, 1));
		let wasAutoKey = mClipAutoKey;
		if (ImGui.Button("Auto Key", .(66, ImGui.GetFrameHeight())))
		{
			mClipAutoKey = !mClipAutoKey;
			let file = scope String();
			RecentProjects.GetConfigFolder(file);
			file.Append("animation_autokey.txt");
			File.WriteAllText(file, mClipAutoKey ? "1" : "0").IgnoreError();
		}
		if (wasAutoKey)
			ImGui.PopStyleColor();
		if (ImGui.IsItemHovered())
			ImGui.SetTooltip("Key anything you move, turn or scale at the time marker, every time a clip is open.\nRecord does the same until you turn it off or close the window.");
		ImGui.EndDisabled();
		ImGui.PopStyleVar();

		// ---- the ruler: click or drag to move the time marker ----
		ImGui.SetCursorScreenPos(.(sheetLeft, origin.y));
		ImGui.InvisibleButton("##ruler", .(sheetWidth, rowHeight * 2 - 1));
		if (ImGui.IsItemActive())
		{
			mClipTime = Snap(XToTime(mouse.x));
			mClipPlaying = false;
			mClipPreviewOff = false;
		}
		mClipTime = Math.Max(mClipTime, 0);
		if (mClipPlaying && editing)
		{
			mClipTime += Time.UnscaledDeltaTime;
			if (mClipTime > clip.duration)
				mClipTime = clip.loop ? mClipTime % clip.duration : clip.duration;
			if (mClipTime >= clip.duration && !clip.loop)
				mClipPlaying = false;
		}
		// Labels are seconds:frames. The gap between them follows the zoom.
		int32[?] steps = .(1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 1200, 3600, 7200);
		int32 step = steps[steps.Count - 1];
		for (let candidate in steps)
		{
			if (candidate / rate * pixelsPerSecond >= 64)
			{
				step = candidate;
				break;
			}
		}
		int32 minor = step >= 5 && step % 5 == 0 ? step / 5 : (step > 1 ? (int32)1 : (int32)0);
		let firstFrame = (int32)Math.Floor(Math.Max(viewStart, 0) * rate / step) * step;
		let wholeRate = Math.Max((int32)Math.Round(rate), 1);
		ImGui.PushClipRect(.(sheetLeft, origin.y), .(sheetRight, origin.y + rowHeight * 2));
		for (int32 f = firstFrame; TimeToX(f / rate) < sheetRight; f += step)
		{
			let x = TimeToX(f / rate);
			ImGui.DrawLine(.(x, origin.y + rowHeight * 0.35f), .(x, origin.y + rowHeight), .(1, 1, 1, 0.42f));
			let label = scope String();
			label.AppendF("{}:{:00}", f / wholeRate, f % wholeRate);
			ImGui.DrawText(.(x + 4, origin.y + 1), .(1, 1, 1, 0.55f), label.CStr());
			if (minor > 0)
			{
				for (int32 m = f + minor; m < f + step; m += minor)
				{
					let minorX = TimeToX(m / rate);
					ImGui.DrawLine(.(minorX, origin.y + rowHeight * 0.68f), .(minorX, origin.y + rowHeight), .(1, 1, 1, 0.22f));
				}
			}
		}
		// The summary row: every time that has a key.
		for (let time in keyTimes)
		{
			let center = ImGui.Vec2(TimeToX(time), origin.y + rowHeight * 1.5f);
			DrawKeyDiamond(center, 6, .(0.10f, 0.10f, 0.10f, 1));
			DrawKeyDiamond(center, 4.5f, .(0.80f, 0.80f, 0.80f, 1));
		}
		ImGui.PopClipRect();

		// ---- recording: a child moved by hand becomes a key ----
		List<Transform> children = scope .();
		Descendants(animator.Transform, children);
		if (editing && (mClipRecord || mClipAutoKey) && mClipPreview && !mClipPlaying && mClipPosedTime == mClipTime && !ImGui.IsMouseDown(0))
		{
			for (let child in children)
			{
				Vector3 restPosition, restScale; Quaternion restRotation;
				if (!animator.RestPose(child, out restPosition, out restRotation, out restScale))
					continue;
				Vector3 position = .Zero, scale = .(1, 1, 1); Quaternion rotation = .Identity;
				let track = clip.FindTrack(child.GameObject.Name);
				if (track != null)
					track.Sample(mClipTime, out position, out rotation, out scale);
				let expectedPosition = restPosition + position;
				let expectedRotation = (restRotation * rotation).Normalized;
				let expectedScale = Vector3(restScale.x * scale.x, restScale.y * scale.y, restScale.z * scale.z);
				let turned = Math.Abs(Quaternion.Dot(expectedRotation, child.LocalRotation)) < 0.99999f;
				if ((child.LocalPosition - expectedPosition).Length > 0.0005f || (child.LocalScale - expectedScale).Length > 0.0005f || turned)
					KeyChild(animator, child);
			}
		}

		// ---- pose the object at the marker ----
		if (editing && !mClipPreviewOff && (mClipPosedTime != mClipTime || !mClipPreview))
		{
			animator.SampleClip(clip, mClipTime);
			mClipPosedTime = mClipTime;
			mClipPreview = true;
		}
		else if (!editing)
			mClipPreview = false;

		// ---- the property list and the dopesheet, scrolling together ----
		int removeTrack = -1;
		let rowsTop = origin.y + rowHeight * 2;
		let rowsHeight = Math.Max(avail.y - rowHeight * 2 - footerHeight, 20);
		ImGui.SetCursorScreenPos(.(origin.x, rowsTop));
		ImGui.BeginChild("##rows", .(avail.x, rowsHeight), 0, ImGui.WindowFlags.NoScrollWithMouse);
		{
			let start = ImGui.GetCursorScreenPos();
			let rowsBottom = rowsTop + rowsHeight;
			if (ImGui.IsWindowHovered() && mouse.x < sheetLeft && Input.MouseWheel != 0)
				ImGui.SetScrollY(Mathf.Clamp(ImGui.GetScrollY() - Input.MouseWheel * rowHeight * 2, 0, ImGui.GetScrollMaxY()));
			ImGui.DrawRectFilled(.(origin.x, rowsTop), .(origin.x + leftWidth, rowsBottom), .(0.22f, 0.22f, 0.22f, 1));
			ImGui.DrawRectFilled(.(origin.x + leftWidth, rowsTop), .(sheetLeft, rowsBottom), .(0.11f, 0.11f, 0.11f, 1));
			ImGui.DrawRectFilled(.(sheetLeft, rowsTop), .(sheetRight, rowsBottom), .(0.165f, 0.165f, 0.165f, 1));
			// The divider between the two halves can be dragged.
			ImGui.SetCursorScreenPos(.(origin.x + leftWidth, rowsTop));
			ImGui.InvisibleButton("##split", .(3, rowsHeight));
			if (ImGui.IsItemActive())
				mAnimLeftWidth = mouse.x - origin.x;
			// Faint lines down the sheet at the ruler's labelled frames.
			ImGui.PushClipRect(.(sheetLeft, rowsTop), .(sheetRight, rowsBottom));
			for (int32 f = firstFrame; TimeToX(f / rate) < sheetRight; f += step)
				ImGui.DrawLine(.(TimeToX(f / rate), rowsTop), .(TimeToX(f / rate), rowsBottom), .(1, 1, 1, 0.05f));
			ImGui.PopClipRect();

			float y = start.y;
			int row = 0;
			let lineOffset = (rowHeight - ImGui.GetTextLineHeight()) * 0.5f;
			for (int t < clip.tracks.Count)
			{
				let track = clip.tracks[t];
				ImGui.PushID((int32)t + 500);
				// A row whose child is missing from this object is shown dimmed: the clip still has it for others.
				Transform childTransform = null;
				for (let child in children)
					if (child.GameObject.Name == track.bone)
						childTransform = child;
				let expanded = AnimIsExpanded(track.bone);
				let isSelected = childTransform != null && Selected == childTransform.GameObject;
				ImGui.SetCursorScreenPos(.(origin.x, y));
				ImGui.InvisibleButton("##row", .(leftWidth, rowHeight));
				if (ImGui.IsItemClicked(0))
				{
					if (mouse.x < origin.x + 22 || ImGui.IsMouseDoubleClicked(0))
						AnimToggleExpanded(track.bone);
					else if (childTransform != null)
						mSelectedId = childTransform.GameObject.Id;
				}
				let rowHovered = ImGui.IsItemHovered();
				if (ImGui.BeginPopupContextItem("rowmenu"))
				{
					if (ImGui.MenuItem("Remove Properties"))
						removeTrack = t;
					ImGui.EndPopup();
				}
				if (isSelected)
					ImGui.DrawRectFilled(.(origin.x, y), .(origin.x + leftWidth, y + rowHeight), .(0.17f, 0.36f, 0.53f, 1));
				else if (rowHovered)
					ImGui.DrawRectFilled(.(origin.x, y), .(origin.x + leftWidth, y + rowHeight), .(1, 1, 1, 0.05f));
				let arrow = ImGui.Vec2(origin.x + 12, y + rowHeight * 0.5f);
				let arrowColor = Color(0.75f, 0.75f, 0.75f, 1);
				if (expanded)
					ImGui.DrawTriangleFilled(.(arrow.x - 4, arrow.y - 2.5f), .(arrow.x + 4, arrow.y - 2.5f), .(arrow.x, arrow.y + 3.5f), arrowColor);
				else
					ImGui.DrawTriangleFilled(.(arrow.x - 2.5f, arrow.y - 4), .(arrow.x + 3.5f, arrow.y), .(arrow.x - 2.5f, arrow.y + 4), arrowColor);
				ImGui.DrawText(.(origin.x + 24, y + lineOffset), childTransform != null ? Color(0.86f, 0.86f, 0.86f, 1) : Color(0.55f, 0.55f, 0.55f, 1), track.bone.CStr());
				if (row % 2 == 1)
					ImGui.DrawRectFilled(.(sheetLeft, y), .(sheetRight, y + rowHeight), .(1, 1, 1, 0.025f));
				DrawTrackKeys(clip, t, y, rowHeight, sheetLeft, sheetRight, 0);
				y += rowHeight;
				row++;

				if (expanded)
				{
					Vector3 position, scale; Quaternion rotation;
					track.Sample(mClipTime, out position, out rotation, out scale);
					var euler = SampleEuler(track, mClipTime);
					bool changed = false;
					for (int32 p < 3)
					{
						ImGui.DrawText(.(origin.x + 40, y + lineOffset), .(0.72f, 0.72f, 0.72f, 1), p == 0 ? "Position" : p == 1 ? "Rotation" : "Scale");
						let fieldWidth = Mathf.Clamp(leftWidth - 118, 120, 220);
						ImGui.SetCursorScreenPos(.(origin.x + leftWidth - fieldWidth - 4, y + 1));
						ImGui.SetNextItemWidth(fieldWidth);
						ImGui.PushID(p);
						ImGui.BeginDisabled(!editing);
						if (p == 0)
							changed |= ImGui.DragFloat3("##value", ref position, 0.01f);
						else if (p == 1)
							changed |= ImGui.DragFloat3("##value", ref euler, 0.5f, 0, 0, "%.1f");
						else
							changed |= ImGui.DragFloat3("##value", ref scale, 0.01f);
						ImGui.EndDisabled();
						ImGui.PopID();
						if (row % 2 == 1)
							ImGui.DrawRectFilled(.(sheetLeft, y), .(sheetRight, y + rowHeight), .(1, 1, 1, 0.025f));
						DrawTrackKeys(clip, t, y, rowHeight, sheetLeft, sheetRight, (p + 1) * 100000);
						y += rowHeight;
						row++;
					}
					if (changed)
					{
						// A typed value is a key at the marker, as in Unity.
						mClipTime = Snap(mClipTime);
						int index;
						clip.AutoKey(track.bone, mClipTime, position, euler, scale, out index);
						mClipKeyTrack = t;
						mClipKeyIndex = index;
						mClipPosedTime = -1;
						mClipPreviewOff = false;
						mClipDirty = true;
					}
				}
				ImGui.PopID();
			}

			// ---- add a property ----
			ImGui.SetCursorScreenPos(.(origin.x + Math.Max((leftWidth - 140) * 0.5f, 4), y + 8));
			ImGui.BeginDisabled(!editing);
			if (ImGui.Button("Add Property", .(140, 0)))
				ImGui.OpenPopup("addproperty");
			ImGui.EndDisabled();
			if (ImGui.BeginPopup("addproperty"))
			{
				bool any = false;
				for (let child in children)
				{
					if (clip.FindTrack(child.GameObject.Name) != null)
						continue;
					any = true;
					if (ImGui.Selectable(scope String(child.GameObject.Name).CStr(), false))
					{
						KeyChild(animator, child);
						AnimToggleExpanded(child.GameObject.Name);
					}
				}
				if (!any)
					ImGui.TextDisabled(children.Count == 0 ? "This object has no children to animate.\nClips move the objects beneath the Animator." : "Every child is already animated.");
				ImGui.EndPopup();
			}
			ImGui.SetCursorScreenPos(.(origin.x, y + rowHeight + 18));
			ImGui.Dummy(.(1, 1));

			// Past the end of the clip is darker, and the time marker runs over every row.
			ImGui.PushClipRect(.(sheetLeft, rowsTop), .(sheetRight, rowsBottom));
			ImGui.DrawRectFilled(.(Math.Max(TimeToX(clip.duration), sheetLeft), rowsTop), .(sheetRight, rowsBottom), .(0, 0, 0, 0.28f));
			if (TimeToX(0) > sheetLeft)
				ImGui.DrawRectFilled(.(sheetLeft, rowsTop), .(TimeToX(0), rowsBottom), .(0, 0, 0, 0.28f));
			ImGui.DrawLine(.(TimeToX(mClipTime), rowsTop), .(TimeToX(mClipTime), rowsBottom), .(1, 1, 1, 0.95f), 1);
			ImGui.PopClipRect();
		}
		ImGui.EndChild();

		// The divider, beside the toolbar rows as well.
		ImGui.SetCursorScreenPos(.(origin.x + leftWidth, origin.y));
		ImGui.InvisibleButton("##splittop", .(3, rowHeight * 2));
		if (ImGui.IsItemActive())
			mAnimLeftWidth = mouse.x - origin.x;

		// The time marker's head, in the ruler.
		ImGui.PushClipRect(.(sheetLeft, origin.y), .(sheetRight, rowsTop));
		{
			let x = TimeToX(mClipTime);
			let headColor = recording ? Color(1, 0.45f, 0.40f, 1) : Color(1, 1, 1, 0.95f);
			ImGui.DrawRectFilled(.(Math.Max(TimeToX(clip.duration), sheetLeft), origin.y + rowHeight), .(sheetRight, rowsTop), .(0, 0, 0, 0.28f));
			ImGui.DrawLine(.(x, origin.y), .(x, rowsTop), headColor, 1);
			ImGui.DrawRectFilled(.(x - 1, origin.y), .(x + 2, origin.y + rowHeight * 0.45f), headColor);
		}
		ImGui.PopClipRect();

		// ---- dragging the selected key along the timeline ----
		if (!ImGui.IsMouseDown(0))
			mClipKeyDragging = false;
		if (mClipKeyDragging && editing && mClipKeyTrack >= 0 && mClipKeyTrack < clip.tracks.Count && mClipKeyIndex >= 0 && mClipKeyIndex < clip.tracks[mClipKeyTrack].keys.Count)
		{
			// The key follows the mouse, frame by frame, and stays this key even as it passes its neighbours.
			let track = clip.tracks[mClipKeyTrack];
			var key = track.keys[mClipKeyIndex];
			let time = Snap(XToTime(mouse.x));
			if (time != key.time)
			{
				key.time = time;
				track.keys.RemoveAt(mClipKeyIndex);
				int at = 0;
				while (at < track.keys.Count && track.keys[at].time <= key.time)
					at++;
				track.keys.Insert(at, key);
				mClipKeyIndex = at;
				if (time > clip.duration)
					clip.duration = time;
				mClipTime = time;
				mClipPosedTime = -1;
				mClipDirty = true;
			}
		}

		// ---- removing keys and rows ----
		if (mAnimOpenKeyMenu)
		{
			mAnimOpenKeyMenu = false;
			ImGui.OpenPopup("keymenu");
		}
		if (ImGui.BeginPopup("keymenu"))
		{
			if (ImGui.MenuItem("Delete Key", "Del"))
			{
				mAnimDeleteTrack = mAnimMenuTrack;
				mAnimDeleteKey = mAnimMenuKey;
			}
			ImGui.EndPopup();
		}
		if (editing && mClipKeyTrack >= 0 && mClipKeyIndex >= 0 && !ImGui.IsAnyItemActive() && ImGui.IsWindowFocused(ImGui.HoveredFlags.ChildWindows) && ImGui.IsKeyPressed(ImGui.Key.Delete))
		{
			mAnimDeleteTrack = mClipKeyTrack;
			mAnimDeleteKey = mClipKeyIndex;
		}
		if (mAnimDeleteTrack >= 0)
		{
			if (mAnimDeleteTrack < clip.tracks.Count && mAnimDeleteKey >= 0 && mAnimDeleteKey < clip.tracks[mAnimDeleteTrack].keys.Count)
			{
				clip.tracks[mAnimDeleteTrack].keys.RemoveAt(mAnimDeleteKey);
				mClipPosedTime = -1;
				mClipDirty = true;
			}
			mClipKeyTrack = mClipKeyIndex = -1;
			mAnimDeleteTrack = mAnimDeleteKey = -1;
		}
		if (removeTrack >= 0)
		{
			delete clip.tracks[removeTrack];
			clip.tracks.RemoveAt(removeTrack);
			mClipKeyTrack = mClipKeyIndex = -1;
			mClipPosedTime = -1;
			mClipDirty = true;
		}

		// ---- footer: the clip's length and looping ----
		ImGui.SetCursorScreenPos(.(origin.x + 6, bottom - footerHeight + 3));
		ImGui.AlignTextToFramePadding();
		ImGui.TextDisabled("Length");
		ImGui.SameLine();
		ImGui.SetNextItemWidth(64);
		if (ImGui.DragFloat("##length", ref clip.duration, 0.01f, 0.05f, 600, "%.2f s"))
		{
			clip.duration = Math.Max(clip.duration, 0.05f);
			mClipDirty = true;
		}
		ImGui.SameLine(0, 12);
		if (ImGui.Checkbox("Loop", ref clip.loop))
			mClipDirty = true;
		ImGui.SameLine(0, 12);
		if (ImGui.Button("Frame All", .(0, ImGui.GetFrameHeight())))
			mAnimPixelsPerSecond = 0;
		let hint = "Scroll to zoom    Middle-drag to pan    Drag keys to retime    Right-click a key to delete";
		ImGui.DrawText(.(sheetLeft + 8, bottom - footerHeight + (footerHeight - ImGui.GetTextLineHeight()) * 0.5f), .(1, 1, 1, 0.32f), hint);
		ImGui.End();

		if (mClipDirty && !ImGui.IsMouseDown(0))
			SaveClip();
	}

	/// Writes a key at the marker from where a child is now.
	void KeyChild(Animator animator, Transform child)
	{
		if (mClip == null)
			return;
		Vector3 restPosition, restScale; Quaternion restRotation;
		if (!animator.RestPose(child, out restPosition, out restRotation, out restScale))
			return;
		let position = child.LocalPosition - restPosition;
		let euler = (restRotation.Conjugate * child.LocalRotation).Normalized.EulerAngles;
		let scale = Vector3(restScale.x != 0 ? child.LocalScale.x / restScale.x : 1, restScale.y != 0 ? child.LocalScale.y / restScale.y : 1, restScale.z != 0 ? child.LocalScale.z / restScale.z : 1);
		int index;
		let track = mClip.AutoKey(child.GameObject.Name, mClipTime, position, euler, scale, out index);
		mClipKeyIndex = index;
		mClipKeyTrack = mClip.tracks.IndexOf(track);
		mClipPosedTime = -1;
		mClipDirty = true;
	}

	/// Add Key: the selected child, or every child the clip already moves when the Animator itself is selected.
	void KeySelectedChild(Animator animator)
	{
		let selected = Selected;
		if (selected != null && selected != animator.GameObject)
		{
			KeyChild(animator, selected.Transform);
			return;
		}
		List<Transform> children = scope .();
		Descendants(animator.Transform, children);
		for (let child in children)
		{
			if (mClip.FindTrack(child.GameObject.Name) != null)
				KeyChild(animator, child);
		}
	}
}
