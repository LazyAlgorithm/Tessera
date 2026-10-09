# Inspector references

Run `BeefBuild -workspace=Tests/References -config=Debug -run` from the engine root.

Checks field reflection, incompatible assignment, forward scene references through save/load,
prefab descendant remapping, and clearing references when components or objects are removed.

Manual editor checks:
- Drag a .glb/.gltf or .tprefab from Project into Scene or Hierarchy.
- Drag a .tui into Scene to create a UI Document object.
- Drop a .tui on a UI Document's Document field; use `...` to select any project document or None.
- Use the same drop/picker interaction for Mesh, Model, Texture and Prefab path fields.
- Add a script with public GameObject, Transform and Camera fields; drag compatible Hierarchy objects into them.
- Use `...` to pick compatible objects/components or None; incompatible drops preserve the existing value.
- Save/reopen, duplicate an object tree, undo, and delete a referenced object/component.

Scene references are non-owning. Do not delete their targets manually; use Scene/GameObject lifecycle methods.
UI assets here mean .tui documents. Individual runtime UIElement references remain accessed through UIDocument.Find(id).
