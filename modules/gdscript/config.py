def can_build(env, platform):
    env.module_add_dependencies("gdscript", ["jsonrpc", "websocket"], True)
    return True


def configure(env):
    pass


def get_opts(platform):
    from SCons.Variables import BoolVariable

    return [
        # godot-enhanced AOT: compile every opcode body once in AOT mode (patches/gdscript-aot.md). Release templates only.
        BoolVariable("gdscript_aot_check", "Compile the GDScript AOT opcode check", False),
        # Folder of generated AOT C++ (export with GODOT_GDSCRIPT_AOT_DIR). Empty = no AOT bodies.
        ("gdscript_aot_dir", "Folder of generated GDScript AOT C++", ""),
    ]


def get_doc_classes():
    return [
        "@GDScript",
        "GDScript",
        "GDScriptLanguageProtocol",
        "GDScriptSyntaxHighlighter",
        "GDScriptTextDocument",
        "GDScriptWorkspace",
    ]


def get_doc_path():
    return "doc_classes"
