/**************************************************************************/
/*  gdscript_prebuild.cpp                                                 */
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

#include "gdscript_prebuild.h"

#include "gdscript.h"
#include "gdscript_cache.h"
#include "gdscript_function.h"
#include "gdscript_utility_functions.h"

#include "core/io/marshalls.h"
#include "core/io/resource_loader.h"
#include "core/object/class_db.h"
#include "core/object/method_bind.h"
#include "core/version.h"

namespace {

constexpr uint8_t MAGIC[4] = { 'G', 'D', 'P', 'B' };

// Compatibility key: same enhanced build, same opcode / operator / type tables.
String compat_key() {
	return vformat("%s|%d|%d|%d|%d", GODOT_VERSION_FULL_BUILD, GDScriptPrebuild::FORMAT_VERSION,
			(int)GDScriptFunction::OPCODE_END, (int)Variant::OP_MAX, (int)Variant::VARIANT_MAX);
}

// ---------------------------------------------------------------- byte streams

struct Writer {
	Vector<uint8_t> data;

	void u8(uint8_t p_v) { data.push_back(p_v); }
	void u32(uint32_t p_v) {
		uint8_t b[4];
		encode_uint32(p_v, b);
		for (uint8_t c : b) {
			data.push_back(c);
		}
	}
	void i32(int32_t p_v) { u32((uint32_t)p_v); }
	void bytes(const Vector<uint8_t> &p_b) {
		u32(p_b.size());
		data.append_array(p_b);
	}
	void str(const String &p_s) {
		CharString cs = p_s.utf8();
		u32(cs.length());
		for (int i = 0; i < cs.length(); i++) {
			data.push_back((uint8_t)cs[i]);
		}
	}
	// Plain Variant (no objects). Caller checks with has_object().
	bool var(const Variant &p_v) {
		int len = 0;
		if (encode_variant(p_v, nullptr, len, false) != OK) {
			return false;
		}
		Vector<uint8_t> b;
		b.resize(len);
		if (encode_variant(p_v, b.ptrw(), len, false) != OK) {
			return false;
		}
		bytes(b);
		return true;
	}
};

struct Reader {
	const uint8_t *p = nullptr;
	int size = 0;
	int pos = 0;
	bool fail = false;

