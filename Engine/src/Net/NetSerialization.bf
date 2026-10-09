using System;
using System.Collections;

namespace Tessera;

/// Growable little-endian message writer.
class NetWriter
{
	public List<uint8> Data = new .() ~ delete _;

	public void Clear() => Data.Clear();

	public void Write<T>(T value) where T : struct
	{
		var v = value;
		let start = Data.Count;
		Data.Count += sizeof(T);
		Internal.MemCpy(Data.Ptr + start, &v, sizeof(T));
	}

	/// A whole number in as few bytes as it needs: one byte below 128, two below 16384, and so on.
	public void WriteVarUInt(uint32 value)
	{
		var left = value;
		while (left >= 0x80)
		{
			Data.Add((uint8)(left | 0x80));
			left >>= 7;
		}
		Data.Add((uint8)left);
	}

	/// The low three bytes of a number between -8388608 and 8388607.
	public void Write24(int32 value)
	{
		Data.Add((uint8)value);
		Data.Add((uint8)(value >> 8));
		Data.Add((uint8)(value >> 16));
	}

	public void WriteString(StringView text)
	{
		let length = (uint8)Math.Min(text.Length, 255);
		Data.Add(length);
		for (int i < length)
			Data.Add((uint8)text[i]);
	}
}

/// Bounds-checked message reader. After any failed read, Ok stays false and values are zero.
struct NetReader
{
	uint8* mData;
	int mLength;
	int mOffset;
	public bool Ok = true;

	public this(uint8* data, int length)
	{
		mData = data;
		mLength = length;
		mOffset = 0;
	}

	public T Read<T>() mut where T : struct
	{
		T value = default;
		if (mOffset + sizeof(T) > mLength)
		{
			Ok = false;
			return value;
		}
		Internal.MemCpy(&value, mData + mOffset, sizeof(T));
		mOffset += sizeof(T);
		return value;
	}

	public uint32 ReadVarUInt() mut
	{
		uint32 value = 0;
		for (int shift = 0; shift < 35; shift += 7)
		{
			let part = Read<uint8>();
			value |= (uint32)(part & 0x7F) << shift;
			if ((part & 0x80) == 0)
				return value;
		}
		Ok = false;
		return 0;
	}

	public int32 Read24() mut
	{
		let low = (uint32)Read<uint16>();
		let high = (uint32)Read<uint8>();
		// Shifted up and back down so that the sign comes with it.
		return (int32)((low | (high << 16)) << 8) >> 8;
	}

	public void ReadString(String text) mut
	{
		let length = (int)Read<uint8>();
		if (mOffset + length > mLength)
		{
			Ok = false;
			return;
		}
		text.Append((char8*)mData + mOffset, length);
		mOffset += length;
	}
}

/// One tick of player intent. Sent from the owning client to the server, and replayed during prediction.
[CRepr]
struct NetInput
{
	public float moveX;
	public float moveZ;
	public float yaw;
	public float pitch;
	public uint32 buttons;

	public bool GetButton(int index) => (buttons & ((uint32)1 << index)) != 0;
	public void SetButton(int index, bool down) mut
	{
		if (down)
			buttons |= (uint32)1 << index;
		else
			buttons &= ~((uint32)1 << index);
	}
}

/// Packs what goes over the network every tick into few bytes: positions to about two millimetres, rotations to a
/// fraction of a degree, controls to nine bytes.
static class NetPack
{
	/// Steps per world unit in a packed position.
	public const float PositionScale = 512;
	const float cPositionLimit = 8388607 / PositionScale;

	public const uint8 FlagYawOnly = 1;
	/// The position is too far from the origin to pack; it is sent as plain floats.
	public const uint8 FlagWide = 2;
	/// Everything, unpacked: for the machine that predicts this object and must compare exactly.
	public const uint8 FlagFull = 4;

	/// What a snapshot says about an object nobody on the receiving machine controls.
	public struct Packed
	{
		public int32 x, y, z;
		public uint32 rotation;
		public uint8 flags;

		public bool Same(Packed other) => x == other.x && y == other.y && z == other.z && rotation == other.rotation && flags == other.flags;
	}

	public static Packed Pack(Vector3 position, Quaternion rotation)
	{
		Packed packed = default;
		if (Math.Abs(position.x) < cPositionLimit && Math.Abs(position.y) < cPositionLimit && Math.Abs(position.z) < cPositionLimit)
		{
			packed.x = (int32)Math.Round(position.x * PositionScale);
			packed.y = (int32)Math.Round(position.y * PositionScale);
			packed.z = (int32)Math.Round(position.z * PositionScale);
		}
		else
		{
			var copy = position;
			packed.flags |= FlagWide;
			packed.x = *(int32*)&copy.x;
			packed.y = *(int32*)&copy.y;
			packed.z = *(int32*)&copy.z;
		}
		// Most things only ever turn about the upright axis (characters above all), which takes two bytes.
		if (Math.Abs(rotation.x) < 0.0005f && Math.Abs(rotation.z) < 0.0005f)
		{
			packed.flags |= FlagYawOnly;
			let turn = Math.Atan2(rotation.y, rotation.w) / Math.PI_f;
			packed.rotation = (uint32)(uint16)(int32)Math.Round(turn * 32768);
		}
		else
			packed.rotation = PackRotation(rotation);
		return packed;
	}

	public static void Unpack(Packed packed, out Vector3 position, out Quaternion rotation)
	{
		if ((packed.flags & FlagWide) != 0)
		{
			var copy = packed;
			position = .(*(float*)&copy.x, *(float*)&copy.y, *(float*)&copy.z);
		}
		else
			position = .(packed.x / PositionScale, packed.y / PositionScale, packed.z / PositionScale);
		if ((packed.flags & FlagYawOnly) != 0)
		{
			let half = (float)(int16)(uint16)packed.rotation / 32768 * Math.PI_f;
			rotation = .(0, Math.Sin(half), 0, Math.Cos(half));
		}
		else
			rotation = UnpackRotation(packed.rotation);
	}

