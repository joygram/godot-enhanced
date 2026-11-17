/**************************************************************************/
/*  register_types.cpp                                                    */
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

#include "register_types.h"

#include "gdscript.h"
#include "gdscript_aot.h"
#include "gdscript_cache.h"
#include "gdscript_parser.h"
#include "gdscript_prebuild.h"
#include "gdscript_resource_format.h"
#include "gdscript_tokenizer_buffer.h"
#include "gdscript_utility_functions.h"

#ifdef TOOLS_ENABLED
#include "editor/gdscript_highlighter.h"
#include "editor/gdscript_translation_parser_plugin.h"
#include "editor/script/script_editor_plugin.h"

#ifndef GDSCRIPT_NO_LSP
#include "language_server/gdscript_language_protocol.h"
#include "language_server/gdscript_language_server.h"
#endif
#endif // TOOLS_ENABLED

#ifdef TESTS_ENABLED
#include "tests/test_gdscript.h"
#endif

#include "core/io/dir_access.h"
#include "core/io/file_access.h"
#include "core/io/resource_loader.h"
#include "core/os/os.h"
#include "core/io/resource_saver.h"
#include "core/object/class_db.h"

#ifdef TOOLS_ENABLED
#include "editor/editor_node.h"
#include "editor/export/editor_export.h"
#include "editor/translations/editor_translation_parser.h"

#ifndef GDSCRIPT_NO_LSP
#include "core/config/engine.h"
#endif
#endif // TOOLS_ENABLED

#ifdef TESTS_ENABLED
#include "tests/test_macros.h"
#endif

GDScriptLanguage *script_language_gd = nullptr;
Ref<ResourceFormatLoaderGDScript> resource_loader_gd;
Ref<ResourceFormatSaverGDScript> resource_saver_gd;
GDScriptCache *gdscript_cache = nullptr;

#ifdef TOOLS_ENABLED

Ref<GDScriptEditorTranslationParserPlugin> gdscript_translation_parser_plugin;

class EditorExportGDScript : public EditorExportPlugin {
	GDCLASS(EditorExportGDScript, EditorExportPlugin);

	static constexpr EditorExportPreset::ScriptExportMode DEFAULT_SCRIPT_MODE = EditorExportPreset::MODE_SCRIPT_BINARY_TOKENS_COMPRESSED;
	EditorExportPreset::ScriptExportMode script_mode = DEFAULT_SCRIPT_MODE;
	int prebuilt_count = 0;
	int tokens_only_count = 0;
	// godot-enhanced AOT: GODOT_GDSCRIPT_AOT_DIR → C++ per prebuilt script + registry (patches/gdscript-aot.md).
	String aot_dir;
	int aot_next_id = 0;
	int aot_file_count = 0;
	Vector<String> aot_registry;
	Vector<String> aot_skipped;

protected:
	virtual void _export_end() override {
		if (script_mode == EditorExportPreset::MODE_SCRIPT_PREBUILT) {
			print_line(vformat("GDScript prebuild: %d prebuilt, %d as tokens.", prebuilt_count, tokens_only_count));
		}
		if (!aot_dir.is_empty()) {
			Ref<FileAccess> registry = FileAccess::open(aot_dir.path_join("gd_aot_registry.cpp"), FileAccess::WRITE);
			if (registry.is_valid()) {
				registry->store_string(GDScriptAOT::registry_source(aot_registry));
			}
			for (const String &skipped : aot_skipped) {
				print_verbose("GDScript AOT: VM kept for " + skipped);
			}
			print_line(vformat("GDScript AOT: %d functions in %d files, %d kept on the VM → %s", aot_registry.size(), aot_file_count, aot_skipped.size(), aot_dir));
		}
	}

