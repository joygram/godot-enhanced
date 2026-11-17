/**************************************************************************/
/*  gdscript_aot.cpp                                                      */
/**************************************************************************/
/* godot-enhanced: GDScript AOT — bytecode → C++ (patches/gdscript-aot.md) */
/**************************************************************************/

#include "gdscript_aot.h"

#include "gdscript.h"

// Registry: generated `gd_aot_registry.cpp`, or `aot_empty/gdscript_aot_empty.cpp` when AOT is off.
// Referenced here so the linker keeps the registry (and through it every generated body).
const GDScriptAOT::Entry *gdscript_aot_table(int &r_count);

static HashMap<String, const GDScriptAOT::Entry *> &_aot_index() {
	static HashMap<String, const GDScriptAOT::Entry *> index;
	static bool built = false;
	if (!built) {
		built = true;
		int count = 0;
		const GDScriptAOT::Entry *entries = gdscript_aot_table(count);
		for (int i = 0; i < count; i++) {
			index.insert(String(entries[i].path) + "|" + entries[i].class_name + "|" + entries[i].function, &entries[i]);
		}
	}
	return index;
}

void GDScriptAOT::register_entries(const Entry *p_entries, int p_count) {
	HashMap<String, const Entry *> &index = _aot_index();
	for (int i = 0; i < p_count; i++) {
		index.insert(String(p_entries[i].path) + "|" + p_entries[i].class_name + "|" + p_entries[i].function, &p_entries[i]);
	}
}

bool GDScriptAOT::has_entries() {
	return !_aot_index().is_empty();
}

uint64_t GDScriptAOT::code_hash(const GDScriptFunction *p_function) {
	// FNV-1a over the code size and every code int.
	uint64_t hash = 14695981039346656037ULL;
	const auto mix = [&hash](uint32_t p_value) {
		for (int b = 0; b < 4; b++) {
			hash ^= (p_value >> (b * 8)) & 0xff;
			hash *= 1099511628211ULL;
		}
	};
	const int *code = p_function->get_code();
	mix(uint32_t(p_function->get_code_size()));
	for (int i = 0; i < p_function->get_code_size(); i++) {
		mix(uint32_t(code[i]));
	}
	return hash;
}

static void _bind_class(GDScript *p_script, const HashMap<String, const GDScriptAOT::Entry *> &p_index) {
	const String prefix = p_script->get_script_path() + "|" + p_script->get_fully_qualified_name() + "|";
	for (const KeyValue<StringName, GDScriptFunction *> &E : p_script->get_member_functions()) {
		const GDScriptAOT::Entry *const *found = p_index.getptr(prefix + String(E.key));
		if (!found) {
			continue;
		}
		if ((*found)->hash == GDScriptAOT::code_hash(E.value)) {
			E.value->set_aot_call((*found)->call);
			print_verbose("GDScript AOT: native " + prefix + String(E.key));
		} else {
			print_verbose("GDScript AOT: bytecode changed, VM for " + prefix + String(E.key));
		}
	}
	for (const KeyValue<StringName, Ref<GDScript>> &E : p_script->get_subclasses()) {
		_bind_class(E.value.ptr(), p_index);
	}
}

void GDScriptAOT::bind(GDScript *p_script) {
	const HashMap<String, const Entry *> &index = _aot_index();
	if (index.is_empty() || !p_script) {
		return;
	}
	_bind_class(p_script, index);
}

#ifdef DEBUG_ENABLED

// Functions kept on the VM: suspend/resume (await), closures (lambda), load-time patched operands (global index).
static bool _aot_eligible(const GDScriptFunction *p_function, const Vector<int> &p_offsets, String &r_reason) {
	for (int ip : p_offsets) {
		switch (p_function->get_code()[ip]) {
			case GDScriptFunction::OPCODE_AWAIT:
			case GDScriptFunction::OPCODE_AWAIT_RESUME:
			case GDScriptFunction::OPCODE_CALL_ASYNC:
				r_reason = "await";
				return false;
			case GDScriptFunction::OPCODE_CREATE_LAMBDA:
			case GDScriptFunction::OPCODE_CREATE_SELF_LAMBDA:
				r_reason = "lambda";
				return false;
			case GDScriptFunction::OPCODE_STORE_GLOBAL:
				r_reason = "global index";
				return false;
			default:
				break;
		}
	}
	return true;
}

static String _c_string(const String &p_text) {
	return "\"" + p_text.c_escape() + "\"";
}

