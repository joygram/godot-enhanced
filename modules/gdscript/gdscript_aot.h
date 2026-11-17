/**************************************************************************/
/*  gdscript_aot.h                                                        */
/**************************************************************************/
/* godot-enhanced: GDScript AOT — bytecode → C++ (patches/gdscript-aot.md) */
/**************************************************************************/

#pragma once

#include "gdscript_function.h"

#include "core/templates/hash_map.h"

class GDScript;

// Opcode lambda is always inlined so clang/MSVC fold the constant ip and operands.
#if defined(__GNUC__) || defined(__clang__)
#define GD_AOT_INLINE __attribute__((always_inline))
#else
#define GD_AOT_INLINE
#endif

// AOT opcode lambda: makes the bytecode pointer's type depend on the opcode tag, so a discarded opcode body
// (e.g. OPCODE_OPERATOR writing its cache into the code) is not checked against a const code array.
template <typename T, typename P>
inline P *gd_aot_dependent(P *p_ptr) {
	return p_ptr;
}

class GDScriptAOT {
public:
	// One generated function. Path = script path, class = fully qualified class name, hash = bytecode hash.
	struct Entry {
		const char *path;
		const char *class_name;
		const char *function;
		uint64_t hash;
		GDScriptFunction::AotCall call;
	};

	// Generated registry calls this once (static initializer).
	static void register_entries(const Entry *p_entries, int p_count);
	static bool has_entries();

	// After a script's functions are ready: swap in native bodies whose bytecode hash matches.
	static void bind(GDScript *p_script);

	static uint64_t code_hash(const GDScriptFunction *p_function);

#ifdef DEBUG_ENABLED
	// Editor export: C++ for every eligible function of the script (and inner classes).
	// r_next_id: running template id across the whole export. r_registry: entry lines for the registry file.
	static String generate(const GDScript *p_script, int &r_next_id, Vector<String> &r_registry, Vector<String> &r_skipped);
	static String registry_source(const Vector<String> &p_registry);
#endif
};