	virtual void _export_begin(const HashSet<String> &p_features, bool p_debug, const String &p_path, int p_flags) override {
		script_mode = DEFAULT_SCRIPT_MODE;
		prebuilt_count = 0;
		tokens_only_count = 0;
		aot_next_id = 0;
		aot_file_count = 0;
		aot_registry.clear();
		aot_skipped.clear();
		aot_dir = OS::get_singleton()->get_environment("GODOT_GDSCRIPT_AOT_DIR");
		if (!aot_dir.is_empty()) {
			DirAccess::make_dir_recursive_absolute(aot_dir);
			// Fresh set per export: stale bodies would not match the new registry ids.
			Ref<DirAccess> dir = DirAccess::open(aot_dir);
			if (dir.is_valid()) {
				for (const String &file : dir->get_files()) {
					if (file.begins_with("gd_aot_") && file.ends_with(".cpp")) {
						dir->remove(file);
					}
				}
			}
		}

		const Ref<EditorExportPreset> &preset = get_export_preset();
		if (preset.is_valid()) {
			script_mode = preset->get_script_export_mode();
		}
		if (!aot_dir.is_empty()) {
			// AOT needs the prebuilt bytecode → export as Prebuilt whatever the preset says.
			script_mode = EditorExportPreset::MODE_SCRIPT_PREBUILT;
		}
	}

	virtual void _export_file(const String &p_path, const String &p_type, const HashSet<String> &p_features) override {
		if (p_path.get_extension() != "gd" || script_mode == EditorExportPreset::MODE_SCRIPT_TEXT) {
			return;
		}

		Vector<uint8_t> file = FileAccess::get_file_as_bytes(p_path);
		if (file.is_empty()) {
			return;
		}

		String source = String::utf8(reinterpret_cast<const char *>(file.ptr()), file.size());
		GDScriptTokenizerBuffer::CompressMode compress_mode = script_mode == EditorExportPreset::MODE_SCRIPT_BINARY_TOKENS_COMPRESSED || script_mode == EditorExportPreset::MODE_SCRIPT_PREBUILT ? GDScriptTokenizerBuffer::COMPRESS_ZSTD : GDScriptTokenizerBuffer::COMPRESS_NONE;
		file = GDScriptTokenizerBuffer::parse_code_string(source, compress_mode);
		if (file.is_empty()) {
			return;
		}

		// godot-enhanced: Prebuilt → tokens + the compiled class tree (GDScriptPrebuild). A script that
		// cannot be stored keeps plain tokens and compiles at load as usual.
		if (script_mode == EditorExportPreset::MODE_SCRIPT_PREBUILT) {
			Ref<GDScript> script = ResourceLoader::load(p_path, "GDScript");
			String error;
			Vector<uint8_t> prebuilt = script.is_valid() ? GDScriptPrebuild::save(script.ptr(), error) : Vector<uint8_t>();
			if (!prebuilt.is_empty()) {
				file = GDScriptPrebuild::pack(file, prebuilt);
				prebuilt_count++;
				// AOT only for prebuilt scripts: the runtime bytecode is exactly the one stored here.
				if (!aot_dir.is_empty()) {
					String source = GDScriptAOT::generate(script.ptr(), aot_next_id, aot_registry, aot_skipped);
					if (!source.is_empty()) {
						Ref<FileAccess> out = FileAccess::open(aot_dir.path_join(vformat("gd_aot_%04d.cpp", aot_file_count++)), FileAccess::WRITE);
						if (out.is_valid()) {
							out->store_string(source);
						}
					}
				}
			} else {
				print_verbose(vformat("GDScript prebuild: %s kept as tokens (%s).", p_path, script.is_valid() ? error : String("not loadable")));
				tokens_only_count++;
			}
		}

		add_file(p_path.get_basename() + ".gdc", file, true);
	}

public:
	virtual String get_name() const override { return "GDScript"; }
};

static void _editor_init() {
	Ref<EditorExportGDScript> gd_export;
	gd_export.instantiate();
	EditorExport::get_singleton()->add_export_plugin(gd_export);

#ifdef TOOLS_ENABLED
	Ref<GDScriptSyntaxHighlighter> gdscript_syntax_highlighter;
	gdscript_syntax_highlighter.instantiate();
	ScriptEditor::get_singleton()->register_syntax_highlighter(gdscript_syntax_highlighter);
#endif
}

#endif // TOOLS_ENABLED

