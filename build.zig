const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // shared module
    const common = b.createModule(.{
        .root_source_file = b.path("src/common/format.zig"),
        .target = target,
        .optimize = optimize,
    });

    // CLI tool
    const cli_module = b.createModule(.{
        .root_source_file = b.path("src/cli/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    cli_module.addImport("common", common);
    cli_module.link_libc = true;

    const cli = b.addExecutable(.{
        .name = "fmt",
        .root_module = cli_module,
    });
    b.installArtifact(cli);

    // wasm
    const wasm_module = b.createModule(.{
        .root_source_file = b.path("src/wasm/main.zig"),
        .target = b.resolveTargetQuery(.{
            .cpu_arch = .wasm32,
            .os_tag = .freestanding,
        }),
        .optimize = .ReleaseSmall,
    });
    wasm_module.addImport("common", common);

    const wasm = b.addExecutable(.{
        .name = "wasm",
        .root_module = wasm_module,
    });
    wasm.rdynamic = true;
    wasm.entry = .disabled;

    const wasm_install = b.addInstallFile(
        wasm.getEmittedBin(),
        "../web/public/main.wasm", // relative to zig-out/
    );
    wasm_install.step.dependOn(&wasm.step);
    const wasm_step = b.step("wasm", "Build WASM target");
    wasm_step.dependOn(&wasm_install.step);

    // HTTP server
    // const server_module = b.createModule(.{
    //     .root_source_file = b.path("src/server/main.zig"),
    //     .target = target,
    //     .optimize = optimize,
    // });
    //server_module.addImport("common", common);

    // const server = b.addExecutable(.{
    //     .name = "fmtp-server",
    //     .root_module = server_module,
    // });
    // b.installArtifact(server);

    // run steps
    const run_cli = b.addRunArtifact(cli);
    //const run_server = b.addRunArtifact(server);
    if (b.args) |args| {
        run_cli.addArgs(args);
        //run_server.addArgs(args);
    }

    b.step("cli", "Run the CLI tool").dependOn(&run_cli.step);
    const check_step = b.step("check", "ZLS code analysis hook");

    const cli_check = b.addExecutable(.{
        .name = "fmt-check",
        .root_module = cli_module, // Reuse the exact same module graph
    });

    check_step.dependOn(&cli_check.step);

    const wasm_check = b.addExecutable(.{
        .name = "wasm",
        .root_module = wasm_module,
    });
    check_step.dependOn(&wasm_check.step);
    //b.step("server", "Run the HTTP server").dependOn(&run_server.step);

    // tests
    // const test_step = b.step("test", "Run all tests");
    // for (&[_][]const u8{
    //     "src/common/detect.zig",
    //     "src/common/format.zig",
    //     "src/cli/pipe.zig",
    // }) |path| {
    //     const test_module = b.createModule(.{
    //         .root_source_file = b.path(path),
    //         .target = target,
    //         .optimize = optimize,
    //     });
    //     test_module.addImport("common", common);
    //     const t = b.addTest(.{ .root_module = test_module });
    //     test_step.dependOn(&b.addRunArtifact(t).step);
    // }
}
