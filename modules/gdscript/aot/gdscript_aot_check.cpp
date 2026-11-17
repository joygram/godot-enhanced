/**************************************************************************/
/*  gdscript_aot_check.cpp                                                */
/**************************************************************************/
/* godot-enhanced: GDScript AOT compile check (patches/gdscript-aot.md).  */
/* Instantiates every opcode body once in AOT mode, so a VM change that   */
/* breaks AOT fails the build. Built with `gdscript_aot_check=yes`.       */
/**************************************************************************/

#include "../gdscript.h"
#include "../gdscript_function.h"
#include "../gdscript_lambda_callable.h"

#include "core/object/class_db.h"
#include "core/os/os.h"
#include "core/profiling/profiling.h"

#include <type_traits>

#define GD_AOT_ALL_OPCODES(X)                    \
	X(OPCODE_OPERATOR)                           \
	X(OPCODE_OPERATOR_VALIDATED)                 \
	X(OPCODE_TYPE_TEST_BUILTIN)                  \
	X(OPCODE_TYPE_TEST_ARRAY)                    \
	X(OPCODE_TYPE_TEST_DICTIONARY)               \
	X(OPCODE_TYPE_TEST_NATIVE)                   \
	X(OPCODE_TYPE_TEST_SCRIPT)                   \
	X(OPCODE_SET_KEYED)                          \
	X(OPCODE_SET_KEYED_VALIDATED)                \
	X(OPCODE_SET_INDEXED_VALIDATED)              \
	X(OPCODE_GET_KEYED)                          \
	X(OPCODE_GET_KEYED_VALIDATED)                \
	X(OPCODE_GET_INDEXED_VALIDATED)              \
	X(OPCODE_SET_NAMED)                          \
	X(OPCODE_SET_NAMED_VALIDATED)                \
	X(OPCODE_GET_NAMED)                          \
	X(OPCODE_GET_NAMED_VALIDATED)                \
	X(OPCODE_SET_MEMBER)                         \
	X(OPCODE_GET_MEMBER)                         \
	X(OPCODE_SET_STATIC_VARIABLE)                \
	X(OPCODE_GET_STATIC_VARIABLE)                \
	X(OPCODE_ASSIGN)                             \
	X(OPCODE_ASSIGN_NULL)                        \
	X(OPCODE_ASSIGN_TRUE)                        \
	X(OPCODE_ASSIGN_FALSE)                       \
	X(OPCODE_ASSIGN_TYPED_BUILTIN)               \
	X(OPCODE_ASSIGN_TYPED_ARRAY)                 \
	X(OPCODE_ASSIGN_TYPED_DICTIONARY)            \
	X(OPCODE_ASSIGN_TYPED_NATIVE)                \
	X(OPCODE_ASSIGN_TYPED_SCRIPT)                \
	X(OPCODE_CAST_TO_BUILTIN)                    \
	X(OPCODE_CAST_TO_NATIVE)                     \
	X(OPCODE_CAST_TO_SCRIPT)                     \
	X(OPCODE_CONSTRUCT)                          \
	X(OPCODE_CONSTRUCT_VALIDATED)                \
	X(OPCODE_CONSTRUCT_ARRAY)                    \
	X(OPCODE_CONSTRUCT_TYPED_ARRAY)              \
	X(OPCODE_CONSTRUCT_DICTIONARY)               \
	X(OPCODE_CONSTRUCT_TYPED_DICTIONARY)         \
	X(OPCODE_CALL)                               \
	X(OPCODE_CALL_RETURN)                        \
	X(OPCODE_CALL_ASYNC)                         \
	X(OPCODE_CALL_UTILITY)                       \
	X(OPCODE_CALL_UTILITY_VALIDATED)             \
	X(OPCODE_CALL_GDSCRIPT_UTILITY)              \
	X(OPCODE_CALL_BUILTIN_TYPE_VALIDATED)        \
	X(OPCODE_CALL_SELF_BASE)                     \
	X(OPCODE_CALL_METHOD_BIND)                   \
	X(OPCODE_CALL_METHOD_BIND_RET)               \
	X(OPCODE_CALL_BUILTIN_STATIC)                \
	X(OPCODE_CALL_NATIVE_STATIC)                 \
	X(OPCODE_CALL_NATIVE_STATIC_VALIDATED_RETURN) \
	X(OPCODE_CALL_NATIVE_STATIC_VALIDATED_NO_RETURN) \
	X(OPCODE_CALL_METHOD_BIND_VALIDATED_RETURN)  \
	X(OPCODE_CALL_METHOD_BIND_VALIDATED_NO_RETURN) \
	X(OPCODE_AWAIT)                              \
	X(OPCODE_AWAIT_RESUME)                       \
	X(OPCODE_CREATE_LAMBDA)                      \
	X(OPCODE_CREATE_SELF_LAMBDA)                 \
	X(OPCODE_JUMP)                               \
	X(OPCODE_JUMP_IF)                            \
	X(OPCODE_JUMP_IF_NOT)                        \
	X(OPCODE_JUMP_TO_DEF_ARGUMENT)               \
	X(OPCODE_JUMP_IF_SHARED)                     \
	X(OPCODE_RETURN)                             \
	X(OPCODE_RETURN_TYPED_BUILTIN)               \
	X(OPCODE_RETURN_TYPED_ARRAY)                 \
	X(OPCODE_RETURN_TYPED_DICTIONARY)            \
	X(OPCODE_RETURN_TYPED_NATIVE)                \
	X(OPCODE_RETURN_TYPED_SCRIPT)                \
	X(OPCODE_ITERATE_BEGIN)                      \
	X(OPCODE_ITERATE_BEGIN_INT)                  \
	X(OPCODE_ITERATE_BEGIN_FLOAT)                \
	X(OPCODE_ITERATE_BEGIN_VECTOR2)              \
	X(OPCODE_ITERATE_BEGIN_VECTOR2I)             \
	X(OPCODE_ITERATE_BEGIN_VECTOR3)              \
	X(OPCODE_ITERATE_BEGIN_VECTOR3I)             \
	X(OPCODE_ITERATE_BEGIN_STRING)               \
	X(OPCODE_ITERATE_BEGIN_DICTIONARY)           \
	X(OPCODE_ITERATE_BEGIN_ARRAY)                \
	X(OPCODE_ITERATE_BEGIN_PACKED_BYTE_ARRAY)    \
	X(OPCODE_ITERATE_BEGIN_PACKED_INT32_ARRAY)   \
	X(OPCODE_ITERATE_BEGIN_PACKED_INT64_ARRAY)   \
	X(OPCODE_ITERATE_BEGIN_PACKED_FLOAT32_ARRAY) \
	X(OPCODE_ITERATE_BEGIN_PACKED_FLOAT64_ARRAY) \
	X(OPCODE_ITERATE_BEGIN_PACKED_STRING_ARRAY)  \
	X(OPCODE_ITERATE_BEGIN_PACKED_VECTOR2_ARRAY) \
	X(OPCODE_ITERATE_BEGIN_PACKED_VECTOR3_ARRAY) \
	X(OPCODE_ITERATE_BEGIN_PACKED_COLOR_ARRAY)   \
	X(OPCODE_ITERATE_BEGIN_PACKED_VECTOR4_ARRAY) \
	X(OPCODE_ITERATE_BEGIN_OBJECT)               \
	X(OPCODE_ITERATE_BEGIN_RANGE)                \
	X(OPCODE_ITERATE)                            \
	X(OPCODE_ITERATE_INT)                        \
	X(OPCODE_ITERATE_FLOAT)                      \
	X(OPCODE_ITERATE_VECTOR2)                    \
	X(OPCODE_ITERATE_VECTOR2I)                   \
	X(OPCODE_ITERATE_VECTOR3)                    \
	X(OPCODE_ITERATE_VECTOR3I)                   \
	X(OPCODE_ITERATE_STRING)                     \
	X(OPCODE_ITERATE_DICTIONARY)                 \
	X(OPCODE_ITERATE_ARRAY)                      \
	X(OPCODE_ITERATE_PACKED_BYTE_ARRAY)          \
	X(OPCODE_ITERATE_PACKED_INT32_ARRAY)         \
	X(OPCODE_ITERATE_PACKED_INT64_ARRAY)         \
	X(OPCODE_ITERATE_PACKED_FLOAT32_ARRAY)       \
	X(OPCODE_ITERATE_PACKED_FLOAT64_ARRAY)       \
	X(OPCODE_ITERATE_PACKED_STRING_ARRAY)        \
	X(OPCODE_ITERATE_PACKED_VECTOR2_ARRAY)       \
	X(OPCODE_ITERATE_PACKED_VECTOR3_ARRAY)       \
	X(OPCODE_ITERATE_PACKED_COLOR_ARRAY)         \
	X(OPCODE_ITERATE_PACKED_VECTOR4_ARRAY)       \
	X(OPCODE_ITERATE_OBJECT)                     \
	X(OPCODE_ITERATE_RANGE)                      \
	X(OPCODE_STORE_GLOBAL)                       \
	X(OPCODE_STORE_NAMED_GLOBAL)                 \
	X(OPCODE_TYPE_ADJUST_BOOL)                   \
	X(OPCODE_TYPE_ADJUST_INT)                    \
	X(OPCODE_TYPE_ADJUST_FLOAT)                  \
	X(OPCODE_TYPE_ADJUST_STRING)                 \
	X(OPCODE_TYPE_ADJUST_VECTOR2)                \
	X(OPCODE_TYPE_ADJUST_VECTOR2I)               \
	X(OPCODE_TYPE_ADJUST_RECT2)                  \
	X(OPCODE_TYPE_ADJUST_RECT2I)                 \
	X(OPCODE_TYPE_ADJUST_VECTOR3)                \
	X(OPCODE_TYPE_ADJUST_VECTOR3I)               \
	X(OPCODE_TYPE_ADJUST_TRANSFORM2D)            \
	X(OPCODE_TYPE_ADJUST_VECTOR4)                \
	X(OPCODE_TYPE_ADJUST_VECTOR4I)               \
	X(OPCODE_TYPE_ADJUST_PLANE)                  \
	X(OPCODE_TYPE_ADJUST_QUATERNION)             \
	X(OPCODE_TYPE_ADJUST_AABB)                   \
	X(OPCODE_TYPE_ADJUST_BASIS)                  \
	X(OPCODE_TYPE_ADJUST_TRANSFORM3D)            \
	X(OPCODE_TYPE_ADJUST_PROJECTION)             \
	X(OPCODE_TYPE_ADJUST_COLOR)                  \
	X(OPCODE_TYPE_ADJUST_STRING_NAME)            \
	X(OPCODE_TYPE_ADJUST_NODE_PATH)              \
	X(OPCODE_TYPE_ADJUST_RID)                    \
	X(OPCODE_TYPE_ADJUST_OBJECT)                 \
	X(OPCODE_TYPE_ADJUST_CALLABLE)               \
	X(OPCODE_TYPE_ADJUST_SIGNAL)                 \
	X(OPCODE_TYPE_ADJUST_DICTIONARY)             \
	X(OPCODE_TYPE_ADJUST_ARRAY)                  \
	X(OPCODE_TYPE_ADJUST_PACKED_BYTE_ARRAY)      \
	X(OPCODE_TYPE_ADJUST_PACKED_INT32_ARRAY)     \
	X(OPCODE_TYPE_ADJUST_PACKED_INT64_ARRAY)     \
	X(OPCODE_TYPE_ADJUST_PACKED_FLOAT32_ARRAY)   \
	X(OPCODE_TYPE_ADJUST_PACKED_FLOAT64_ARRAY)   \
	X(OPCODE_TYPE_ADJUST_PACKED_STRING_ARRAY)    \
	X(OPCODE_TYPE_ADJUST_PACKED_VECTOR2_ARRAY)   \
	X(OPCODE_TYPE_ADJUST_PACKED_VECTOR3_ARRAY)   \
	X(OPCODE_TYPE_ADJUST_PACKED_COLOR_ARRAY)     \
	X(OPCODE_TYPE_ADJUST_PACKED_VECTOR4_ARRAY)   \
	X(OPCODE_ASSERT)                             \
	X(OPCODE_BREAKPOINT)                         \
	X(OPCODE_LINE)                               \
	X(OPCODE_END)

// Check dispatch: a plain loop over the function's own bytecode, every opcode through the AOT lambda.
#define GD_AOT_CASE(m_op)                                                      \
	case m_op: {                                                               \
		const int next = aot_op(std::integral_constant<int, m_op>{});          \
		if (next == GD_AOT_EXIT) {                                             \
			goto OPSEXIT;                                                      \
		}                                                                      \
		ip = next;                                                             \
	} break;

#define GD_AOT_RUN                                 \
	for (;;) {                                     \
		switch (_code_ptr[ip]) {                   \
			GD_AOT_ALL_OPCODES(GD_AOT_CASE)        \
			default:                               \
				goto OPSEXIT;                      \
		}                                          \
	}

template <>
Variant GDScriptFunction::call_aot<0>(GDScriptInstance *p_instance, const Variant **p_args, int p_argcount, Callable::CallError &r_err, CallState *p_state) {
#define GD_AOT_CALL
#include "../gdscript_vm.cpp"
#undef GD_AOT_CALL
