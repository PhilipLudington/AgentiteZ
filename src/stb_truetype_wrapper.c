// stb_truetype_wrapper.c
// Custom wrapper for stb_truetype with Zig allocator integration
// Solves malloc issues with packFontRanges API

#include <stddef.h>

// Forward declarations for Zig-provided allocator functions
extern void* zig_stb_alloc(size_t size);
extern void zig_stb_free(void* ptr);

// Define stb_truetype allocator macros
// Note: The second parameter (u) is the user context, which stb_truetype passes as NULL
// We ignore it since we use a thread-local allocator in Zig
#define STBTT_malloc(x,u)  zig_stb_alloc(x)
#define STBTT_free(x,u)    zig_stb_free(x)

// Now include stb_truetype implementation with our custom allocators
#define STB_TRUETYPE_IMPLEMENTATION
#include "stb_truetype.h"