	bool need(int p_n) {
		if (fail || pos + p_n > size || p_n < 0) {
			fail = true;
			return false;
		}
		return true;
	}
	uint8_t u8() {
		if (!need(1)) {
			return 0;
		}
		return p[pos++];
	}
	uint32_t u32() {
		if (!need(4)) {
			return 0;
		}
		uint32_t v = decode_uint32(p + pos);
		pos += 4;
		return v;
	}
	int32_t i32() { return (int32_t)u32(); }
	Vector<uint8_t> bytes() {
		Vector<uint8_t> b;
		int n = (int)u32();
		if (!need(n)) {
			return b;
		}
		b.resize(n);
		memcpy(b.ptrw(), p + pos, n);
		pos += n;
		return b;
	}
	String str() {
		int n = (int)u32();
		if (!need(n)) {
			return String();
		}
		String s = String::utf8((const char *)p + pos, n);
		pos += n;
		return s;
	}
	Variant var() {
		Vector<uint8_t> b = bytes();
		Variant v;
		if (fail || decode_variant(v, b.ptr(), b.size(), nullptr, false) != OK) {
			fail = true;
		}
		return v;
	}
};

bool has_object(const Variant &p_v) {
	switch (p_v.get_type()) {
		case Variant::OBJECT:
			return p_v.get_validated_object() != nullptr;
		case Variant::ARRAY: {
			Array a = p_v;
			for (int i = 0; i < a.size(); i++) {
				if (has_object(a[i])) {
					return true;
				}
			}
			return false;
		}
		case Variant::DICTIONARY: {
			Dictionary d = p_v;
			for (const KeyValue<Variant, Variant> &kv : d) {
				if (has_object(kv.key) || has_object(kv.value)) {
					return true;
				}
			}
			return false;
		}
		case Variant::CALLABLE:
		case Variant::SIGNAL:
			return true; // Bound to objects; not stored.
		default:
			return false;
	}
}

// ---------------------------------------------------------------- pointer tables ↔ keys

struct FnKey {
	int a = 0;
	int b = 0;
	int c = 0;
	StringName name;
};

struct ReverseTables {
	bool built = false;
	HashMap<uintptr_t, FnKey> operators, setters, getters, keyed_setters, keyed_getters, indexed_setters,
			indexed_getters, builtin_methods, constructors, utilities, gds_utilities;
};

ReverseTables &reverse_tables() {
	static ReverseTables t;
	if (t.built) {
		return t;
	}
	t.built = true;
	for (int op = 0; op < Variant::OP_MAX; op++) {
		for (int a = 0; a < Variant::VARIANT_MAX; a++) {
			for (int b = 0; b < Variant::VARIANT_MAX; b++) {
				Variant::ValidatedOperatorEvaluator f = Variant::get_validated_operator_evaluator((Variant::Operator)op, (Variant::Type)a, (Variant::Type)b);
				if (f && !t.operators.has((uintptr_t)f)) {
					t.operators[(uintptr_t)f] = FnKey{ op, a, b, StringName() };
				}
			}
		}
	}
	for (int type = 0; type < Variant::VARIANT_MAX; type++) {
		Variant::Type vt = (Variant::Type)type;
		List<StringName> members;
		Variant::get_member_list(vt, &members);
		for (const StringName &m : members) {
			if (Variant::ValidatedSetter s = Variant::get_member_validated_setter(vt, m)) {
				t.setters[(uintptr_t)s] = FnKey{ type, 0, 0, m };
			}
			if (Variant::ValidatedGetter g = Variant::get_member_validated_getter(vt, m)) {
				t.getters[(uintptr_t)g] = FnKey{ type, 0, 0, m };
			}
		}
		if (Variant::ValidatedKeyedSetter f = Variant::get_member_validated_keyed_setter(vt)) {
			t.keyed_setters[(uintptr_t)f] = FnKey{ type, 0, 0, StringName() };
		}
		if (Variant::ValidatedKeyedGetter f = Variant::get_member_validated_keyed_getter(vt)) {
			t.keyed_getters[(uintptr_t)f] = FnKey{ type, 0, 0, StringName() };
		}
		if (Variant::ValidatedIndexedSetter f = Variant::get_member_validated_indexed_setter(vt)) {
			t.indexed_setters[(uintptr_t)f] = FnKey{ type, 0, 0, StringName() };
		}
		if (Variant::ValidatedIndexedGetter f = Variant::get_member_validated_indexed_getter(vt)) {
			t.indexed_getters[(uintptr_t)f] = FnKey{ type, 0, 0, StringName() };
		}
		List<StringName> methods;
		Variant::get_builtin_method_list(vt, &methods);
		for (const StringName &m : methods) {
			if (Variant::ValidatedBuiltInMethod f = Variant::get_validated_builtin_method(vt, m)) {
				t.builtin_methods[(uintptr_t)f] = FnKey{ type, 0, 0, m };
			}
		}
		for (int i = 0; i < Variant::get_constructor_count(vt); i++) {
			if (Variant::ValidatedConstructor f = Variant::get_validated_constructor(vt, i)) {
				t.constructors[(uintptr_t)f] = FnKey{ type, i, 0, StringName() };
			}
		}
	}
	List<StringName> utils;
	Variant::get_utility_function_list(&utils);
	for (const StringName &u : utils) {
		if (Variant::ValidatedUtilityFunction f = Variant::get_validated_utility_function(u)) {
			t.utilities[(uintptr_t)f] = FnKey{ 0, 0, 0, u };
		}
	}
	List<StringName> gds_utils;
	GDScriptUtilityFunctions::get_function_list(&gds_utils);
	for (const StringName &u : gds_utils) {
		if (GDScriptUtilityFunctions::FunctionPtr f = GDScriptUtilityFunctions::get_function(u)) {
			t.gds_utilities[(uintptr_t)f] = FnKey{ 0, 0, 0, u };
		}
	}
	return t;
}

template <typename T>
bool save_table(Writer &w, const Vector<T> &p_table, const HashMap<uintptr_t, FnKey> &p_keys, String &r_error, const char *p_what) {
	w.u32(p_table.size());
	for (const T &f : p_table) {
		const FnKey *k = p_keys.getptr((uintptr_t)f);
		if (!k) {
			r_error = vformat("unknown %s pointer", p_what);
			return false;
		}
		w.i32(k->a);
		w.i32(k->b);
		w.i32(k->c);
		w.str(k->name);
	}
	return true;
}

} // namespace

// ---------------------------------------------------------------- save

struct GDScriptPrebuild::Saver {
	const GDScript *root = nullptr;
	String error;

