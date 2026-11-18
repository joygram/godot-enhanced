/**************************************************************************/
/*  gdscript_prebuild.h                                                   */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
/*                                                                        */
/* Permission is hereby granted, free of charge, to any person obtaining  */
/* a copy of this software and associated documentation files (the        */
/* "Software"), to deal in the Software without restriction, including    */
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

#pragma once

#include "core/string/ustring.h"
#include "core/templates/vector.h"

class GDScript;

// godot-enhanced: GDScript prebuild (script_export_mode = Prebuilt).
// Export stores the compiled class tree (bytecode + class data) next to the binary tokens.
// At runtime GDScript::reload() applies it instead of parse / analyze / compile, and falls back to the
// tokens when the data is unusable (other engine build, unsupported constant, missing dependency).
// Design: patches/gdscript-prebuild.md
class GDScriptPrebuild {
	// Nested so they share the friendship GDScript / GDScriptFunction / GDScriptCache grant.
	struct Saver;
	struct Applier;

public:
	static constexpr uint32_t FORMAT_VERSION = 2; // 2 = 연산 캐시 칸 고정 2칸(플랫폼 무관 명령 길이)

	// Editor: serialize a fully compiled script. Empty result + r_error when it cannot be stored.
	static Vector<uint8_t> save(const GDScript *p_script, String &r_error);
	// Runtime: fill a GDScript (path set, not compiled) from saved data.
	static Error apply(GDScript *p_script, const Vector<uint8_t> &p_data);

	// .gdc container: "GDPB", format version, engine build, tokens, prebuilt data.
	static Vector<uint8_t> pack(const Vector<uint8_t> &p_tokens, const Vector<uint8_t> &p_prebuilt);
	// Splits a container. Returns false (outputs untouched) when p_file is plain binary tokens.
	static bool unpack(const Vector<uint8_t> &p_file, Vector<uint8_t> &r_tokens, Vector<uint8_t> &r_prebuilt);
	// Binary tokens of a .gdc file, container or not.
	static Vector<uint8_t> tokens_of(const Vector<uint8_t> &p_file);
};
