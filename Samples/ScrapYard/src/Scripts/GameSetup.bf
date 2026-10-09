using System;
using Tessera;

namespace ScrapYard;

/// Runs once when the game or editor starts, before any scene loads.
static class GameSetup
{
	public static void Register()
	{
		// Network prefabs and messages must be registered identically on the server and every client.
		NetworkManager.RegisterPrefab("Player", new => CreatePlayer);
		NetworkManager.RegisterPrefab("Creation", new => CreateCreation);
		GameNet.Register();
	}

	public static GameObject CreatePlayer(Scene scene)
	{
		let player = scene.CreateGameObject("Player");
		// The visible body is the sample animated character; a plain capsule stands in if it is missing.
		let model = Prefab.Instantiate(scene, "Prefabs/character.tprefab");
		if (model != null)
		{
			model.Transform.SetParent(player.Transform, false);
			model.Transform.LocalPosition = .(0, -1, 0);
		}
		else
		{
			let renderer = player.AddComponent<MeshRenderer>();
			renderer.mesh.Set("builtin:capsule");
			renderer.color = .FromBytes(235, 140, 60);
		}
		// A character controller walks up steps and stays on slopes, which a capsule rigid body cannot.
		let controller = player.AddComponent<CharacterController>();
		controller.radius = 0.5f;
		controller.height = 2;
		player.AddComponent<NetworkIdentity>();
		player.AddComponent<CharacterMotor>();
		player.AddComponent<FollowCamera>();
		player.AddComponent<CharacterAnimation>();
		return player;
	}

	/// An empty construction: one rigid body that parts are welded onto.
	public static GameObject CreateCreation(Scene scene)
	{
		let gameObject = scene.CreateGameObject("Creation");
		gameObject.AddComponent<CompoundCollider>();
		let body = gameObject.AddComponent<Rigidbody>();
		body.linearDamping = 0.1f;
		body.angularDamping = 0.6f;
		body.allowSleeping = false;
		gameObject.AddComponent<NetworkIdentity>();
		gameObject.AddComponent<Creation>();
		// Create the body right away so parts can be welded on in the same frame.
		body.EnsureBody();
		return gameObject;
	}
}