	bool constant(Writer &w, const Variant &p_v) {
		if (p_v.get_type() == Variant::OBJECT) {
			Object *obj = p_v.get_validated_object();
			if (!obj) {
				w.u8(4); // Null object.
				return true;
			}
			if (GDScript *gd = Object::cast_to<GDScript>(obj)) {
				if (gd->get_script_path().is_empty() || gd->get_script_path().contains("::")) {
					error = "built-in script constant";
					return false;
				}
				w.u8(1);
				w.str(gd->get_script_path());
				w.str(gd->is_root_script() ? String() : gd->get_fully_qualified_name());
				return true;
			}
			if (GDScriptNativeClass *nc = Object::cast_to<GDScriptNativeClass>(obj)) {
				w.u8(2);
				w.str(nc->get_name());
				return true;
			}
			if (Resource *res = Object::cast_to<Resource>(obj)) {
				const String &path = res->get_path();
				if (path.is_empty() || path.contains("::")) {
					error = vformat("unsaved resource constant (%s)", res->get_class());
					return false;
				}
				w.u8(3);
				w.str(path);
				return true;
			}
			error = vformat("object constant (%s)", obj->get_class());
			return false;
		}
		if (has_object(p_v)) {
			error = "container constant holding objects";
			return false;
		}
		w.u8(0);
		if (!w.var(p_v)) {
			error = "constant not encodable";
			return false;
		}
		return true;
	}

	bool type(Writer &w, const GDScriptDataType &p_t) {
		w.u8((uint8_t)p_t.kind);
		w.u32((uint32_t)p_t.builtin_type);
		w.str(p_t.native_type);
		if (p_t.kind == GDScriptDataType::SCRIPT || p_t.kind == GDScriptDataType::GDSCRIPT) {
			Ref<Script> s = Ref<Script>(p_t.script_type);
			if (!constant(w, s)) {
				return false;
			}
		}
		w.u32(p_t.container_element_types.size());
		for (const GDScriptDataType &e : p_t.container_element_types) {
			if (!type(w, e)) {
				return false;
			}
		}
		return true;
	}

	bool function(Writer &w, const GDScriptFunction *f) {
		const ReverseTables &t = reverse_tables();
		const HashMap<StringName, int> &global_map = GDScriptLanguage::get_singleton()->get_global_map();
		HashMap<int, StringName> global_names_by_index;
		for (const KeyValue<StringName, int> &kv : global_map) {
			global_names_by_index[kv.value] = kv.key;
		}

		w.str(f->name);
		w.u8(f->_static);
		w.var(Dictionary(f->method_info));
		if (has_object(f->rpc_config)) {
			error = "rpc config with objects";
			return false;
		}
		w.var(f->rpc_config);
		w.u32(f->argument_types.size());
		for (const GDScriptDataType &a : f->argument_types) {
			if (!type(w, a)) {
				return false;
			}
		}
		if (!type(w, f->return_type)) {
			return false;
		}
		w.i32(f->_initial_line);
		w.i32(f->_argument_count);
		w.i32(f->_vararg_index);
		w.i32(f->_stack_size);
		w.i32(f->_instruction_args_size);

		w.u32(f->code.size());
		for (int c : f->code) {
			w.i32(c);
		}
		w.u32(f->global_index_offsets.size());
		for (int off : f->global_index_offsets) {
			const StringName *gname = global_names_by_index.getptr(f->code[off]);
			if (!gname) {
				error = "global index without name";
				return false;
			}
			w.i32(off);
			w.str(*gname);
		}
		w.u32(f->named_global_offsets.size());
		for (int off : f->named_global_offsets) {
			w.i32(off);
		}
		w.u32(f->default_arguments.size());
		for (int d : f->default_arguments) {
			w.i32(d);
		}
		w.u32(f->constants.size());
		for (const Variant &c : f->constants) {
			if (!constant(w, c)) {
				return false;
			}
		}
		w.u32(f->constant_map.size());
		for (const KeyValue<StringName, Variant> &kv : f->constant_map) {
			w.str(kv.key);
			if (!constant(w, kv.value)) {
				return false;
			}
		}
		w.u32(f->global_names.size());
		for (const StringName &n : f->global_names) {
			w.str(n);
		}
		if (!save_table(w, f->operator_funcs, t.operators, error, "operator") ||
				!save_table(w, f->setters, t.setters, error, "setter") ||
				!save_table(w, f->getters, t.getters, error, "getter") ||
				!save_table(w, f->keyed_setters, t.keyed_setters, error, "keyed setter") ||
				!save_table(w, f->keyed_getters, t.keyed_getters, error, "keyed getter") ||
				!save_table(w, f->indexed_setters, t.indexed_setters, error, "indexed setter") ||
				!save_table(w, f->indexed_getters, t.indexed_getters, error, "indexed getter") ||
				!save_table(w, f->builtin_methods, t.builtin_methods, error, "builtin method") ||
				!save_table(w, f->constructors, t.constructors, error, "constructor") ||
				!save_table(w, f->utilities, t.utilities, error, "utility") ||
				!save_table(w, f->gds_utilities, t.gds_utilities, error, "gdscript utility")) {
			return false;
		}
		w.u32(f->methods.size());
		for (const MethodBind *mb : f->methods) {
			w.str(mb->get_instance_class());
			w.str(mb->get_name());
		}
		w.u32(f->temporary_slots.size());
		for (const Pair<int, Variant::Type> &ts : f->temporary_slots) {
			w.i32(ts.first);
			w.u32((uint32_t)ts.second);
		}
		w.u32(f->lambdas.size());
		for (const GDScriptFunction *l : f->lambdas) {
			const GDScript::LambdaInfo *info = l->_script ? l->_script->lambda_info.getptr(const_cast<GDScriptFunction *>(l)) : nullptr;
			w.i32(info ? info->capture_count : 0);
			w.u8(info ? info->use_self : 0);
			w.str(l->_script ? l->_script->get_fully_qualified_name() : String());
			if (!function(w, l)) {
				return false;
			}
		}
		return true;
	}

