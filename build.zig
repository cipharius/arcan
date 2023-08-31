//! Experimental arcan build script
//! Tested with Zig version 0.11.0
const std = @import("std");

const a12_version = std.SemanticVersion{
    .major = 0,
    .minor = 1,
    .patch = 0,
};

const ashmif_version = std.SemanticVersion{
    .major = 0,
    .minor = 16,
    .patch = 0,
};

const flags = [_][]const u8{ "-fPIC", "-latomic" };

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Target: arcan_shmif
    const arcan_shmif_static = b.addStaticLibrary(.{
        .name = "arcan_shmif",
        .target = target,
        .optimize = optimize,
    });
    arcan_shmif_static.linkLibC();
    arcan_shmif_static.addCSourceFiles(&shmif_sources, &flags);
    inline for (shmif_include_paths) |dir| {
        arcan_shmif_static.addIncludePath(.{ .path = dir });
    }
    inline for (shmif_headers) |header| {
        arcan_shmif_static.installHeader(header[0], header[1]);
    }
    addShmifPlatformSources(arcan_shmif_static);
    addPlatformDefinitions(arcan_shmif_static);
    b.installArtifact(arcan_shmif_static);

    // Target: arcan_shmif_server
    const arcan_shmif_server_static = b.addStaticLibrary(.{
        .name = "arcan_shmif_server",
        .target = target,
        .optimize = optimize,
    });
    arcan_shmif_server_static.linkLibC();
    arcan_shmif_server_static.addCSourceFiles(&shmif_server_sources, &.{});
    inline for (shmif_include_paths) |dir| {
        arcan_shmif_server_static.addIncludePath(.{ .path = dir });
    }
    inline for (shmif_headers) |header| {
        arcan_shmif_server_static.installHeader(header[0], header[1]);
    }
    addShmifPlatformSources(arcan_shmif_server_static);
    addPlatformDefinitions(arcan_shmif_server_static);
    b.installArtifact(arcan_shmif_server_static);

    // Target: arcan_a12
    const arcan_a12_static = b.addStaticLibrary(.{
        .name = "arcan_a12",
        .target = target,
        .optimize = optimize,
    });
    arcan_a12_static.linkLibC();
    arcan_a12_static.linkLibrary(arcan_shmif_static);
    arcan_a12_static.linkLibrary(arcan_shmif_server_static);
    arcan_a12_static.addCSourceFiles(&a12_sources, &flags);
    arcan_a12_static.addCSourceFiles(&a12_external_sources, &flags);
    inline for (a12_include_paths) |path| {
        arcan_a12_static.addIncludePath(.{ .path = path });
    }
    inline for (a12_headers) |header| {
        arcan_a12_static.installHeader(header[0], header[1]);
    }
    arcan_a12_static.defineCMacro("BLAKE3_NO_AVX2", null);
    arcan_a12_static.defineCMacro("BLAKE3_NO_AVX512", null);
    arcan_a12_static.defineCMacro("BLAKE3_NO_SSE41", null);
    arcan_a12_static.defineCMacro("ZSTD_MULTITHREAD", null);
    addPlatformDefinitions(arcan_a12_static);
    b.installArtifact(arcan_a12_static);

    // Target: arcan-net
    const arcan_net = b.addExecutable(.{
        .name = "arcan-net",
        .target = target,
        .optimize = optimize,
    });
    arcan_net.linkLibC();
    arcan_net.linkLibrary(arcan_a12_static);
    arcan_net.defineCMacro("ARCAN_BUILDVERSION", "\"experimental-zig-build\"");
    arcan_net.addCSourceFiles(&arcan_net_sources, &.{});
    inline for (arcan_net_include_paths) |path| {
        arcan_net.addIncludePath(.{ .path = path });
    }
    addPlatformDefinitions(arcan_net);
    b.installArtifact(arcan_net);
}

fn addShmifPlatformSources(lib: *std.Build.Step.Compile) void {
    lib.addCSourceFiles(&shmif_platform_sources, &flags);
    lib.addCSourceFiles(
        &.{"src/platform/posix/fdpassing.c"},
        &.{ "-fPIC", "-w", "-DNONBLOCK_RECV" },
    );

    switch (lib.target_info.target.os.tag) {
        .linux, .freebsd, .openbsd, .dragonfly, .kfreebsd, .netbsd => {
            lib.addCSourceFiles(&shmif_platform_posix_sources, &flags);
        },
        .ios, .macos, .watchos, .tvos => {
            lib.addCSourceFiles(&shmif_platform_darwin_sources, &flags);
        },
        else => @panic("attempted to build arcan-shmif on an unsupported OS/platform"),
    }
}

