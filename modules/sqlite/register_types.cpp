#include "register_types.h"

#include "gdsqlite.hpp"

void initialize_sqlite_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(godot::SQLite);
}

void uninitialize_sqlite_module(ModuleInitializationLevel p_level) {
}