	bool optional_function(Writer &w, const GDScriptFunction *f) {
		w.u8(f != nullptr);
		return f == nullptr || function(w, f);
	}

	bool member_info(Writer &w, const StringName &p_name, const GDScript::MemberInfo &p_info) {
		w.str(p_name);
		w.i32(p_info.index);
		w.str(p_info.setter);
		w.str(p_info.getter);
		if (!type(w, p_info.data_type)) {
			return false;
		}
		Dictionary pi = Dictionary(p_info.property_info);
		if (has_object(pi)) {
			error = "property info with objects";
			return false;
		}
		w.var(pi);
		return true;
	}

	// Tree first (names), so apply() can create every inner class before resolving references.
	void tree(Writer &w, const GDScript *s) {
		w.str(s->local_name);
		w.str(s->global_name);
		w.str(s->fully_qualified_name);
		w.str(s->simplified_icon_path);
		w.u32(s->subclasses.size());
		for (const KeyValue<StringName, Ref<GDScript>> &kv : s->subclasses) {
			w.str(kv.key);
			tree(w, kv.value.ptr());
		}
	}

	bool body(Writer &w, const GDScript *s) {
		w.u8(s->tool);
		w.u8(s->_is_abstract);
		w.str(s->native.is_valid() ? String(s->native->get_name()) : String());
		w.u8(s->base.is_valid());
		if (s->base.is_valid() && !constant(w, s->base)) {
			return false;
		}
		w.u32(s->member_indices.size());
		for (const KeyValue<StringName, GDScript::MemberInfo> &kv : s->member_indices) {
			if (!member_info(w, kv.key, kv.value)) {
				return false;
			}
		}
		w.u32(s->members.size());
		for (const StringName &m : s->members) {
			w.str(m);
		}
		w.u32(s->static_variables_indices.size());
		for (const KeyValue<StringName, GDScript::MemberInfo> &kv : s->static_variables_indices) {
			if (!member_info(w, kv.key, kv.value)) {
				return false;
			}
		}
		w.u32(s->constants.size());
		for (const KeyValue<StringName, Variant> &kv : s->constants) {
			w.str(kv.key);
			if (!constant(w, kv.value)) {
				return false;
			}
		}
		w.u32(s->_signals.size());
		for (const KeyValue<StringName, MethodInfo> &kv : s->_signals) {
			w.str(kv.key);
			w.var(Dictionary(kv.value));
		}
		if (has_object(s->rpc_config)) {
			error = "rpc config with objects";
			return false;
		}
		w.var(s->rpc_config);
		w.u32(s->member_functions.size());
		for (const KeyValue<StringName, GDScriptFunction *> &kv : s->member_functions) {
			w.str(kv.key);
			if (!function(w, kv.value)) {
				return false;
			}
		}
		w.str(s->initializer ? String(s->initializer->get_name()) : String());
		if (!optional_function(w, s->implicit_initializer) || !optional_function(w, s->implicit_ready) || !optional_function(w, s->static_initializer)) {
			return false;
		}
		w.u32(s->subclasses.size());
		for (const KeyValue<StringName, Ref<GDScript>> &kv : s->subclasses) {
			w.str(kv.key);
			if (!body(w, kv.value.ptr())) {
				return false;
			}
		}
		return true;
	}
};

// ---------------------------------------------------------------- apply

struct GDScriptPrebuild::Applier {
	GDScript *root = nullptr;
	Reader r;
	String error;

	bool fail(const String &p_error) {
		if (error.is_empty()) {
			error = p_error;
		}
		r.fail = true;
		return false;
	}

