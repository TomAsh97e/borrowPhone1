# Host build of the on-device range interpreter, used by run_eval.mjs.
cmake_minimum_required(VERSION 3.14)
project(RangeEval CXX C)

set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_COMMON OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TOOLS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_SERVER OFF CACHE BOOL "" FORCE)

set(ROOT ${CMAKE_CURRENT_SOURCE_DIR}/../..)
add_subdirectory(${ROOT}/third_party/llama.cpp ${CMAKE_CURRENT_BINARY_DIR}/llama)

add_executable(range_eval eval_host.cpp ${ROOT}/entry/src/main/cpp/range_model.cpp)
target_include_directories(range_eval PRIVATE ${ROOT}/entry/src/main/cpp)
target_link_libraries(range_eval PRIVATE llama)
