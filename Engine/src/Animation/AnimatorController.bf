using System;
using System.Collections;
using System.IO;

namespace Tessera;

enum AnimatorParameterType : int32 { Float, Int, Bool, Trigger }

/// How a transition's condition compares a parameter. If and IfNot are for booleans and triggers.
enum AnimatorConditionMode : int32 { If, IfNot, Greater, Less, Equals, NotEqual }

/// A state machine for an Animator: states that each play a clip, parameters that scripts set, and transitions
/// between states that fire when their conditions on those parameters hold. Made in the Animator window and saved
/// as a .tcontroller file.
class AnimatorController
{
	public class Parameter
	{
		public String name = new .() ~ delete _;
		public AnimatorParameterType type;
		public float defaultValue;
	}

	public class State
	{
		public String name = new .() ~ delete _;
		/// A .tanim clip file, or the name of a clip in the object's skinned model.
		public String clip = new .() ~ delete _;
		public float speed = 1;
		public bool loop = true;
		/// Where the state sits in the Animator window.
		public Vector2 position;
	}

	public struct Condition
	{
		public int32 parameter;
		public AnimatorConditionMode mode;
		public float threshold;
	}

	public class Transition
	{
		/// The state it leaves, or -1 for Any State.
		public int32 from;
		public int32 to;
		/// Seconds of cross-fade.
		public float duration = 0.15f;
		/// Wait until the state has played this fraction of its clip (1 is the end) before the transition can fire.
		public bool hasExitTime;
		public float exitTime = 1;
		public List<Condition> conditions = new .() ~ delete _;
	}

	public List<Parameter> parameters = new .() ~ DeleteContainerAndItems!(_);
	public List<State> states = new .() ~ DeleteContainerAndItems!(_);
	public List<Transition> transitions = new .() ~ DeleteContainerAndItems!(_);
	/// The state entered when the Animator starts.
	public int32 defaultState;
	/// Goes up when the controller is edited, so running Animators pick the change up.
	public int32 Revision;

	static Dictionary<String, AnimatorController> sCache = new .() ~ DeleteDictionaryAndKeysAndValues!(_);

	public int32 FindParameter(StringView name)
	{
		for (int32 i < (int32)parameters.Count)
			if (parameters[i].name == name)
				return i;
		return -1;
	}

	public int32 FindState(StringView name)
	{
		for (int32 i < (int32)states.Count)
			if (states[i].name == name)
				return i;
		return -1;
	}

	public Parameter AddParameter(StringView name, AnimatorParameterType type)
	{
		let parameter = new Parameter();
		parameter.name.Set(name);
		parameter.type = type;
		parameters.Add(parameter);
		Revision++;
		return parameter;
	}

	public State AddState(StringView name, StringView clip, Vector2 position = default)
	{
		let state = new State();
		state.name.Set(name);
		state.clip.Set(clip);
		state.position = position;
		states.Add(state);
		Revision++;
		return state;
	}

	public Transition AddTransition(int32 from, int32 to)
	{
		let transition = new Transition();
		transition.from = from;
		transition.to = to;
		transitions.Add(transition);
		Revision++;
		return transition;
	}

	/// Adds a condition to a transition by parameter name. Returns false if there is no such parameter.
	public bool AddCondition(Transition transition, StringView parameter, AnimatorConditionMode mode, float threshold = 0)
	{
		let index = FindParameter(parameter);
		if (index < 0)
			return false;
		Condition condition;
		condition.parameter = index;
		condition.mode = mode;
		condition.threshold = threshold;
		transition.conditions.Add(condition);
		Revision++;
		return true;
	}

	/// Removes a state and every transition to or from it.
	public void RemoveState(int32 index)
	{
		if (index < 0 || index >= states.Count)
			return;
		delete states[index];
		states.RemoveAt(index);
		for (int i = transitions.Count - 1; i >= 0; i--)
		{
			let transition = transitions[i];
			if (transition.from == index || transition.to == index)
			{
				delete transition;
				transitions.RemoveAt(i);
				continue;
			}
			if (transition.from > index) transition.from--;
			if (transition.to > index) transition.to--;
		}
		if (defaultState == index)
			defaultState = 0;
		else if (defaultState > index)
			defaultState--;
		Revision++;
	}

	/// Removes a parameter and the conditions that used it.
	public void RemoveParameter(int32 index)
	{
		if (index < 0 || index >= parameters.Count)
			return;
		delete parameters[index];
		parameters.RemoveAt(index);
		for (let transition in transitions)
		{
			for (int i = transition.conditions.Count - 1; i >= 0; i--)
			{
				if (transition.conditions[i].parameter == index)
					transition.conditions.RemoveAt(i);
				else if (transition.conditions[i].parameter > index)
					transition.conditions[i].parameter--;
			}
		}
		Revision++;
	}

