using System;
using System.Collections;
using Tessera;
namespace ReferenceTests;
[Component]
class Links : Component
{
    public GameObject target;
    public Transform pose;
    public Camera camera;
}
[Component]
class InspectorAttributes : Component
{
 [ShowInInspector] private float shown=2;
 [HideInInspector] public int32 hidden=3;
 private int32 ordinaryPrivate=4;
 [NonSerialized] public int32 transient=5;
 public float Shown => shown;
}
class Program
{
    static bool Check(bool condition, StringView name)
    {
        Console.WriteLine(scope $"{condition ? "PASS" : "FAIL"}: {name}");
        return condition;
    }
    public static int Main(String[] args)
    {
        bool ok=true;
        let scene=scope Scene(); Scene.Active=scene;
        let root=scene.CreateGameObject("Root");
        let links=root.AddComponent<Links>();
        let child=scene.CreateGameObject("Target",root.Transform);
        let camera=child.AddComponent<Camera>();
        links.target=child; links.pose=child.Transform; links.camera=camera;
        List<FieldRef> fields=scope .(); ComponentRegistry.GetFields(links,fields);
        ok &= Check(fields.Count==3,"three typed references reflected");
        for(let field in fields)
            if(field.name=="camera")
                ok &= Check(!ComponentRegistry.AssignReference(field,root) && links.camera==camera,"incompatible drop preserves value");
        let text=scope String(); SceneSerializer.Save(scene,text);
        let loaded=scope Scene(); SceneSerializer.Load(loaded,text);
        let loadedLinks=loaded.Find("Root").GetComponent<Links>();
        let loadedChild=loaded.Find("Target");
        ok &= Check(loadedLinks.target==loadedChild && loadedLinks.pose==loadedChild.Transform && loadedLinks.camera==loadedChild.GetComponent<Camera>(),"forward references survive save/load");
        let prefab=scope String(); SceneSerializer.SaveObjectTree(root,prefab);
        let copy=SceneSerializer.Instantiate(scene,prefab);
        let copyLinks=copy.GetComponent<Links>();
        ok &= Check(copyLinks.target!=child && copyLinks.target.Transform.Parent==copy.Transform && copyLinks.camera==copyLinks.target.GetComponent<Camera>(),"prefab references remap to copied descendants");
        child.RemoveComponent(camera);
        ok &= Check(links.camera==null && links.target==child,"component removal clears only component references");
        scene.DestroyImmediate(child);
        ok &= Check(links.target==null && links.pose==null,"object removal clears object and transform references");
        Scene.Active=scene;
        fields.Clear(); ComponentRegistry.GetFields(links,fields);
        for(let field in fields) ComponentRegistry.AssignReference(field,null);
        let attributes=root.AddComponent<InspectorAttributes>();fields.Clear();ComponentRegistry.GetFields(attributes,fields);
        bool shown=false,hidden=false,ordinary=false,transient=false;
        for(let field in fields)
        {
            if(field.name=="shown") {shown=!field.hidden;*(float*)field.ptr=12;}
            if(field.name=="hidden") hidden=field.hidden;
            if(field.name=="ordinaryPrivate") ordinary=true;
            if(field.name=="transient") transient=true;
        }
        ok &= Check(shown && hidden && !ordinary && !transient,"ShowInInspector exposes private fields; HideInInspector hides public fields");
        text.Clear();SceneSerializer.Save(scene,text);let attributeScene=scope Scene();SceneSerializer.Load(attributeScene,text);
        let restored=attributeScene.Find("Root").GetComponent<InspectorAttributes>();
        ok &= Check(restored!=null && restored.Shown==12 && restored.hidden==3,"shown private and hidden public fields survive scene serialization");
        return ok ? 0 : 1;
    }
}
