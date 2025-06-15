const android = @import("android");
const std = @import("std");

//This is targeting android version 10 / API level 29.
//Change the value here and in android/AndroidManifest.xml to target your desired API level
const android_version: android.APILevel = .android10;
const android_api = std.fmt.comptimePrint("{}", .{@intFromEnum(android_version)});

const exe_name = "CrappyBird";

fn Pair(T: type, R: type) type {
    return struct {
        first: T,
        second: R,

        fn init(first: T, second: R) Pair(T, R) {
            return .{
                .first = first,
                .second = second,
            };
        }
    };
}

pub fn build(b: *std.Build) void {
    const root_target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const android_targets = android.standardTargets(b, root_target);

    if (android_targets.len > 0) {
        const android_tools = android.Tools.create(b, .{
            .api_level = android_version,
            .build_tools_version = "35.0.1",
            .ndk_version = "29.0.13599879",
        });

        const key_store_file = android_tools.createKeyStore(android.CreateKey.example());
        const android_apk = android.APK.create(b, android_tools);

        android_apk.setKeyStore(key_store_file);
        android_apk.setAndroidManifest(b.path("android/AndroidManifest.xml"));
        android_apk.addResourceDirectory(b.path("android/res"));

        for (android_targets) |target| {
            buildAndroid(b, target, optimize, android_apk);
        }

        android_apk.installApk();
    }

    else buildNative(b, root_target, optimize);
}

pub fn buildAndroid(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, apk: *android.APK) void {
    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .linkage = .dynamic,
        .name = exe_name,
        .root_module = lib_mod,
    });

    lib.linkLibC();
    b.installArtifact(lib);

    const android_ndk_path = b.fmt(
        "{s}/ndk/{s}",
        .{ apk.tools.android_sdk_path, apk.tools.ndk_version },
    );

    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
        .android_api_version = @as([]const u8, android_api),
        .android_ndk = @as([]const u8, android_ndk_path),
    });

    const raylib_artifact = raylib_dep.artifact("raylib");
    lib.linkLibrary(raylib_artifact);

    const raylib_mod = raylib_dep.module("raylib");
    lib.root_module.addImport("raylib", raylib_mod);

    const android_dep = b.dependency("android", .{
        .optimize = optimize,
        .target = target,
    });

    lib.root_module.linkSystemLibrary("android", .{ .preferred_link_mode = .dynamic });
    lib.root_module.addImport("android", android_dep.module("android"));

    const native_app_glue_dir: std.Build.LazyPath = .{ 
        .cwd_relative = b.fmt(
            "{s}/sources/android/native_app_glue",
            .{android_ndk_path},
        ),
    };
    
    lib.root_module.addCSourceFile(.{
        .file = native_app_glue_dir.path(b, "android_native_app_glue.c") ,
    });

    lib.root_module.addIncludePath(native_app_glue_dir);

    lib.root_module.linkSystemLibrary(
        "log",
        .{.preferred_link_mode = .dynamic }.
    );

    apk.addArtifact(lib);
}

pub fn buildNative(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .linkage = .dynamic,
        .name = exe_name,
        .root_module = lib_mod,
    });

    lib.linkLibC();
    b.installArtifact(lib);

    const raylib_dep = b.dependency(
        "raylib_zig", 
        .{
            .target = target,
            .optimize = optimize, 
            .shared = true,
        },
    );
    
    const raylib_artifact = raylib_dep.artifact("raylib");
    lib.linkLibrary(raylib_artifact);

    const raylib_mod = raylib_dep.module("raylib");
    lib.root_module.addImport("raylib", raylib_mod);


    const run_step = b.step("run", "Run the application");
    
    const exe = b.addExecutable(.{
        .name = exe_name,
        .optimize = optimize,
        .root_module = lib_mod 
    });

    b.installArtifact(exe);
    const run_exe = b.addRunArtifact(exe);
    run_step.dependOn(&run_exe.step);
}
