// Standalone ASan/UBSan smoke test for the native asset/parser/query bridge.
#undef NDEBUG // Keep test assertions while matching release Jolt in the bridge translation unit.
#include <vector>
#include <cstdint>
#include <cstring>
#include <cassert>
#include <limits>
#include <cstdio>
extern "C" {
void* tn_nav_load(const unsigned char*,int);
void tn_nav_destroy(void*);
int tn_nav_tile_count(void*);
int tn_nav_tiles_rebuilt(void*);
struct Volume {float center[3],rotation[4],half[3],cost;int cylinder,obstacle;};
bool tn_nav_overlay(void*,const Volume*,int,const void*,int);
int tn_nav_polygons(const void*);
void* tn_nav_query_create();
void tn_nav_query_destroy(void*);
unsigned tn_nav_sample(const void*,void*,const float*,float,float*);
int tn_nav_path(const void*,void*,const float*,const float*,float,int,int,int*,int*);
bool tn_nav_line(const void*,void*,const float*,const float*,float*);
}
static void put(std::vector<unsigned char>& out,uint32_t v){for(int i=0;i<4;++i)out.push_back((unsigned char)(v>>(i*8)));}
static void number(std::vector<unsigned char>& out,float f){uint32_t v;std::memcpy(&v,&f,4);put(out,v);}
static std::vector<unsigned char> asset(bool empty=false){
 std::vector<unsigned char> out;put(out,0x314D4E54);
 const float cfg[]={0,0,0,128,6,128,1.f/6,1.f/12,.3f,1.8f,.5f,45};for(float f:cfg)number(out,f);
 const float geometry[]={0,0,0,0,0,16,16,0,16,0,0,0,16,0,16,16,0,0};put(out,empty?0:18);if(!empty)for(float f:geometry)number(out,f);return out;
}
int main(){
 auto data=asset();void* mesh=tn_nav_load(data.data(),int(data.size()));assert(mesh&&tn_nav_polygons(mesh)>0);
 void* query=tn_nav_query_create();float from[]={2,.1f,2},to[]={14,.1f,14},found[3];int visited=0,exceeded=0;
 assert(tn_nav_sample(mesh,query,from,1,found));
 assert(tn_nav_path(mesh,query,from,to,2,1,200000,&visited,&exceeded)>=2&&!exceeded);
 assert(tn_nav_line(mesh,query,from,to,found));
 assert(!tn_nav_path(mesh,query,from,to,2,1,0,&visited,&exceeded)&&exceeded);
 float nan[]={std::numeric_limits<float>::quiet_NaN(),0,0};assert(!tn_nav_sample(mesh,query,nan,1,found));
 Volume volume{{8,0,8},{0,0,0,1},{1,1,1},0,0,1};
 assert(tn_nav_tile_count(mesh)>1&&tn_nav_overlay(mesh,&volume,1,nullptr,0));
 assert(tn_nav_tiles_rebuilt(mesh)>0&&tn_nav_tiles_rebuilt(mesh)<tn_nav_tile_count(mesh));
 float blocked[]={8,.1f,8};assert(!tn_nav_sample(mesh,query,blocked,.2f,found));
 assert(tn_nav_overlay(mesh,nullptr,0,nullptr,0)&&tn_nav_sample(mesh,query,blocked,.2f,found));
 for(int cost=2;cost<72;++cost){volume.cost=float(cost);assert(tn_nav_overlay(mesh,&volume,1,nullptr,0));}
 assert(tn_nav_overlay(mesh,nullptr,0,nullptr,0));
 tn_nav_query_destroy(query);tn_nav_destroy(mesh);
 for(size_t size=0;size<data.size();++size)assert(!tn_nav_load(data.data(),int(size)));
 for(size_t offset=4;offset<52;offset+=4){auto bad=data;uint32_t v=0x7fc00000u;std::memcpy(bad.data()+offset,&v,4);assert(!tn_nav_load(bad.data(),int(bad.size())));}
 auto huge=data;uint32_t count=0xfffffff0u;std::memcpy(huge.data()+52,&count,4);assert(!tn_nav_load(huge.data(),int(huge.size())));
 auto empty=asset(true);mesh=tn_nav_load(empty.data(),int(empty.size()));assert(mesh&&tn_nav_polygons(mesh)==0);query=tn_nav_query_create();assert(!tn_nav_sample(mesh,query,from,1,found));tn_nav_query_destroy(query);tn_nav_destroy(mesh);
 std::puts("PASS native NavMesh parser/query/empty geometry smoke test");
}
