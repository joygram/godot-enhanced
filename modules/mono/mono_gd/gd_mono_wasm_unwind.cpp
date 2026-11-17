/**************************************************************************/
/*  gd_mono_wasm_unwind.cpp                                               */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
/*                                                                        */
/* Permission is hereby granted, free of charge, to any person obtaining  */
/* a copy of this software and associated documentation files (the       */
/* "Software"), to deal in the Software without restriction, including   */
/* without limitation the rights to use, copy, modify, merge, publish,    */
/* distribute, sublicense, and/or sell copies of the Software, and to     */
/* permit persons to whom the Software is furnished to do so, subject to  */
/* the following conditions:                                              */
/*                                                                        */
/* The above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.        */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

// .NET 11 Mono runtime pack objects (libmono-wasm-eh-wasm.a) were compiled by the
// Emscripten 6 clang, whose Wasm EH catch pads call _Unwind_CallPersonality.
// Emscripten 7 (LLVM 23) moved that function from libunwind into libc++abi as
// __gxx_wasm_personality_v0 (same body: reset selector, search-phase personality).
// Keep the old name for the prebuilt pack.

#if defined(__EMSCRIPTEN__) && defined(__WASM_EXCEPTIONS__)

#include <unwind.h>

extern "C" {

_Unwind_Reason_Code __gxx_wasm_personality_v0(void *exception_ptr);

__attribute__((weak)) _Unwind_Reason_Code _Unwind_CallPersonality(void *exception_ptr) {
	return __gxx_wasm_personality_v0(exception_ptr);
}

} // extern "C"

#endif
