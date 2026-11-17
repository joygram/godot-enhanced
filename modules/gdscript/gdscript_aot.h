/**************************************************************************/
/*  gdscript_aot.h                                                        */
/**************************************************************************/
/* godot-enhanced: GDScript AOT — bytecode → C++ (patches/gdscript-aot.md) */
/**************************************************************************/

#pragma once

#include "gdscript_function.h"

#include "core/templates/hash_map.h"

class GDScript;

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
