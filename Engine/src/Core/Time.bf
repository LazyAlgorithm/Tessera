using System;
using System.Collections;
using System.Threading;

namespace Tessera;

/// Frame and simulation timing. The simulation runs on a fixed tick so physics and
/// networking stay deterministic; rendering interpolates between ticks.
static class Time
{
	public const int32 TickRate = 60;
	public const float FixedDeltaTime = 1.0f / TickRate;

	/// Seconds since the previous rendered frame, scaled by TimeScale.
	public static float DeltaTime;
	public static float UnscaledDeltaTime;
	/// Seconds of game time since play started.
	public static float Time;
	/// Seconds since the program started, whether or not the game is playing or paused. Shaders use this for
	/// "time", so that animated materials move in the editor too.
	public static float RealTime;
	public static float TimeScale = 1.0f;
	/// How fast simulation ticks come round compared with real time. A network client moves this a few percent
	/// either side of 1 to stay in step with the server; each tick still simulates FixedDeltaTime.
	public static float TickScale = 1.0f;
	public static int64 FrameCount;
	/// Number of fixed simulation ticks executed.
	public static int32 Tick;
	/// 0..1 position of the current frame between the last two fixed ticks.
	public static float InterpolationAlpha;
	public static float SmoothedFps;
}