	Ref<GDScript> script_ref(const String &p_path, const String &p_fqn) {
		Ref<GDScript> s;
		if (p_path == root->get_script_path()) {
			s = Ref<GDScript>(root);
		} else {
			Error err = OK;
			s = p_fqn.is_empty() ? GDScriptCache::get_shallow_script(p_path, err, root->get_script_path())
								 : GDScriptCache::get_full_script(p_path, err, root->get_script_path());
			if (err != OK || s.is_null()) {
				fail(vformat("missing script %s", p_path));
				return Ref<GDScript>();
			}
		}
		if (!p_fqn.is_empty()) {
			GDScript *inner = s->find_class(p_fqn);
			if (!inner) {
				fail(vformat("missing class %s", p_fqn));
				return Ref<GDScript>();
			}
			return Ref<GDScript>(inner);
		}
		return s;
	}

	Variant constant() {
		uint8_t tag = r.u8();
		switch (tag) {
			case 0:
				return r.var();
			case 1: {
				String path = r.str();
				String fqn = r.str();
				return script_ref(path, fqn);
			}
			case 2: {
				StringName name = r.str();
				const int *idx = GDScriptLanguage::get_singleton()->get_global_map().getptr(name);
				if (!idx) {
					fail(vformat("missing native class %s", name));
					return Variant();
				}
				return GDScriptLanguage::get_singleton()->get_global_array()[*idx];
			}
			case 3: {
				String path = r.str();
				Ref<Resource> res = ResourceLoader::load(path);
				if (res.is_null()) {
					fail(vformat("missing resource %s", path));
				}
				return res;
			}
			case 4:
				return Variant((Object *)nullptr);
			default:
				fail("bad constant tag");
				return Variant();
		}
	}

	GDScriptDataType type() {
		GDScriptDataType t;
		t.kind = (GDScriptDataType::Kind)r.u8();
		t.builtin_type = (Variant::Type)r.u32();
		t.native_type = r.str();
		if (t.kind == GDScriptDataType::SCRIPT || t.kind == GDScriptDataType::GDSCRIPT) {
			Variant s = constant();
			t.script_type_ref = Ref<Script>(s);
			t.script_type = t.script_type_ref.ptr();
		}
		int n = (int)r.u32();
		for (int i = 0; i < n && !r.fail; i++) {
			t.set_container_element_type(i, type());
		}
		return t;
	}

	template <typename T, typename F>
	bool table(Vector<T> &r_table, F p_resolve, const char *p_what) {
		int n = (int)r.u32();
		r_table.resize(n);
		for (int i = 0; i < n && !r.fail; i++) {
			FnKey k;
			k.a = r.i32();
			k.b = r.i32();
			k.c = r.i32();
			k.name = r.str();
			T f = p_resolve(k);
			if (!f) {
				return fail(vformat("unresolved %s %s", p_what, k.name));
			}
			r_table.write[i] = f;
		}
		return !r.fail;
	}