void initialize_gdscript_module(ModuleInitializationLevel p_level) {
	if (p_level == MODULE_INITIALIZATION_LEVEL_SERVERS) {
		GDREGISTER_CLASS(GDScript);
		GDREGISTER_INTERNAL_CLASS(GDScriptFunctionState);

		script_language_gd = memnew(GDScriptLanguage);
		ScriptServer::register_language(script_language_gd);

		resource_loader_gd.instantiate();
		ResourceLoader::add_resource_format_loader(resource_loader_gd);

		resource_saver_gd.instantiate();
		ResourceSaver::add_resource_format_saver(resource_saver_gd);

		gdscript_cache = memnew(GDScriptCache);

		GDScriptUtilityFunctions::register_functions();
	}

#ifdef TOOLS_ENABLED
	if (p_level == MODULE_INITIALIZATION_LEVEL_SERVERS) {
		EditorNode::add_init_callback(_editor_init);

		gdscript_translation_parser_plugin.instantiate();
		EditorTranslationParser::get_singleton()->add_parser(gdscript_translation_parser_plugin, EditorTranslationParser::STANDARD);
	} else if (p_level == MODULE_INITIALIZATION_LEVEL_EDITOR) {
		GDREGISTER_CLASS(GDScriptSyntaxHighlighter);
#ifndef GDSCRIPT_NO_LSP
		register_lsp_types();
		memnew(GDScriptLanguageProtocol);
		EditorPlugins::add_by_type<GDScriptLanguageServer>();

		Engine::Singleton singleton("GDScriptLanguageProtocol", GDScriptLanguageProtocol::get_singleton());
		singleton.editor_only = true;
		Engine::get_singleton()->add_singleton(singleton);
#endif // !GDSCRIPT_NO_LSP
	}
#endif // TOOLS_ENABLED
}

void uninitialize_gdscript_module(ModuleInitializationLevel p_level) {
	if (p_level == MODULE_INITIALIZATION_LEVEL_SERVERS) {
		ScriptServer::unregister_language(script_language_gd);

		if (gdscript_cache) {
			memdelete(gdscript_cache);
		}

		if (script_language_gd) {
			memdelete(script_language_gd);
		}

		ResourceLoader::remove_resource_format_loader(resource_loader_gd);
		resource_loader_gd.unref();

		ResourceSaver::remove_resource_format_saver(resource_saver_gd);
		resource_saver_gd.unref();

		GDScriptParser::cleanup();
		GDScriptUtilityFunctions::unregister_functions();
	}

#ifdef TOOLS_ENABLED
	if (p_level == MODULE_INITIALIZATION_LEVEL_EDITOR) {
		EditorTranslationParser::get_singleton()->remove_parser(gdscript_translation_parser_plugin, EditorTranslationParser::STANDARD);
		gdscript_translation_parser_plugin.unref();
#ifndef GDSCRIPT_NO_LSP
		memdelete(GDScriptLanguageProtocol::get_singleton());
#endif // GDSCRIPT_NO_LSP
	}
#endif // TOOLS_ENABLED
}

#ifdef TESTS_ENABLED
void test_tokenizer() {
	GDScriptTests::test(GDScriptTests::TestType::TEST_TOKENIZER);
}

void test_tokenizer_buffer() {
	GDScriptTests::test(GDScriptTests::TestType::TEST_TOKENIZER_BUFFER);
}

void test_parser() {
	GDScriptTests::test(GDScriptTests::TestType::TEST_PARSER);
}

void test_compiler() {
	GDScriptTests::test(GDScriptTests::TestType::TEST_COMPILER);
}

void test_bytecode() {
	GDScriptTests::test(GDScriptTests::TestType::TEST_BYTECODE);
}

REGISTER_TEST_COMMAND("gdscript-tokenizer", &test_tokenizer);
REGISTER_TEST_COMMAND("gdscript-tokenizer-buffer", &test_tokenizer_buffer);
REGISTER_TEST_COMMAND("gdscript-parser", &test_parser);
REGISTER_TEST_COMMAND("gdscript-compiler", &test_compiler);
REGISTER_TEST_COMMAND("gdscript-bytecode", &test_bytecode);
#endif
