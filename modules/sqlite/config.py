def can_build(env, platform):
    return True


def configure(env):
    pass


def is_enabled():
    # 기본 끔 — 웹 정적 템플릿에서 module_sqlite_enabled=yes 로만 켠다(에디터·데스크톱은 GDExtension 판과 클래스명 충돌)
    return False


def get_doc_classes():
    return ["SQLite"]


def get_doc_path():
    return "doc_classes"