fn addPlatformDefinitions(step: *std.Build.Step.Compile) void {
    const platform_definitions: []const [2][]const u8 = switch (step.target_info.target.os.tag) {
        .linux => &linux_platform_definitions,
        .ios, .macos, .watchos, .tvos => &darwin_platform_definitions,
        .freebsd => &(bsd_platform_definitions ++ .{.{ "__FreeBSD__", "" }}),
        .dragonfly => &(bsd_platform_definitions ++ .{.{ "__DragonFly__", "" }}),
        .kfreebsd => &(bsd_platform_definitions ++ .{.{ "__kFreeBSD__", "" }}),
        .openbsd => &(bsd_platform_definitions ++ .{
            .{ "__OpenBSD__", "" },
            .{ "CLOCK_MONOTONIC_RAW", "CLOCK_MONOTONIC" },
        }),
        .netbsd => &(bsd_platform_definitions ++ .{
            .{ "__NetBSD__", "" },
            .{ "CLOCK_MONOTONIC_RAW", "CLOCK_MONOTONIC" },
        }),
        else => &(.{}),
    };

    for (platform_definitions) |def| {
        step.defineCMacro(def[0], def[1]);
    }
}

fn arcanRootPath(comptime postfix: []const u8) []const u8 {
    if (postfix[0] != '/') @compileError("relative path expected");
    return comptime blk: {
        const root_dir = std.fs.path.dirname(@src().file) orelse ".";
        break :blk root_dir ++ postfix;
    };
}

const platform_header_path = arcanRootPath("/src/platform/platform.h");

const darwin_platform_definitions = [_][2][]const u8{
    .{ "__UNIX", "" },
    .{ "POSIX_C_SOURCE", "" },
    .{ "__APPLE__", "" },
    .{ "ARCAN_SHMIF_OVERCOMMIT", "" },
    .{ "_WITH_DPRINTF", "" },
    .{ "_GNU_SOURCE", "" },
    .{ "PLATFORM_HEADER", "\"" ++ platform_header_path ++ "\"" },
};

const linux_platform_definitions = [_][2][]const u8{
    .{ "__UNIX", "" },
    .{ "__LINUX", "" },
    .{ "POSIX_C_SOURCE", "" },
    .{ "_GNU_SOURCE", "" },
    .{ "PLATFORM_HEADER", "\"" ++ platform_header_path ++ "\"" },
};

const bsd_platform_definitions = [_][2][]const u8{
    .{ "PLATFORM_HEADER", "\"" ++ platform_header_path ++ "\"" },
    .{ "_WITH_GETLINE", "" },
    .{ "__UNIX", "" },
    .{ "__BSD", "" },
    .{ "LIBUSB_BSD", "" },
};

const shmif_headers = [_][2][]const u8{
    .{ "src/shmif/arcan_shmif_control.h", "arcan_shmif_control.h" },
    .{ "src/shmif/arcan_shmif_interop.h", "arcan_shmif_interop.h" },
    .{ "src/shmif/arcan_shmif_event.h", "arcan_shmif_event.h" },
    .{ "src/shmif/arcan_shmif_server.h", "arcan_shmif_server.h" },
    .{ "src/shmif/arcan_shmif_sub.h", "arcan_shmif_sub.h" },
    .{ "src/shmif/arcan_shmif_defs.h", "arcan_shmif_defs.h" },
    .{ "src/shmif/arcan_shmif.h", "arcan_shmif.h" },
};

const shmif_sources = [_][]const u8{
    "src/shmif/arcan_shmif_control.c",
    "src/shmif/arcan_shmif_sub.c",
    "src/shmif/arcan_shmif_evpack.c",
    "src/engine/arcan_trace.c",
    "src/shmif/platform/exec.c",
};

const shmif_platform_sources = [_][]const u8{
    "src/platform/posix/shmemop.c",
    "src/platform/posix/warning.c",
    "src/platform/posix/random.c",
    "src/platform/posix/fdscan.c",
};