	public void Save(StringView fullPath)
	{
		let text = scope String();
		text.Append("controller 1\n");
		for (let parameter in parameters)
		{
			text.Append("parameter ");
			SceneSerializer.Quote(parameter.name, text);
			text.AppendF(" {} {}\n", (int32)parameter.type, parameter.defaultValue);
		}
		for (let state in states)
		{
			text.Append("state ");
			SceneSerializer.Quote(state.name, text);
			text.Append(' ');
			SceneSerializer.Quote(state.clip, text);
			text.AppendF(" {} {} {} {}\n", state.speed, state.loop ? 1 : 0, state.position.x, state.position.y);
		}
		text.AppendF("default {}\n", defaultState);
		for (let transition in transitions)
		{
			text.AppendF("transition {} {} {} {} {}\n", transition.from, transition.to, transition.duration, transition.hasExitTime ? 1 : 0, transition.exitTime);
			for (let condition in transition.conditions)
				text.AppendF("condition {} {} {}\n", condition.parameter, (int32)condition.mode, condition.threshold);
		}
		if (File.WriteAllText(fullPath, text) case .Err)
			Log.Error(scope $"Could not save {fullPath}");
	}

	public bool Read(StringView fullPath)
	{
		let text = scope String();
		if (AssetPack.ReadAllText(fullPath, text) case .Err)
			return false;
		ClearAndDeleteItems!(parameters);
		ClearAndDeleteItems!(states);
		ClearAndDeleteItems!(transitions);
		defaultState = 0;
		Transition transition = null;
		List<StringView> tokens = scope .();
		List<String> storage = scope .();
		defer { for (let s in storage) delete s; }
		for (let line in text.Split('\n'))
		{
			tokens.Clear();
			SceneSerializer.Tokenize(line, tokens, storage);
			if (tokens.Count < 2)
				continue;
			switch (tokens[0])
			{
			case "parameter":
				if (tokens.Count >= 4)
				{
					let parameter = AddParameter(tokens[1], (AnimatorParameterType)Math.Clamp(SceneSerializer.ParseInt(tokens[2]), 0, 3));
					parameter.defaultValue = SceneSerializer.ParseFloat(tokens[3]);
				}
			case "state":
				if (tokens.Count >= 7)
				{
					let state = AddState(tokens[1], tokens[2], .(SceneSerializer.ParseFloat(tokens[5]), SceneSerializer.ParseFloat(tokens[6])));
					state.speed = SceneSerializer.ParseFloat(tokens[3]);
					state.loop = tokens[4] == "1";
				}
			case "default":
				defaultState = (int32)SceneSerializer.ParseInt(tokens[1]);
			case "transition":
				if (tokens.Count >= 6)
				{
					transition = AddTransition((int32)SceneSerializer.ParseInt(tokens[1]), (int32)SceneSerializer.ParseInt(tokens[2]));
					transition.duration = Math.Max(SceneSerializer.ParseFloat(tokens[3]), 0);
					transition.hasExitTime = tokens[4] == "1";
					transition.exitTime = SceneSerializer.ParseFloat(tokens[5]);
				}
			case "condition":
				if (tokens.Count >= 4 && transition != null)
				{
					Condition condition;
					condition.parameter = (int32)SceneSerializer.ParseInt(tokens[1]);
					condition.mode = (AnimatorConditionMode)Math.Clamp(SceneSerializer.ParseInt(tokens[2]), 0, 5);
					condition.threshold = SceneSerializer.ParseFloat(tokens[3]);
					if (condition.parameter >= 0 && condition.parameter < parameters.Count)
						transition.conditions.Add(condition);
				}
			}
		}
		// Anything pointing at a state that is not there is dropped rather than trusted.
		for (int i = transitions.Count - 1; i >= 0; i--)
		{
			let t = transitions[i];
			if (t.to < 0 || t.to >= states.Count || t.from < -1 || t.from >= states.Count)
			{
				delete t;
				transitions.RemoveAt(i);
			}
		}
		defaultState = Math.Clamp(defaultState, 0, Math.Max((int32)states.Count - 1, 0));
		Revision++;
		return true;
	}

	/// Loads (and caches) a controller. The path is relative to the project's asset folder. Everything using the
	/// same file shares one controller, so an edit in the Animator window shows on every object at once.
	public static AnimatorController Load(StringView path)
	{
		if (path.IsEmpty)
			return null;
		if (sCache.TryGetValueAlt(path, let cached))
			return cached;
		let full = scope String();
		Assets.ResolvePath(path, full);
		let controller = new AnimatorController();
		if (!controller.Read(full))
		{
			delete controller;
			Log.Warning(scope $"Animator controller not found: {path}");
			return null;
		}
		sCache[new String(path)] = controller;
		return controller;
	}
}
