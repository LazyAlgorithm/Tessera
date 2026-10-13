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
set(BGFX_BUILD_TOOLS_TEXTURE OFF CACHE BOOL "" FORCE)
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

# ---- Opus (voice chat codec), compiled into the shim so there is no extra archive to link ----
set(OPUS_BUILD_SHARED_LIBRARY OFF CACHE BOOL "" FORCE)
set(OPUS_BUILD_TESTING OFF CACHE BOOL "" FORCE)
set(OPUS_BUILD_PROGRAMS OFF CACHE BOOL "" FORCE)
set(OPUS_INSTALL_PKG_CONFIG_MODULE OFF CACHE BOOL "" FORCE)
set(OPUS_INSTALL_CMAKE_CONFIG_MODULE OFF CACHE BOOL "" FORCE)
if(MSVC)
	set(OPUS_STATIC_RUNTIME ON CACHE BOOL "" FORCE)
endif()
if(CMAKE_CROSSCOMPILING AND MSVC)
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
	tessera_assets.c
	tessera_pack.c
	tessera_guard.c
	tessera_physics.cpp
	tessera_audio.c
	tessera_web.c
	$<TARGET_OBJECTS:opus>
)
target_compile_features(tessera_native PRIVATE cxx_std_20)
target_include_directories(tessera_native PRIVATE
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
