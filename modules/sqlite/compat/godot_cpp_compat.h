#pragma once

// godot-sqlite(GDExtension) 소스를 엔진 모듈로 그대로 빌드하기 위한 godot-cpp → 엔진 헤더 대응.
// godot-sqlite 원본의 godot_cpp/... include 가 모두 이 파일로 모인다.

#include "core/core_bind.h"
#include "core/config/project_settings.h"
#include "core/io/dir_access.h"
#include "core/io/file_access.h"
#include "core/io/json.h"
#include "core/object/class_db.h"
#include "core/object/ref_counted.h"
#include "core/os/os.h"
#include "core/os/time.h"
#include "core/string/print_string.h"
#include "core/variant/typed_array.h"

namespace godot {

using Marshalls = CoreBind::Marshalls;

struct UtilityFunctions {
	template <typename... Args>
	static void print(const Args &...p_args) {
		print_line(p_args...);
	}
};

} // namespace godot

// godot-cpp 의 VARIANT_ENUM_CAST 는 godot 이름공간 안에서 펼쳐진다 — 엔진 매크로는 전역이라 이름을 끌어온다.
using namespace godot;