	GDScriptFunction *function(GDScript *p_script) {
		GDScriptFunction *f = memnew(GDScriptFunction);
		f->_script = p_script;
		f->source = p_script->get_script_path();
		f->name = r.str();
		f->_static = r.u8();
		f->method_info = MethodInfo::from_dict(r.var());
		f->rpc_config = r.var();
		int argc = (int)r.u32();
		for (int i = 0; i < argc && !r.fail; i++) {
			f->argument_types.push_back(type());
		}
		f->return_type = type();
		f->_initial_line = r.i32();
		f->_argument_count = r.i32();
		f->_vararg_index = r.i32();
		f->_stack_size = r.i32();
		f->_instruction_args_size = r.i32();

		int code_size = (int)r.u32();
		if (!r.need(code_size * 4)) {
			memdelete(f);
			fail("truncated code");
			return nullptr;
		}
		f->code.resize(code_size);
		for (int i = 0; i < code_size; i++) {
			f->code.write[i] = r.i32();
		}
		int offsets = (int)r.u32();
		const HashMap<StringName, int> &global_map = GDScriptLanguage::get_singleton()->get_global_map();
		for (int i = 0; i < offsets && !r.fail; i++) {
			int off = r.i32();
			StringName gname = r.str();
			const int *idx = global_map.getptr(gname);
			if (!idx || off < 0 || off >= code_size) {
				fail(vformat("missing global %s", gname));
				break;
			}
			f->code.write[off] = *idx;
			f->global_index_offsets.push_back(off);
		}
		Vector<int> named_offsets;
		int named = (int)r.u32();
		for (int i = 0; i < named && !r.fail; i++) {
			int off = r.i32();
			if (off < 0 || off + 2 >= code_size) {
				fail("bad named global offset");
				break;
			}
			named_offsets.push_back(off);
		}
		int defaults = (int)r.u32();
		for (int i = 0; i < defaults && !r.fail; i++) {
			f->default_arguments.push_back(r.i32());
		}
		int constants = (int)r.u32();
		f->constants.resize(constants);
		for (int i = 0; i < constants && !r.fail; i++) {
			f->constants.write[i] = constant();
		}
		int constant_map = (int)r.u32();
		for (int i = 0; i < constant_map && !r.fail; i++) {
			StringName k = r.str();
			f->constant_map.insert(k, constant());
		}
		int names = (int)r.u32();
		f->global_names.resize(names);
		for (int i = 0; i < names && !r.fail; i++) {
			f->global_names.write[i] = r.str();
		}
		// Editor-compiled autoload access (named global) → the game's form (global index), as a runtime
		// compile would emit. Same instruction length: opcode, destination, operand.
		for (int off : named_offsets) {
			int name_idx = f->code[off + 2];
			if (name_idx < 0 || name_idx >= f->global_names.size()) {
				fail("bad named global name");
				break;
			}
			const int *idx = global_map.getptr(f->global_names[name_idx]);
			if (idx) {
				f->code.write[off] = GDScriptFunction::OPCODE_STORE_GLOBAL;
				f->code.write[off + 2] = *idx;
				f->global_index_offsets.push_back(off + 2);
			} else {
				f->named_global_offsets.push_back(off);
			}
		}

		table(f->operator_funcs, [](const FnKey &k) { return Variant::get_validated_operator_evaluator((Variant::Operator)k.a, (Variant::Type)k.b, (Variant::Type)k.c); }, "operator");
		table(f->setters, [](const FnKey &k) { return Variant::get_member_validated_setter((Variant::Type)k.a, k.name); }, "setter");
		table(f->getters, [](const FnKey &k) { return Variant::get_member_validated_getter((Variant::Type)k.a, k.name); }, "getter");
		table(f->keyed_setters, [](const FnKey &k) { return Variant::get_member_validated_keyed_setter((Variant::Type)k.a); }, "keyed setter");
		table(f->keyed_getters, [](const FnKey &k) { return Variant::get_member_validated_keyed_getter((Variant::Type)k.a); }, "keyed getter");
		table(f->indexed_setters, [](const FnKey &k) { return Variant::get_member_validated_indexed_setter((Variant::Type)k.a); }, "indexed setter");
		table(f->indexed_getters, [](const FnKey &k) { return Variant::get_member_validated_indexed_getter((Variant::Type)k.a); }, "indexed getter");
		table(f->builtin_methods, [](const FnKey &k) { return Variant::get_validated_builtin_method((Variant::Type)k.a, k.name); }, "builtin method");
		table(f->constructors, [](const FnKey &k) { return Variant::get_validated_constructor((Variant::Type)k.a, k.b); }, "constructor");
		table(f->utilities, [](const FnKey &k) { return Variant::get_validated_utility_function(k.name); }, "utility");
		table(f->gds_utilities, [](const FnKey &k) { return GDScriptUtilityFunctions::get_function(k.name); }, "gdscript utility");

		int methods = (int)r.u32();
		f->methods.resize(methods);
		for (int i = 0; i < methods && !r.fail; i++) {
			StringName cls = r.str();
			StringName name = r.str();
			MethodBind *mb = ClassDB::get_method(cls, name);
			if (!mb) {
				fail(vformat("missing method %s.%s", cls, name));
				break;
			}
			f->methods.write[i] = mb;
		}
		int slots = (int)r.u32();
		for (int i = 0; i < slots && !r.fail; i++) {
			int idx = r.i32();
			Variant::Type vt = (Variant::Type)r.u32();
			f->temporary_slots.push_back(Pair<int, Variant::Type>(idx, vt));
		}
		int lambdas = (int)r.u32();
		f->lambdas.resize(lambdas);
		for (int i = 0; i < lambdas && !r.fail; i++) {
			int capture_count = r.i32();
			bool use_self = r.u8();
			String owner_fqn = r.str();
			GDScript *owner = owner_fqn.is_empty() ? p_script : root->find_class(owner_fqn);
			if (!owner) {
				fail(vformat("missing lambda owner %s", owner_fqn));
				break;
			}
			GDScriptFunction *l = function(owner);
			if (!l) {
				break;
			}
			owner->lambda_info.insert(l, { capture_count, use_self });
			f->lambdas.write[i] = l;
		}

		if (r.fail) {
			memdelete(f);
			return nullptr;
		}
		finalize(f);
		return f;
	}

