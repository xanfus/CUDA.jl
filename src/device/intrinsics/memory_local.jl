export alloc_local

# get a pointer to shared memory, with known (static) or zero length (dynamic shared memory)
@generated function emit_localmem(::Val{name}, ::Type{T}, ::Val{len}=Val(0)) where {name,T,len}
    JuliaContext() do ctx
        eltyp = convert(LLVMType, T, ctx)
        T_ptr = convert(LLVMType, LLVMPtr{T, AS.Local}, ctx)

        # create a function
        llvm_f, _ = create_function(T_ptr)

        # create the global variable
        mod = LLVM.parent(llvm_f)
        gv_typ = LLVM.ArrayType(eltyp, len)
        gv = GlobalVariable(mod, gv_typ, GPUCompiler.safe_name(string(name)), AS.Local)
        if len > 0
            linkage!(gv, LLVM.API.LLVMLinkOnceODRLinkage)
            initializer!(gv, null(gv_typ))
        end
        alignment!(gv, Base.datatype_alignment(T))

        # generate IR
        Builder(ctx) do builder
            entry = BasicBlock(llvm_f, "entry", ctx)
            position!(builder, entry)

            ptr = gep!(builder, gv, [ConstantInt(0, ctx), ConstantInt(0, ctx)])

            untyped_ptr = bitcast!(builder, ptr, T_ptr)

            ret!(builder, untyped_ptr)
        end

        call_function(llvm_f, LLVMPtr{T,AS.Local})
    end
end

"""
    alloc_local(name::Symbol, T::Type, dims::NTuple)

Allocates a `CuDeviceArray` backed by a global variable in local memory.

!!! note:
    Calls to `alloc_local` with the same `name` will alias within
    a kernel. This allows for the implmentation of thread local global state.
"""
@inline function alloc_local(name::Symbol, ::Type{T}, dims=(0,))
    ptr = emit_localmem(Val(name), T, Val(prod(dims)))
    CuDeviceArray(dims, ptr)
end
