cmake_minimum_required(VERSION 3.20)
project(tessera_native C CXX)

# Builds every native dependency of the Tessera engine as static libraries.
# The Beef projects link the resulting archives (see Engine/BeefProj.toml).

set(CMAKE_POSITION_INDEPENDENT_CODE ON)
if(NOT CMAKE_BUILD_TYPE)
	set(CMAKE_BUILD_TYPE Release)
endif()

set(TP ${CMAKE_CURRENT_SOURCE_DIR}/../third_party)

if(EMSCRIPTEN)
	# Emscripten turns SSE into WebAssembly SIMD. bx asks for SSE 4.2 on every non-MSVC compiler, and Jolt's headers
	# use SSE when built for WebAssembly SIMD, so everything that includes them needs both flags.
	add_compile_options(-msimd128 -msse4.2)
endif()

# ---- bgfx (renderer: Vulkan / Metal / D3D11 / D3D12 / GLES / WebGL) ----
set(BGFX_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(BGFX_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(BGFX_INSTALL OFF CACHE BOOL "" FORCE)
set(BGFX_CUSTOM_TARGETS OFF CACHE BOOL "" FORCE)
# shaderc: the editor runs it to compile a project's own shaders. The Windows cross-build makes shaderc.exe for the
# Windows editor.
set(BGFX_BUILD_TOOLS ON CACHE BOOL "" FORCE)
if(EMSCRIPTEN)
	# A web build (emcmake cmake ..., see tools/web/build_native.sh) runs in a browser: shaderc is a desktop tool,
	# and there is a single thread, so bgfx renders on the thread that calls frame().
	set(BGFX_BUILD_TOOLS OFF CACHE BOOL "" FORCE)
	set(BGFX_CONFIG_MULTITHREADED OFF CACHE BOOL "" FORCE)
endif()
set(BGFX_BUILD_TOOLS_GEOMETRY OFF CACHE BOOL "" FORCE)
# texturec: tools/build_player.py compresses a game's pictures with it (BC7 .ktx with mip levels).
set(BGFX_BUILD_TOOLS_TEXTURE ON CACHE BOOL "" FORCE)
set(BGFX_BUILD_TOOLS_BIN2C OFF CACHE BOOL "" FORCE)
set(BGFX_CONFIG_VIDEO OFF CACHE BOOL "" FORCE)
# Linux windows are X11 (XWayland on Wayland desktops). With bgfx's Wayland path compiled in,
# its OpenGL backend hands the X11 display to EGL as a Wayland display and crashes.
set(BGFX_WITH_WAYLAND OFF CACHE BOOL "" FORCE)
add_subdirectory(${TP}/bgfx.cmake bgfx)

# ---- SDL3 (window, input, gamepads, audio device) ----
set(SDL_SHARED OFF CACHE BOOL "" FORCE)
set(SDL_STATIC ON CACHE BOOL "" FORCE)
set(SDL_TEST_LIBRARY OFF CACHE BOOL "" FORCE)
set(SDL_EXAMPLES OFF CACHE BOOL "" FORCE)
set(SDL_INSTALL OFF CACHE BOOL "" FORCE)
add_subdirectory(${TP}/SDL SDL)

# ---- ENet (reliable / unreliable UDP transport) ----
add_subdirectory(${TP}/enet enet)

# ---- Jolt Physics through the JoltC C API ----
set(JPH_BUILD_SHARED OFF CACHE BOOL "" FORCE)
set(JPH_SAMPLES OFF CACHE BOOL "" FORCE)
set(JPH_TESTS OFF CACHE BOOL "" FORCE)
set(JPH_INSTALL OFF CACHE BOOL "" FORCE)
set(INTERPROCEDURAL_OPTIMIZATION OFF CACHE BOOL "" FORCE)
# Bit-identical simulation is what makes client-side physics prediction converge.
set(CROSS_PLATFORM_DETERMINISTIC ON CACHE BOOL "" FORCE)
set(USE_AVX OFF CACHE BOOL "" FORCE)
set(USE_AVX2 OFF CACHE BOOL "" FORCE)
set(USE_FMADD OFF CACHE BOOL "" FORCE)
set(USE_F16C OFF CACHE BOOL "" FORCE)
set(USE_LZCNT OFF CACHE BOOL "" FORCE)
set(USE_TZCNT OFF CACHE BOOL "" FORCE)
set(FLOATING_POINT_EXCEPTIONS_ENABLED OFF CACHE BOOL "" FORCE)
set(DEBUG_RENDERER_IN_DEBUG_AND_RELEASE OFF CACHE BOOL "" FORCE)
set(DEBUG_RENDERER_IN_DISTRIBUTION OFF CACHE BOOL "" FORCE)
set(PROFILER_IN_DEBUG_AND_RELEASE OFF CACHE BOOL "" FORCE)
set(JPH_USE_DX12 OFF CACHE BOOL "" FORCE)
set(JPH_USE_VK OFF CACHE BOOL "" FORCE)
set(JPH_USE_MTL OFF CACHE BOOL "" FORCE)
if(EMSCRIPTEN)
	# WebAssembly SIMD: every current browser has it, and Jolt is much faster with it.
	set(USE_WASM_SIMD ON CACHE BOOL "" FORCE)
endif()
add_subdirectory(${TP}/joltc joltc)

# Focused diagnostic instrumentation: only the convex dispatch translation unit is rebuilt with Jolt's
# external profiler. Production builds leave it off. Callbacks are thread-local and set only during queries.
option(TESSERA_PROFILE_CONVEX_QUERIES "Expose Jolt convex and EPA scopes to the engine profiler" OFF)
if(TESSERA_PROFILE_CONVEX_QUERIES)
	get_target_property(_tessera_jolt_sources Jolt SOURCES)
	foreach(_tessera_jolt_source IN LISTS _tessera_jolt_sources)
		if(_tessera_jolt_source MATCHES "/ConvexShape\\.cpp$")
			set_source_files_properties(${_tessera_jolt_source}
				TARGET_DIRECTORY Jolt PROPERTIES COMPILE_DEFINITIONS JPH_EXTERNAL_PROFILE SKIP_PRECOMPILE_HEADERS ON)
		endif()
	endforeach()
endif()
# Preserve Jolt's registered fallback when installing query-only shape specializations. The upstream header
# exposes registration but no lookup; add a read-only inline accessor to the fetched dependency.
get_target_property(_tessera_jolt_sources Jolt SOURCES)
foreach(_tessera_jolt_source IN LISTS _tessera_jolt_sources)
	if(_tessera_jolt_source MATCHES "/CollisionDispatch\\.cpp$")
		get_filename_component(_tessera_collision_dir ${_tessera_jolt_source} DIRECTORY)
		set(_tessera_dispatch_header "${_tessera_collision_dir}/CollisionDispatch.h")
		file(READ ${_tessera_dispatch_header} _tessera_dispatch_text)
		if(NOT _tessera_dispatch_text MATCHES "sGetCollideShape")
			string(REPLACE "\nprivate:" "\n\t// Tessera: preserve the original dispatcher for query-only specializations.\n\tstatic CollideShape sGetCollideShape(EShapeSubType a, EShapeSubType b) { return sCollideShape[(int)a][(int)b]; }\nprivate:" _tessera_dispatch_text "${_tessera_dispatch_text}")
			file(WRITE ${_tessera_dispatch_header} "${_tessera_dispatch_text}")
		endif()
	endif()
endforeach()

# Recast/Detour v1.6.0, vendored at 6dc1667f580357e8a2154c28b7867bea7e8ad3a7.
# Include the objects in our existing archive so all desktop/web consumers keep the same link interface.
file(GLOB TESSERA_RECAST_SOURCES CONFIGURE_DEPENDS ${TP}/recastnavigation/Recast/Source/*.cpp ${TP}/recastnavigation/Detour/Source/*.cpp)
add_library(tessera_navigation OBJECT tessera_navigation.cpp ${TESSERA_RECAST_SOURCES})
target_compile_features(tessera_navigation PRIVATE cxx_std_17)
target_include_directories(tessera_navigation PRIVATE ${TP}/recastnavigation/Recast/Include ${TP}/recastnavigation/Detour/Include ${TP}/joltc/include)
target_link_libraries(tessera_navigation PRIVATE Jolt)

add_library(tessera_collision_support OBJECT tessera_collision_profile.cpp tessera_overlap_contacts.cpp)
target_compile_features(tessera_collision_support PRIVATE cxx_std_17)
target_link_libraries(tessera_collision_support PRIVATE Jolt)

# Soft bodies (cloth, jelly) reach Jolt's C++ soft body settings, which joltc does not cover.
add_library(tessera_softbody OBJECT tessera_softbody.cpp)
target_compile_features(tessera_softbody PRIVATE cxx_std_17)
target_include_directories(tessera_softbody PRIVATE ${TP}/joltc/include)
target_link_libraries(tessera_softbody PRIVATE Jolt)

# ---- Opus (voice chat codec), compiled into the shim so there is no extra archive to link ----
set(OPUS_BUILD_SHARED_LIBRARY OFF CACHE BOOL "" FORCE)
set(OPUS_BUILD_TESTING OFF CACHE BOOL "" FORCE)
set(OPUS_BUILD_PROGRAMS OFF CACHE BOOL "" FORCE)
set(OPUS_INSTALL_PKG_CONFIG_MODULE OFF CACHE BOOL "" FORCE)
set(OPUS_INSTALL_CMAKE_CONFIG_MODULE OFF CACHE BOOL "" FORCE)
if(MSVC)
	set(OPUS_STATIC_RUNTIME ON CACHE BOOL "" FORCE)
endif()
if(MSVC AND CMAKE_C_COMPILER_ID MATCHES "Clang")
	# Opus leaves out the per-file SSE4.1/AVX2 switches for Microsoft's compiler, and clang-cl needs them.
	set(OPUS_DISABLE_INTRINSICS ON CACHE BOOL "" FORCE)
endif()
add_subdirectory(${TP}/opus opus EXCLUDE_FROM_ALL)

# ---- Tessera shim: Dear ImGui (docking) + ImGuizmo + stb_image + cgltf ----
add_library(tessera_native STATIC
	${TP}/cimgui/cimgui.cpp
	${TP}/cimgui/imgui/imgui.cpp
	${TP}/cimgui/imgui/imgui_draw.cpp
	${TP}/cimgui/imgui/imgui_tables.cpp
	${TP}/cimgui/imgui/imgui_widgets.cpp
	${TP}/cimgui/imgui/imgui_demo.cpp
	${TP}/cimgui/imgui/backends/imgui_impl_sdl3.cpp
	${TP}/ImGuizmo/src/ImGuizmo.cpp
	${TP}/TextEdit/TextEditor.cpp
	${TP}/TextEdit/extras/TrieAutoComplete.cpp
	tessera_native.cpp
	tessera_code.cpp
	tessera_bake.cpp
	tessera_rig.cpp
	tessera_assets.c
	tessera_modelimport.c
	tessera_pack.c
	tessera_guard.c
	tessera_physics.cpp
	$<TARGET_OBJECTS:tessera_navigation>
	$<TARGET_OBJECTS:tessera_collision_support>
	$<TARGET_OBJECTS:tessera_softbody>
	tessera_audio.c
	tessera_web.c
	tessera_http.c
	tessera_network.c
	$<TARGET_OBJECTS:opus>
)
add_dependencies(tessera_native Jolt)
target_compile_features(tessera_native PRIVATE cxx_std_20)
target_include_directories(tessera_native PRIVATE
	${TP}/enet/include
	${TP}/cimgui
	${TP}/cimgui/imgui
	${TP}/cimgui/imgui/backends
	${TP}/ImGuizmo/src
	${TP}/TextEdit
	${TP}/stb
	${TP}/miniaudio
	${TP}/opus/include
	${TP}/cgltf
	${TP}/joltc/include
	${TP}/bgfx.cmake/bgfx/examples/common/imgui
)
target_compile_definitions(tessera_native PRIVATE
	IMGUI_DISABLE_OBSOLETE_FUNCTIONS=1
	"IMGUI_IMPL_API=extern \"C\""
)
target_link_libraries(tessera_native PRIVATE bgfx bx SDL3::SDL3-static)


# ---- Model import settings step (docs/model-import.md), for tools/build_player.py ----
if(NOT EMSCRIPTEN)
	add_executable(tessera_modelsettings tessera_modelsettings.c tessera_modelimport.c)
	target_include_directories(tessera_modelsettings PRIVATE ${TP}/cgltf)
	if(NOT MSVC)
		target_link_libraries(tessera_modelsettings PRIVATE m)
	endif()
endif()

# ---- Model converter (editor tool): FBX, OBJ, DAE, STL, PLY and 3DS to .glb, through Assimp ----
# The editor and tools/convert_models.py run tessera_modelconv as a program of its own (docs/model-import.md); games
# never link Assimp.
if(NOT EMSCRIPTEN)
	set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
	set(ASSIMP_BUILD_TESTS OFF CACHE BOOL "" FORCE)
	set(ASSIMP_BUILD_ASSIMP_TOOLS OFF CACHE BOOL "" FORCE)
	set(ASSIMP_BUILD_SAMPLES OFF CACHE BOOL "" FORCE)
	set(ASSIMP_BUILD_DOCS OFF CACHE BOOL "" FORCE)
	set(ASSIMP_INSTALL OFF CACHE BOOL "" FORCE)
	set(ASSIMP_WARNINGS_AS_ERRORS OFF CACHE BOOL "" FORCE)
	set(ASSIMP_BUILD_USE_CCACHE OFF CACHE BOOL "" FORCE)
	set(ASSIMP_INJECT_DEBUG_POSTFIX OFF CACHE BOOL "" FORCE)
	# Its own zlib, so the tool needs nothing installed on the machine it runs on.
	set(ASSIMP_BUILD_ZLIB ON CACHE BOOL "" FORCE)
	set(ASSIMP_BUILD_ALL_IMPORTERS_BY_DEFAULT OFF CACHE BOOL "" FORCE)
	set(ASSIMP_BUILD_ALL_EXPORTERS_BY_DEFAULT OFF CACHE BOOL "" FORCE)
	# The glTF exporter shares code with the glTF importer, so that is built too.
	foreach(format FBX OBJ COLLADA STL PLY 3DS GLTF)
		set(ASSIMP_BUILD_${format}_IMPORTER ON CACHE BOOL "" FORCE)
	endforeach()
	set(ASSIMP_BUILD_GLTF_EXPORTER ON CACHE BOOL "" FORCE)
	add_subdirectory(${TP}/assimp assimp EXCLUDE_FROM_ALL)
	add_executable(tessera_modelconv tessera_modelconv.cpp)
	target_compile_features(tessera_modelconv PRIVATE cxx_std_17)
	target_link_libraries(tessera_modelconv PRIVATE assimp)
endif()