	// Same pointer / count setup as GDScriptByteCodeGenerator::write_end().
	static void finalize(GDScriptFunction *f) {
		f->_code_ptr = f->code.is_empty() ? nullptr : f->code.ptrw();
		f->_code_size = f->code.size();
		f->_constants_ptr = f->constants.is_empty() ? nullptr : f->constants.ptrw();
		f->_constant_count = f->constants.size();
		f->_global_names_ptr = f->global_names.is_empty() ? nullptr : f->global_names.ptr();
		f->_global_names_count = f->global_names.size();
		f->_default_arg_count = f->default_arguments.is_empty() ? 0 : f->default_arguments.size() - 1;
		f->_default_arg_ptr = f->default_arguments.is_empty() ? nullptr : f->default_arguments.ptr();
#define GDP_TABLE(m_vec, m_ptr, m_count) \
	f->m_ptr = f->m_vec.is_empty() ? nullptr : f->m_vec.ptr(); \
	f->m_count = f->m_vec.size();
		GDP_TABLE(operator_funcs, _operator_funcs_ptr, _operator_funcs_count)
		GDP_TABLE(setters, _setters_ptr, _setters_count)
		GDP_TABLE(getters, _getters_ptr, _getters_count)
		GDP_TABLE(keyed_setters, _keyed_setters_ptr, _keyed_setters_count)
		GDP_TABLE(keyed_getters, _keyed_getters_ptr, _keyed_getters_count)
		GDP_TABLE(indexed_setters, _indexed_setters_ptr, _indexed_setters_count)
		GDP_TABLE(indexed_getters, _indexed_getters_ptr, _indexed_getters_count)
		GDP_TABLE(builtin_methods, _builtin_methods_ptr, _builtin_methods_count)
		GDP_TABLE(constructors, _constructors_ptr, _constructors_count)
		GDP_TABLE(utilities, _utilities_ptr, _utilities_count)
		GDP_TABLE(gds_utilities, _gds_utilities_ptr, _gds_utilities_count)
#undef GDP_TABLE
		f->_methods_ptr = f->methods.is_empty() ? nullptr : f->methods.ptrw();
		f->_methods_count = f->methods.size();
		f->_lambdas_ptr = f->lambdas.is_empty() ? nullptr : f->lambdas.ptrw();
		f->_lambdas_count = f->lambdas.size();
#ifdef DEBUG_ENABLED
		f->func_cname = (String(f->source) + " - " + String(f->name)).utf8();
		f->_func_cname = f->func_cname.get_data();
#endif
	}

	GDScriptFunction *optional_function(GDScript *p_script) {
		if (!r.u8()) {
			return nullptr;
		}
		return function(p_script);
	}

	bool member_info(StringName &r_name, GDScript::MemberInfo &r_info) {
		r_name = r.str();
		r_info.index = r.i32();
		r_info.setter = r.str();
		r_info.getter = r.str();
		r_info.data_type = type();
		r_info.property_info = PropertyInfo::from_dict(r.var());
		return !r.fail;
	}

	// Mirrors GDScriptCompiler::make_scripts().
	void tree(GDScript *s) {
		s->local_name = r.str();
		s->global_name = r.str();
		s->fully_qualified_name = r.str();
		s->simplified_icon_path = r.str();
		s->subclasses.clear();
		int n = (int)r.u32();
		for (int i = 0; i < n && !r.fail; i++) {
			StringName name = r.str();
			Ref<GDScript> sub = GDScriptLanguage::get_singleton()->get_orphan_subclass(s->fully_qualified_name + "::" + String(name));
			if (sub.is_null()) {
				sub.instantiate();
			}
			sub->_owner = s;
			sub->path = s->path;
			s->subclasses.insert(name, sub);
			tree(sub.ptr());
		}
	}

