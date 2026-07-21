_GHOSTTY_BUILD_FILE = """\
load("@rules_swift//swift:swift_interop_hint.bzl", "swift_interop_hint")

swift_interop_hint(
    name = "GhosttyKit_swift_interop",
    module_map = "GhosttyKit.xcframework/macos-arm64_x86_64/Headers/module.modulemap",
    module_name = "GhosttyKit",
)

cc_import(
    name = "ghostty_internal_archive",
    static_library = "GhosttyKit.xcframework/macos-arm64_x86_64/libghostty-internal.a",
)

cc_library(
    name = "GhosttyKit",
    hdrs = ["GhosttyKit.xcframework/macos-arm64_x86_64/Headers/ghostty.h"],
    aspect_hints = [":GhosttyKit_swift_interop"],
    defines = ["GHOSTTY_STATIC"],
    deps = [":ghostty_internal_archive"],
    includes = ["GhosttyKit.xcframework/macos-arm64_x86_64/Headers"],
    linkopts = [
        "-ObjC",
        "-lc++",
        "-framework", "AppKit",
        "-framework", "Carbon",
        "-framework", "CoreGraphics",
        "-framework", "CoreText",
        "-framework", "Foundation",
        "-framework", "GameController",
        "-framework", "IOSurface",
        "-framework", "Metal",
        "-framework", "QuartzCore",
    ],
    visibility = ["//visibility:public"],
)
"""

def _workspace_root(repository_ctx):
    return str(repository_ctx.path(repository_ctx.attr.workspace_marker).dirname)

def _maybe_link_local_xcframework(repository_ctx):
    if not repository_ctx.attr.local_xcframework_path:
        return False

    local_path = repository_ctx.path(
        _workspace_root(repository_ctx) + "/" + repository_ctx.attr.local_xcframework_path,
    )
    if not local_path.exists:
        return False

    repository_ctx.symlink(local_path, "GhosttyKit.xcframework")
    return True

def _download_ghostty_source(repository_ctx):
    if repository_ctx.attr.urls:
        repository_ctx.download_and_extract(
            sha256 = repository_ctx.attr.sha256,
            stripPrefix = repository_ctx.attr.strip_prefix,
            urls = repository_ctx.attr.urls,
        )
        return

    repository_ctx.download_and_extract(
        sha256 = repository_ctx.attr.sha256,
        stripPrefix = "ghostty-" + repository_ctx.attr.commit,
        urls = [
            "https://github.com/ghostty-org/ghostty/archive/%s.tar.gz" % repository_ctx.attr.commit,
        ],
    )

def _build_xcframework(repository_ctx):
    zig = repository_ctx.which(repository_ctx.attr.zig)
    if zig == None:
        fail("GhosttyKit requires Zig to build Ghostty from source. Install Zig or set local_xcframework_path to an existing GhosttyKit.xcframework.")

    result = repository_ctx.execute(
        [
            zig,
            "build",
            "-Dapp-runtime=none",
            "-Demit-xcframework=true",
            "-Demit-macos-app=false",
            "-Demit-docs=false",
            "-Demit-webdata=false",
            "-Demit-bench=false",
            "-Demit-helpgen=false",
            "-Demit-test-exe=false",
            "-Doptimize=ReleaseFast",
        ],
        timeout = 7200,
    )
    if result.return_code != 0:
        fail("failed to build GhosttyKit.xcframework:\nSTDOUT:\n%s\nSTDERR:\n%s" % (result.stdout, result.stderr))

    generated = repository_ctx.path("zig-out/macos/GhosttyKit.xcframework")
    if not generated.exists:
        fail("Ghostty build completed but zig-out/macos/GhosttyKit.xcframework was not produced")

    repository_ctx.symlink(generated, "GhosttyKit.xcframework")

def _ghostty_kit_repository_impl(repository_ctx):
    if not _maybe_link_local_xcframework(repository_ctx):
        _download_ghostty_source(repository_ctx)
        _build_xcframework(repository_ctx)

    repository_ctx.file("BUILD.bazel", _GHOSTTY_BUILD_FILE)

ghostty_kit_repository = repository_rule(
    implementation = _ghostty_kit_repository_impl,
    attrs = {
        "commit": attr.string(mandatory = True),
        "local_xcframework_path": attr.string(),
        "sha256": attr.string(),
        "strip_prefix": attr.string(),
        "urls": attr.string_list(),
        "workspace_marker": attr.label(default = Label("//:Package.swift")),
        "zig": attr.string(default = "zig"),
    },
    environ = ["PATH"],
)

_dependency = tag_class(
    attrs = {
        "commit": attr.string(mandatory = True),
        "local_xcframework_path": attr.string(),
        "name": attr.string(default = "ghostty_kit"),
        "sha256": attr.string(),
        "strip_prefix": attr.string(),
        "urls": attr.string_list(),
        "zig": attr.string(default = "zig"),
    },
)

def _ghostty_deps_impl(module_ctx):
    for module in module_ctx.modules:
        for dep in module.tags.dependency:
            ghostty_kit_repository(
                name = dep.name,
                commit = dep.commit,
                local_xcframework_path = dep.local_xcframework_path,
                sha256 = dep.sha256,
                strip_prefix = dep.strip_prefix,
                urls = dep.urls,
                zig = dep.zig,
            )

ghostty_deps = module_extension(
    implementation = _ghostty_deps_impl,
    tag_classes = {
        "dependency": _dependency,
    },
)
