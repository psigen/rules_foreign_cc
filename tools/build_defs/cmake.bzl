""" Defines the rule for building external library with CMake
"""

load(
    "//tools/build_defs:framework.bzl",
    "CC_EXTERNAL_RULE_ATTRIBUTES",
    "cc_external_rule_impl",
    "create_attrs",
)
load(
    "//tools/build_defs:detect_root.bzl",
    "detect_root",
)
load(
    "//tools/build_defs:cc_toolchain_util.bzl",
    "get_flags_info",
    "get_tools_info",
    "is_debug_mode",
)
load(":cmake_script.bzl", "create_cmake_script")
load("@foreign_cc_platform_utils//:os_info.bzl", "OSInfo")
load("@foreign_cc_platform_utils//:tools.bzl", "CMAKE_USE_BUILT")

def _cmake_external(ctx):
    tools_deps = ctx.attr.tools_deps + ([ctx.attr._cmake_dep] if hasattr(ctx.attr, "_cmake_dep") else [])
    attrs = create_attrs(
        ctx.attr,
        configure_name = "CMake",
        create_configure_script = _create_configure_script,
        postfix_script = "copy_dir_contents_to_dir $BUILD_TMPDIR/$INSTALL_PREFIX $INSTALLDIR\n" + ctx.attr.postfix_script,
        tools_deps = tools_deps,
    )

    return cc_external_rule_impl(ctx, attrs)

def _create_configure_script(configureParameters):
    ctx = configureParameters.ctx
    inputs = configureParameters.inputs

    root = detect_root(ctx.attr.lib_source)

    tools = get_tools_info(ctx)
    flags = get_flags_info(ctx)
    no_toolchain_file = ctx.attr.cache_entries.get("CMAKE_TOOLCHAIN_FILE") or not ctx.attr.generate_crosstool_file

    define_install_prefix = "export INSTALL_PREFIX=\"" + _get_install_prefix(ctx) + "\"\n"
    configure_script = create_cmake_script(
        ctx.workspace_name,
        ctx.attr._target_os[OSInfo],
        tools,
        flags,
        "$INSTALL_PREFIX",
        root,
        no_toolchain_file,
        dict(ctx.attr.cache_entries),
        dict(ctx.attr.env_vars),
        ctx.attr.cmake_options,
        is_debug_mode(ctx),
    )
    return define_install_prefix + configure_script

def _get_install_prefix(ctx):
    if ctx.attr.install_prefix:
        prefix = ctx.attr.install_prefix

        # If not in sandbox, or after the build, the value can be absolute.
        # So if the user passed the absolute value, do not touch it.
        if (prefix.startswith("/")):
            return prefix
        return prefix if prefix.startswith("./") else "./" + prefix
    if ctx.attr.lib_name:
        return "./" + ctx.attr.lib_name
    return "./" + ctx.attr.name

def _attrs():
    attrs = dict(CC_EXTERNAL_RULE_ATTRIBUTES)
    attrs.update({
        # Relative install prefix to be passed to CMake in -DCMAKE_INSTALL_PREFIX
        "install_prefix": attr.string(mandatory = False),
        # CMake cache entries to initialize (they will be passed with -Dkey=value)
        # Values, defined by the toolchain, will be joined with the values, passed here.
        # (Toolchain values come first)
        "cache_entries": attr.string_dict(mandatory = False, default = {}),
        # CMake environment variable values to join with toolchain-defined.
        # For example, additional CXXFLAGS.
        "env_vars": attr.string_dict(mandatory = False, default = {}),
        # Other CMake options
        "cmake_options": attr.string_list(mandatory = False, default = []),
        # When True, CMake crosstool file will be generated from the toolchain values,
        # provided cache-entries and env_vars (some values will still be passed as -Dkey=value
        # and environment variables).
        # If CMAKE_TOOLCHAIN_FILE cache entry is passed, specified crosstool file will be used
        # When using this option, it makes sense to specify CMAKE_SYSTEM_NAME in the
        # cache_entries - the rule makes only a poor guess about the target system,
        # it is better to specify it manually.
        "generate_crosstool_file": attr.bool(mandatory = False, default = False),
    })
    if CMAKE_USE_BUILT == True:
        # include cmake only if needed
        attrs.update({
            "_cmake_dep": attr.label(
                default = "@foreign_cc_platform_utils//:cmake",
                cfg = "target",
                allow_files = True,
            ),
        })
    return attrs

""" Rule for building external library with CMake.
 Attributes:
   See line comments in _attrs() method.
 Other attributes are documented in framework.bzl:CC_EXTERNAL_RULE_ATTRIBUTES
"""
cmake_external = rule(
    attrs = _attrs(),
    fragments = ["cpp"],
    output_to_genfiles = True,
    implementation = _cmake_external,
)