	// Mirrors GDScriptCompiler::_prepare_compilation() + _compile_class() results.
	bool body(GDScript *s) {
		s->tool = r.u8();
		s->_is_abstract = r.u8();
		StringName native_name = r.str();
		const int *native_idx = GDScriptLanguage::get_singleton()->get_global_map().getptr(native_name);
		if (!native_idx) {
			return fail(vformat("missing native base %s", native_name));
		}
		s->native = GDScriptLanguage::get_singleton()->get_global_array()[*native_idx];
		s->base = Ref<GDScript>();
		if (r.u8()) {
			s->base = Ref<GDScript>(constant());
			if (s->base.is_null()) {
				return fail("missing base script");
			}
		}
		int count = (int)r.u32();
		for (int i = 0; i < count && !r.fail; i++) {
			StringName name;
			GDScript::MemberInfo info;
			member_info(name, info);
			s->member_indices[name] = info;
		}
		count = (int)r.u32();
		for (int i = 0; i < count && !r.fail; i++) {
			s->members.insert(r.str());
		}
		count = (int)r.u32();
		for (int i = 0; i < count && !r.fail; i++) {
			StringName name;
			GDScript::MemberInfo info;
			member_info(name, info);
			s->static_variables_indices[name] = info;
		}
		s->static_variables.resize(s->static_variables_indices.size());
		count = (int)r.u32();
		for (int i = 0; i < count && !r.fail; i++) {
			StringName name = r.str();
			s->constants.insert(name, constant());
		}
		count = (int)r.u32();
		for (int i = 0; i < count && !r.fail; i++) {
			StringName name = r.str();
			s->_signals[name] = MethodInfo::from_dict(r.var());
		}
		s->rpc_config = r.var();
		count = (int)r.u32();
		for (int i = 0; i < count && !r.fail; i++) {
			StringName name = r.str();
			GDScriptFunction *f = function(s);
			if (!f) {
				break;
			}
			s->member_functions[name] = f;
		}
		StringName initializer = r.str();
		if (!r.fail && initializer != StringName()) {
			GDScriptFunction **f = s->member_functions.getptr(initializer);
			s->initializer = f ? *f : nullptr;
		}
		if (!r.fail) {
			s->implicit_initializer = optional_function(s);
		}
		if (!r.fail) {
			s->implicit_ready = optional_function(s);
		}
		if (!r.fail) {
			s->static_initializer = optional_function(s);
		}
		count = (int)r.u32();
		for (int i = 0; i < count && !r.fail; i++) {
			StringName name = r.str();
			Ref<GDScript> *sub = s->subclasses.getptr(name);
			if (!sub) {
				return fail(vformat("missing inner class %s", name));
			}
			body(sub->ptr());
		}
		if (r.fail) {
			return false;
		}
		s->_static_default_init();
		s->valid = true;
		return true;
	}
};

// ---------------------------------------------------------------- public

Vector<uint8_t> GDScriptPrebuild::save(const GDScript *p_script, String &r_error) {
	ERR_FAIL_NULL_V(p_script, Vector<uint8_t>());
	if (!p_script->is_valid()) {
		r_error = "script not compiled";
		return Vector<uint8_t>();
	}
	Saver saver;
	saver.root = p_script;
	Writer w;
	saver.tree(w, p_script);
	if (!saver.body(w, p_script)) {
		r_error = saver.error;
		return Vector<uint8_t>();
	}
	{
		MutexLock lock(GDScriptCache::singleton->mutex);
		w.u8(GDScriptCache::singleton->static_gdscript_cache.has(p_script->get_script_path()));
	}
	return w.data;
}

Error GDScriptPrebuild::apply(GDScript *p_script, const Vector<uint8_t> &p_data) {
	ERR_FAIL_NULL_V(p_script, ERR_INVALID_PARAMETER);
	Applier a;
	a.root = p_script;
	a.r.p = p_data.ptr();
	a.r.size = p_data.size();
	a.tree(p_script);
	if (!a.r.fail) {
		a.body(p_script);
	}
	bool add_static = a.r.u8();
	if (a.r.fail) {
		print_verbose(vformat("GDScript prebuild: %s → compiling from tokens (%s).", p_script->get_script_path(), a.error));
		return ERR_INVALID_DATA;
	}
	if (add_static) {
		GDScriptCache::add_static_script(Ref<GDScript>(p_script));
	}
	return OK;
}

Vector<uint8_t> GDScriptPrebuild::pack(const Vector<uint8_t> &p_tokens, const Vector<uint8_t> &p_prebuilt) {
	Writer w;
	for (uint8_t c : MAGIC) {
		w.u8(c);
	}
	w.str(compat_key());
	w.bytes(p_tokens);
	w.bytes(p_prebuilt);
	return w.data;
}

bool GDScriptPrebuild::unpack(const Vector<uint8_t> &p_file, Vector<uint8_t> &r_tokens, Vector<uint8_t> &r_prebuilt) {
	if (p_file.size() < 4 || memcmp(p_file.ptr(), MAGIC, 4) != 0) {
		return false;
	}
	Reader r;
	r.p = p_file.ptr();
	r.size = p_file.size();
	r.pos = 4;
	String key = r.str();
	Vector<uint8_t> tokens = r.bytes();
	Vector<uint8_t> prebuilt = r.bytes();
	if (r.fail) {
		return false;
	}
	r_tokens = tokens;
	// Another engine build: keep only the tokens (compiled the usual way).
	r_prebuilt = key == compat_key() ? prebuilt : Vector<uint8_t>();
	return true;
}

Vector<uint8_t> GDScriptPrebuild::tokens_of(const Vector<uint8_t> &p_file) {
	Vector<uint8_t> tokens, prebuilt;
	if (unpack(p_file, tokens, prebuilt)) {
		return tokens;
	}
	return p_file;
}