static void _generate_class(const GDScript *p_script, int &r_next_id, String &r_source, Vector<String> &r_registry, Vector<String> &r_skipped) {
	for (const KeyValue<StringName, GDScriptFunction *> &E : p_script->get_member_functions()) {
		const GDScriptFunction *function = E.value;
		const int *function_code = function->get_code();
		if (!function_code || function->get_code_size() == 0) {
			continue;
		}
		Vector<int> offsets;
		function->disassemble(Vector<String>(), &offsets);
		String reason;
		if (!_aot_eligible(function, offsets, reason)) {
			r_skipped.push_back(p_script->get_script_path() + " " + String(E.key) + " (" + reason + ")");
			continue;
		}

		const int id = r_next_id++;
		String code;
		for (int i = 0; i < function->get_code_size(); i++) {
			code += itos(function_code[i]) + ",";
		}

		r_source += "// " + p_script->get_fully_qualified_name() + "." + String(E.key) + "\n";
		r_source += "static const int gd_aot_code_" + itos(id) + "[] = {" + code + "};\n";
		r_source += "#define GD_AOT_RUN \\\n\tfor (;;) { \\\n\t\tswitch (ip) { \\\n";
		for (int ip : offsets) {
			r_source += "\t\t\tcase " + itos(ip) + ": { const int gd_next = aot_op(std::integral_constant<int, " + itos(function_code[ip]) + ">{}); if (gd_next == GD_AOT_EXIT) { goto OPSEXIT; } ip = gd_next; } continue; \\\n";
		}
		r_source += "\t\t\tdefault: goto OPSEXIT; \\\n\t\t} \\\n\t}\n";
		r_source += "template <>\nVariant GDScriptFunction::call_aot<" + itos(id) + ">(GDScriptInstance *p_instance, const Variant **p_args, int p_argcount, Callable::CallError &r_err, CallState *p_state) {\n";
		r_source += "\tconst int *const _code_ptr = gd_aot_code_" + itos(id) + ";\n";
		r_source += "#define GD_AOT_CALL\n#include \"modules/gdscript/gdscript_vm.cpp\"\n#undef GD_AOT_CALL\n#undef GD_AOT_RUN\n\n";

		r_registry.push_back("\t{ " + _c_string(p_script->get_script_path()) + ", " + _c_string(p_script->get_fully_qualified_name()) + ", " + _c_string(String(E.key)) + ", " + String::num_uint64(GDScriptAOT::code_hash(function)) + "ULL, &GDScriptFunction::call_aot<" + itos(id) + "> },");
	}
	for (const KeyValue<StringName, Ref<GDScript>> &E : p_script->get_subclasses()) {
		_generate_class(E.value.ptr(), r_next_id, r_source, r_registry, r_skipped);
	}
}

String GDScriptAOT::generate(const GDScript *p_script, int &r_next_id, Vector<String> &r_registry, Vector<String> &r_skipped) {
	String body;
	_generate_class(p_script, r_next_id, body, r_registry, r_skipped);
	if (body.is_empty()) {
		return String();
	}
	String source = "// Generated by godot-enhanced GDScript AOT from " + p_script->get_script_path() + ". Do not edit.\n";
	source += "#include \"modules/gdscript/gdscript.h\"\n#include \"modules/gdscript/gdscript_function.h\"\n#include \"modules/gdscript/gdscript_lambda_callable.h\"\n";
	source += "#include \"core/object/class_db.h\"\n#include \"core/os/os.h\"\n#include \"core/profiling/profiling.h\"\n#include <type_traits>\n\n";
	return source + body;
}

String GDScriptAOT::registry_source(const Vector<String> &p_registry) {
	String source = "// Generated by godot-enhanced GDScript AOT. Do not edit.\n#include \"modules/gdscript/gdscript_aot.h\"\n\n";
	// Declare the explicit specializations (defined in the per-script files) before taking their addresses.
	for (int id = 0; id < p_registry.size(); id++) {
		source += "template <>\nVariant GDScriptFunction::call_aot<" + itos(id) + ">(GDScriptInstance *, const Variant **, int, Callable::CallError &, CallState *);\n";
	}
	source += "\nstatic const GDScriptAOT::Entry gd_aot_entries[] = {\n";
	for (const String &line : p_registry) {
		source += line + "\n";
	}
	source += "\t{ nullptr, nullptr, nullptr, 0, nullptr },\n};\n\n";
	source += "const GDScriptAOT::Entry *gdscript_aot_table(int &r_count) {\n\tr_count = " + itos(p_registry.size()) + ";\n\treturn gd_aot_entries;\n}\n";
	return source;
}

#endif // DEBUG_ENABLED