const shmif_platform_posix_sources = [_][]const u8{
    "src/platform/posix/time.c",
    "src/platform/posix/sem.c",
};

const shmif_platform_darwin_sources = [_][]const u8{
    "src/platform/darwin/time.c",
    "src/platform/darwin/sem.c",
};

const shmif_server_sources = [_][]const u8{
    "src/shmif/arcan_shmif_server.c",
    "src/platform/posix/frameserver.c",
    "src/shmif/arcan_shmif_control.c",
    "src/platform/posix/fsrv_guard.c",
    "src/platform/posix/mem.c",
    "src/shmif/arcan_shmif_evpack.c",
    "src/shmif/platform/exec.c",
};

const shmif_include_paths = [_][]const u8{
    "src/shmif",
    "src/shmif/tui",
    "src/shmif/tui/lua",
    "src/shmif/tui/widgets",
    "src/shmif/platform",
    "src/engine",
    "src/platform",
};

const a12_headers = [_][2][]const u8{
    .{ "src/a12/a12.h", "a12.h" },
    .{ "src/a12/pack.h", "pack.h" },
    .{ "src/a12/a12_decode.h", "a12_decode.h" },
    .{ "src/a12/a12_encode.h", "a12_encode.h" },
};

const a12_sources = [_][]const u8{
    "src/a12/a12.c",
    "src/a12/a12_decode.c",
    "src/a12/a12_encode.c",
    "src/platform/posix/mem.c",
    "src/platform/posix/base64.c",
    "src/platform/posix/random.c",
};

const a12_external_sources = [_][]const u8{
    "src/a12/external/blake3/blake3.c",
    "src/a12/external/blake3/blake3_dispatch.c",
    "src/a12/external/blake3/blake3_portable.c",
    "src/a12/external/x25519.c",

    "src/a12/external/zstd/common/pool.c",
    "src/a12/external/zstd/common/debug.c",
    "src/a12/external/zstd/common/entropy_common.c",
    "src/a12/external/zstd/common/error_private.c",
    "src/a12/external/zstd/common/fse_decompress.c",
    "src/a12/external/zstd/common/pool.c",
    "src/a12/external/zstd/common/threading.c",
    "src/a12/external/zstd/common/xxhash.c",
    "src/a12/external/zstd/common/zstd_common.c",
    "src/a12/external/zstd/compress/fse_compress.c",
    "src/a12/external/zstd/compress/hist.c",
    "src/a12/external/zstd/compress/huf_compress.c",
    "src/a12/external/zstd/compress/zstd_compress.c",
    "src/a12/external/zstd/compress/zstd_compress_literals.c",
    "src/a12/external/zstd/compress/zstd_compress_sequences.c",
    "src/a12/external/zstd/compress/zstd_compress_superblock.c",
    "src/a12/external/zstd/compress/zstd_double_fast.c",
    "src/a12/external/zstd/compress/zstd_fast.c",
    "src/a12/external/zstd/compress/zstd_lazy.c",
    "src/a12/external/zstd/compress/zstd_ldm.c",
    "src/a12/external/zstd/compress/zstd_opt.c",
    "src/a12/external/zstd/compress/zstdmt_compress.c",
    "src/a12/external/zstd/decompress/huf_decompress.c",
    "src/a12/external/zstd/decompress/zstd_ddict.c",
    "src/a12/external/zstd/decompress/zstd_decompress.c",
    "src/a12/external/zstd/decompress/zstd_decompress_block.c",
};

const a12_include_paths = [_][]const u8{
    "src/a12",
    "src/a12/external/blake3",
    "src/a12/external/zstd",
    "src/a12/external/zstd/common",
    "src/a12/external",
    "src/engine",
    "src/shmif",
};

const arcan_net_sources = [_][]const u8{
    "src/a12/net/a12_helper_cl.c",
    "src/a12/net/a12_helper_srv.c",
    "src/a12/net/net.c",
    "src/a12/net/dir_cl.c",
    "src/a12/net/dir_srv.c",
    "src/a12/net/dir_supp.c",
    "src/frameserver/util/anet_helper.c",
    "src/frameserver/util/anet_keystore_naive.c",
};

const arcan_net_include_paths = [_][]const u8{
    "src/shmif",
    "src/a12/external",
    "src/a12/external/blake3",
    "src/a12",
    "src/engine",
    "src/frameserver/util",
};
