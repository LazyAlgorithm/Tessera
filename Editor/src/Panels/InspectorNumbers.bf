using System;
using Tessera;
namespace Tessera.Editor;
extension EditorApp
{
    [CLink] static extern bool igDragScalar(char8* label,int32 type,void* data,float speed,void* min,void* max,char8* format,int32 flags);
    [CLink] static extern bool igDragScalarN(char8* label,int32 type,void* data,int32 components,float speed,void* min,void* max,char8* format,int32 flags);
    static bool DrawInteger(FieldRef field)=>igDragScalar("##v",FieldNumbers.ImGuiType(field),field.ptr,0.2f,null,null,null,0);
    static bool DrawDouble(FieldRef field)
    {
        double min=field.rangeMin,max=field.rangeMax;
        return igDragScalar("##v",9,field.ptr,0.02f,field.hasRange ? &min : null,field.hasRange ? &max : null,"%.17g",0);
    }
    static bool DragVector(char8* label,float* data,int32 count,float speed)=>igDragScalarN(label,8,data,count,speed,null,null,"%.3f",0);
    static bool DragIntegerVector(char8* label,int32* data,int32 count)=>igDragScalarN(label,4,data,count,0.2f,null,null,null,0);
}
