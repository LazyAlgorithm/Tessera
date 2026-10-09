---
title: Sound: sources, a listener and an echo
summary: Give objects their own sounds, hear them in 3D from the player's position, muffle them behind walls and add reverb to a room.
difficulty: Beginner
minutes: 15
order: 6
---
Sound in Tessera has two parts. An **Audio Source** on an object makes sound from where that object is. An **Audio Listener** is where it is heard from. Nothing needs installing.

You need a sound file or two: WAV, OGG, MP3 or FLAC. Drop them into a `Sounds` folder in the Project panel. Double-click one to hear it.

## 1. A sound in the world

1. Choose **GameObject > Audio Source** and move the new object somewhere in your level.
2. In the Inspector, set **Audio Clip** to a looping sound: a hum, a radio, a fire. Tick **Loop**.
3. Press **Preview**. Outside play mode you hear it from the Scene view's camera, so fly around it: it gets quieter as you leave and moves between your ears as you turn.

The two spheres in the Scene view are **Min Distance** (full volume inside) and **Max Distance** (no quieter beyond). Make the minimum bigger for things that should be heard from far away.

## 2. The listener

Press **Play**. With no Audio Listener in the scene the camera is the listener, which is usually what you want.

If the ears should be somewhere else, for example on the character's head in a game with a far-off camera, add an **Audio Listener** component to that object.

## 3. Headphones

Direction is plain left-right panning until you turn on HRTF, which is made for headphones: with it you can tell in front from behind and above from below. Tick **File > Project Settings > Headphone 3D Audio**, or set it from a script, then put headphones on and walk round the source with your back to it.

Over speakers the effect does not work and can colour the sound, so make it the player's choice, and let them tune it:

```beef
Audio.Hrtf = true;              // headphones; false is ordinary panning
Audio.HrtfStrength = 0.8f;      // 0..1, how much of the effect
Audio.HrtfHeadSize = 1.1f;      // 0.5..1.5, the delay between the ears
Audio.HrtfTreble = 3;           // -12..12 dB, brighter or duller
```

All four can change while sounds are playing.

## 4. Behind a wall

Put a wall with a **Box Collider** between the source and the listener. The sound becomes quieter and duller, and clears when you step round the wall. That is **Occlusion**, on by default; untick it on sources that should ignore walls, such as a voice in the player's ear.

## 5. Sounds from a script

Looping sounds play themselves. One-off sounds are played from code. This component plays a sound each time it is touched, with a little variety:

```beef
using System;
using Tessera;

namespace MyGame;

/// Plays a sound when the object named in Visitor comes within reach, and again each time it returns.
[Component]
class Chime : Component
{
    public String sound = new .("Sounds/chime.wav") ~ delete _;
    public String visitor = new .("Player") ~ delete _;
    public float radius = 2;

    AudioSource mSource;
    bool mInside;
    Random mRandom = new .() ~ delete _;

    public override void Start()
    {
        mSource = GetComponent<AudioSource>();
    }

    public override void Update()
    {
        let other = Scene.Find(visitor);
        let inside = other != null && (other.Transform.Position - Transform.Position).Length < radius;
        if (inside && !mInside && mSource != null)
        {
            // A slightly different pitch each time keeps a repeated sound from grating.
            mSource.pitch = 0.9f + (float)mRandom.NextDouble() * 0.2f;
            mSource.PlayOneShot(sound);
        }
        mInside = inside;
    }
}
```

Put it on an object that has an Audio Source with **Play On Start** off. `PlayOneShot` plays from the object's position with the source's distance settings, and any number can overlap, which is what footsteps and gunshots need.

For a sound with no object, use `Audio.PlayOneShot("Sounds/explosion.wav", position)`. For an interface click, `Audio.PlayOneShot2D("Sounds/click.wav")`.

## 6. Music

1. Add another Audio Source and choose a music file.
2. Set **Group** to **Music**, untick **Spatial** so it is plain stereo, and tick **Loop** and **Stream**.

Streaming reads the file as it plays instead of loading it all, which suits long tracks.

## 7. An options menu

Every source plays into a group and every group into the master:

```beef
Audio.MasterVolume = 0.8f;
Audio.SetGroupVolume(.Music, 0.4f);
Audio.SetGroupVolume(.Effects, 1.0f);
Audio.Hrtf = headphones;
```

## 8. An echo

1. Create an empty object in the middle of a large room or cave and add an **Audio Reverb Zone**.
2. Set **Radius** to cover the space and **Room Size** to taste.
3. Play and walk in. Sounds gain a tail that fades in as you cross the edge of the zone.

## In multiplayer

`Play`, `Stop` and `PlayOneShot` on an Audio Source are shared automatically when called on the server or by the player who controls the object, so a shot fired by one player is heard by all.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| No sound at all | The Console says if no sound device was found, or if the file could not be read. |
| A sound is always the same in both ears | **Spatial** is off, or the source is on the same object as the listener. |
| It is too quiet at a distance | Raise **Min Distance**; with Inverse rolloff the volume halves every time the distance doubles past it. |
| It is muffled for no reason | Something with a collider is between the listener and the source. Untick **Occlusion** to check. |

See [Audio](docs.php?page=audio) for every setting and for what the engine does not do.
