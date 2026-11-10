//! libbolt, Nemotron 3.5 Bolt's forward pass: an optional library nvcc builds beside the server from -Dbolt-src.

const std = @import("std");

const sources = [_][]const u8{ "bolt_kernels.cu", "bolt_mma.cu", "bolt_host.cu", "bolt_draft.cu" };

/// `zig build bolt -Dnvcc=NVCC -Dbolt-src=DIR`: native/lib/libbolt.so, which a Bolt checkpoint opens.
pub fn steps(b: *std.Build, nvcc: ?[]const u8) void {
    const step = b.step("bolt", "libbolt (Nemotron 3.5 Bolt's engine, sm_121) from -Dbolt-src with -Dnvcc, beside the server");
    const src = b.option([]const u8, "bolt-src", "the directory of libbolt's .cu sources (bolt_host.cu and its siblings)");
    const tool = nvcc orelse {
        step.dependOn(&b.addFail("zig build bolt needs -Dnvcc=PATH to nvcc").step);
        return;
    };
    const dir = src orelse {
        step.dependOn(&b.addFail("zig build bolt needs -Dbolt-src=DIR, the folder holding bolt_host.cu").step);
        return;
    };
    const root: std.Build.LazyPath = .{ .cwd_relative = dir };
    const windows = b.graph.host.result.os.tag == .windows;
    const name = if (windows) "bolt.dll" else "libbolt.so";
    const run = b.addSystemCommand(&.{ tool, "-shared", "-O3", "-gencode", "arch=compute_121a,code=sm_121a" });
    // Windows: the shared UCRT (/MD) so the server's setenv reaches the library, MSVC's conforming preprocessor and
    // M_SQRT2 for CUDA 13's headers, C++17 as gcc defaults to, and bolt.def naming the exports
    if (windows) run.addArgs(&.{ "-std=c++17", "-Xcompiler=/MD,/Zc:preprocessor,/EHsc", "-D_USE_MATH_DEFINES" }) else run.addArgs(&.{ "-Xcompiler", "-fPIC" });
    run.addArg("-I");
    run.addDirectoryArg(root);
    run.addArg("-o");
    const lib = run.addOutputFileArg(name);
    for (sources) |src_name| run.addFileArg(root.path(b, src_name));
    run.addArg("-lcuda");
    if (windows) run.addPrefixedFileArg("-Xlinker=/DEF:", root.path(b, "bolt.def"));
    step.dependOn(&b.addInstallFile(lib, b.fmt("native/lib/{s}", .{name})).step);
}
