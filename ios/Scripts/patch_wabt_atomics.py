#!/usr/bin/env python3
"""Patch pinned WABT CWriter for WebAssembly memory.atomic.wait/notify.

Apply to b835f1ce49e5803c597a0548099456d6be1d3d11 (pinned toolchain).
The portable sidecar implements actual wait queue semantics; it is not a
fake success/no-op replacement.
"""
import sys
from pathlib import Path
p=Path(sys.argv[1])
s=p.read_text()
old='''      case ExprType::AtomicWait:
      case ExprType::AtomicNotify:
      case ExprType::CallRef:
      case ExprType::ReturnCallRef:
      case ExprType::Quaternary:
        UNIMPLEMENTED("...");
        break;'''
new='''      case ExprType::AtomicWait: {
        const auto* op = cast<AtomicWaitExpr>(&expr);
        const Memory* memory = module_->memories[module_->GetMemoryIndex(op->memidx)];
        std::string api;
        if (op->opcode == Opcode::MemoryAtomicWait32) {
          api = "gta_wasm_atomic_wait32";
        } else if (op->opcode == Opcode::MemoryAtomicWait64) {
          api = "gta_wasm_atomic_wait64";
        } else {
          WABT_UNREACHABLE;
        }
        Write(StackVar(2, Type::I32), " = ", api, "(",
              ExternalInstancePtr(ModuleFieldType::Memory, memory->name), ", ");
        WriteMemoryAddress(2, memory, op->offset);
        Write(", ", StackVar(1), ", ", StackVar(0), ");", Newline());
        DropTypes(3);
        PushType(Type::I32);
        break;
      }

      case ExprType::AtomicNotify: {
        const auto* op = cast<AtomicNotifyExpr>(&expr);
        const Memory* memory = module_->memories[module_->GetMemoryIndex(op->memidx)];
        Write(StackVar(1, Type::I32), " = gta_wasm_atomic_notify(",
              ExternalInstancePtr(ModuleFieldType::Memory, memory->name), ", ");
        WriteMemoryAddress(1, memory, op->offset);
        Write(", ", StackVar(0), ");", Newline());
        DropTypes(2);
        PushType(Type::I32);
        break;
      }

      case ExprType::CallRef:
      case ExprType::ReturnCallRef:
      case ExprType::Quaternary:
        UNIMPLEMENTED("call_ref / return_call_ref / quaternary");
        break;'''
if s.count(old)!=1:
    raise SystemExit('Pinned WABT CWriter expression switch changed; refusing patch')
s=s.replace(old,new)
anchor='  Write(s_source_includes);'
if s.count(anchor)!=1:
    raise SystemExit('Pinned WABT include emission changed; refusing patch')
included='  Write(Newline(), "#include <gta-native-atomics.h>", Newline());'
s=s.replace(anchor,anchor+'\n'+included)
p.write_text(s)
print('Patched atomic wait32/wait64/notify C generation with real portable sidecar API')