	public static void Write(NetWriter writer, Packed packed)
	{
		writer.Write(packed.flags);
		if ((packed.flags & FlagWide) != 0)
		{
			writer.Write(packed.x); writer.Write(packed.y); writer.Write(packed.z);
		}
		else
		{
			writer.Write24(packed.x); writer.Write24(packed.y); writer.Write24(packed.z);
		}
		if ((packed.flags & FlagYawOnly) != 0)
			writer.Write((uint16)packed.rotation);
		else
			writer.Write(packed.rotation);
	}

	/// Reads what Write wrote, the flags byte having been read already.
	public static Packed Read(ref NetReader reader, uint8 flags)
	{
		Packed packed = default;
		packed.flags = flags;
		if ((flags & FlagWide) != 0)
		{
			packed.x = reader.Read<int32>(); packed.y = reader.Read<int32>(); packed.z = reader.Read<int32>();
		}
		else
		{
			packed.x = reader.Read24(); packed.y = reader.Read24(); packed.z = reader.Read24();
		}
		packed.rotation = (flags & FlagYawOnly) != 0 ? (uint32)reader.Read<uint16>() : reader.Read<uint32>();
		return packed;
	}

	/// A rotation in four bytes: the largest of its four numbers is left out (it follows from the other three),
	/// and those take ten bits each.
	public static uint32 PackRotation(Quaternion rotation)
	{
		float[4] parts = .(rotation.x, rotation.y, rotation.z, rotation.w);
		int largest = 0;
		for (int i = 1; i < 4; i++)
		{
			if (Math.Abs(parts[i]) > Math.Abs(parts[largest]))
				largest = i;
		}
		let sign = parts[largest] < 0 ? -1.0f : 1.0f;
		uint32 packed = (uint32)largest << 30;
		int shift = 20;
		for (int i < 4)
		{
			if (i == largest)
				continue;
			let scaled = Mathf.Clamp(parts[i] * sign * 0.70710678f + 0.5f, 0, 1);
			packed |= (uint32)Math.Round(scaled * 1023) << shift;
			shift -= 10;
		}
		return packed;
	}

	public static Quaternion UnpackRotation(uint32 packed)
	{
		let largest = (int)(packed >> 30);
		float[4] parts = default;
		float sum = 0;
		int shift = 20;
		for (int i < 4)
		{
			if (i == largest)
				continue;
			let value = ((float)((packed >> shift) & 1023) / 1023 - 0.5f) / 0.70710678f;
			parts[i] = value;
			sum += value * value;
			shift -= 10;
		}
		parts[largest] = Math.Sqrt(Math.Max(1 - sum, 0));
		return Quaternion(parts[0], parts[1], parts[2], parts[3]).Normalized;
	}

	// ---- controls ----

	/// The controls as they will arrive on the server. The player's own machine predicts with these too, so that
	/// both work from exactly the same numbers.
	public static NetInput Quantize(NetInput input)
	{
		NetInput packed = input;
		packed.moveX = (float)MoveByte(input.moveX) / 127;
		packed.moveZ = (float)MoveByte(input.moveZ) / 127;
		packed.yaw = (float)AngleShort(input.yaw) * (360.0f / 65536);
		packed.pitch = (float)AngleShort(input.pitch) * (360.0f / 65536);
		return packed;
	}

	static int8 MoveByte(float value) => value.IsFinite ? (int8)Math.Round(Mathf.Clamp(value, -1, 1) * 127) : 0;
	/// A whole turn in 65536 steps; going round more than once comes back to the same place.
	static int16 AngleShort(float degrees) => degrees.IsFinite ? (int16)(uint16)(int32)((int64)Math.Round((double)degrees * (65536.0 / 360)) & 0xFFFF) : 0;

	const uint8 cInputSame = 1;
	const uint8 cInputWideButtons = 2;

	/// Writes one tick of controls; a tick the same as the one before it in the packet takes a single byte.
	public static void WriteInput(NetWriter writer, NetInput input, NetInput previous, bool hasPrevious)
	{
		if (hasPrevious && input.moveX == previous.moveX && input.moveZ == previous.moveZ && input.yaw == previous.yaw && input.pitch == previous.pitch && input.buttons == previous.buttons)
		{
			writer.Write(cInputSame);
			return;
		}
		let wide = input.buttons > 0xFFFF;
		writer.Write(wide ? cInputWideButtons : (uint8)0);
		writer.Write(MoveByte(input.moveX));
		writer.Write(MoveByte(input.moveZ));
		writer.Write(AngleShort(input.yaw));
		writer.Write(AngleShort(input.pitch));
		if (wide)
			writer.Write(input.buttons);
		else
			writer.Write((uint16)input.buttons);
	}

	public static NetInput ReadInput(ref NetReader reader, NetInput previous)
	{
		let flags = reader.Read<uint8>();
		if ((flags & cInputSame) != 0)
			return previous;
		NetInput input = default;
		input.moveX = (float)reader.Read<int8>() / 127;
		input.moveZ = (float)reader.Read<int8>() / 127;
		input.yaw = (float)reader.Read<int16>() * (360.0f / 65536);
		input.pitch = (float)reader.Read<int16>() * (360.0f / 65536);
		input.buttons = (flags & cInputWideButtons) != 0 ? reader.Read<uint32>() : (uint32)reader.Read<uint16>();
		return input;
	}
}
