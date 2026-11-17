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
// Emscripten 7 (LLVM 23) libunwind no longer defines it; it keeps the landing
// pad context behind _Unwind_GetWasmLPadContext. This is the libunwind
// implementation (LLVM Unwind-wasm.c) on top of that accessor.

#if defined(__EMSCRIPTEN__) && defined(__WASM_EXCEPTIONS__)

#include <unwind.h>
#include <unwind_wasm.h>

extern "C" {

_Unwind_Reason_Code __gxx_personality_wasm0(int version, _Unwind_Action actions, uint64_t exception_class,
		_Unwind_Exception *exception_object, _Unwind_Context *context);

__attribute__((weak)) _Unwind_Reason_Code _Unwind_CallPersonality(void *exception_ptr) {
	_Unwind_Exception *exception_object = (_Unwind_Exception *)exception_ptr;
	_Unwind_LandingPadContext *lpad_context = _Unwind_GetWasmLPadContext();
	// Reset the selector.
	lpad_context->selector = 0;
	// Wasm has no two-phase unwinding: only the search phase is run here.
	return __gxx_personality_wasm0(1, _UA_SEARCH_PHASE, exception_object->exception_class, exception_object,
			(_Unwind_Context *)lpad_context);
}

} // extern "C"

#endif
