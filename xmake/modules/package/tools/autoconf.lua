--!A cross-platform build utility based on Lua
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--
-- Copyright (C) 2015-present, TBOOX Open Source Group.
--
-- @author      ruki
-- @file        autoconf.lua
--

-- imports
import("core.base.option")
import("core.project.config")
import("core.tool.linker")
import("core.tool.compiler")
import("lib.detect.find_tool")

-- translate path
function _translate_path(package, p)
    if p and is_host("windows") and (package:is_plat("mingw") or package:is_plat("msys") or package:is_plat("cygwin")) then
        p = p:gsub("\\", "/")
    end
    return p
end

-- translate windows bin path
function _translate_windows_bin_path(bin_path)
    if bin_path then
        local argv = os.argv(bin_path)
        argv[1] = argv[1]:gsub("\\", "/") .. ".exe"
        return os.args(argv)
    end
end

-- map compiler flags
function _map_compflags(package, langkind, name, values)
    return compiler.map_flags(langkind, name, values, {target = package})
end

-- map linker flags
function _map_linkflags(package, targetkind, sourcekinds, name, values)
    return linker.map_flags(targetkind, sourcekinds, name, values, {target = package})
end

-- get configs
function _get_configs(package, configs)

    -- add prefix
    local configs = configs or {}
    table.insert(configs, "--prefix=" .. _translate_path(package, package:installdir()))

    -- add host for cross-complation
    if not configs.host and not package:is_plat(os.subhost()) then
        if package:is_plat("iphoneos") then
            local triples =
            {
                arm64  = "aarch64-apple-darwin",
                arm64e = "aarch64-apple-darwin",
                armv7  = "armv7-apple-darwin",
                armv7s = "armv7s-apple-darwin",
                i386   = "i386-apple-darwin",
                x86_64 = "x86_64-apple-darwin"
            }
            table.insert(configs, "--host=" .. (triples[package:arch()] or triples.arm64))
        elseif package:is_plat("android") then
            -- @see https://developer.android.com/ndk/guides/other_build_systems#autoconf
            local triples =
            {
                ["armv5te"]     = "arm-linux-androideabi",  -- deprecated
                ["armv7-a"]     = "arm-linux-androideabi",  -- deprecated
                ["armeabi"]     = "arm-linux-androideabi",  -- removed in ndk r17
                ["armeabi-v7a"] = "arm-linux-androideabi",
                ["arm64-v8a"]   = "aarch64-linux-android",
                i386            = "i686-linux-android",     -- deprecated
                x86             = "i686-linux-android",
                x86_64          = "x86_64-linux-android",
                mips            = "mips-linux-android",     -- removed in ndk r17
                mips64          = "mips64-linux-android"    -- removed in ndk r17
            }
            table.insert(configs, "--host=" .. (triples[package:arch()] or triples["armeabi-v7a"]))
        elseif package:is_plat("mingw") then
            local triples =
            {
                i386   = "i686-w64-mingw32",
                x86_64 = "x86_64-w64-mingw32"
            }
            table.insert(configs, "--host=" .. (triples[package:arch()] or triples.i386))
        elseif package:is_plat("cross") then
            local host = package:arch()
            if package:is_arch("arm64") then
                host = "aarch64"
            elseif package:is_arch("arm.*") then
                host = "arm"
            end
            host = host .. "-" .. package:targetos()
            table.insert(configs, "--host=" .. host)
        end
    end
    return configs
end

-- get the build environments
function buildenvs(package, opt)
    opt = opt or {}
    local envs = {}
    local cppflags = {}
    if package:is_plat(os.subhost()) then
        local cflags   = table.join(table.wrap(package:config("cxflags")), package:config("cflags"))
        local cxxflags = table.join(table.wrap(package:config("cxflags")), package:config("cxxflags"))
        local asflags  = table.copy(table.wrap(package:config("asflags")))
        local ldflags  = table.copy(table.wrap(package:config("ldflags")))
        if package:is_plat("linux") and package:is_arch("i386") then
            table.insert(cflags,   "-m32")
            table.insert(cxxflags, "-m32")
            table.insert(asflags,  "-m32")
            table.insert(ldflags,  "-m32")
        end
        table.join2(cflags,   opt.cflags)
        table.join2(cflags,   opt.cxflags)
        table.join2(cxxflags, opt.cxxflags)
        table.join2(cxxflags, opt.cxflags)
        table.join2(cppflags, opt.cppflags) -- @see https://github.com/xmake-io/xmake/issues/1688
        table.join2(asflags,  opt.asflags)
        table.join2(ldflags,  opt.ldflags)
        envs.CFLAGS    = table.concat(cflags, ' ')
        envs.CXXFLAGS  = table.concat(cxxflags, ' ')
        envs.CPPFLAGS  = table.concat(cppflags, ' ')
        envs.ASFLAGS   = table.concat(asflags, ' ')
        envs.LDFLAGS   = table.concat(ldflags, ' ')
    else
        local cflags         = table.join(table.wrap(package:build_getenv("cxflags")), package:build_getenv("cflags"))
        local cxxflags       = table.join(table.wrap(package:build_getenv("cxflags")), package:build_getenv("cxxflags"))
        local asflags        = table.copy(table.wrap(package:build_getenv("asflags")))
        local ldflags        = table.copy(table.wrap(package:build_getenv("ldflags")))
        local shflags        = table.copy(table.wrap(package:build_getenv("shflags")))
        local arflags        = table.copy(table.wrap(package:build_getenv("arflags")))
        local defines        = package:build_getenv("defines")
        local includedirs    = package:build_getenv("includedirs")
        local sysincludedirs = package:build_getenv("sysincludedirs")
        local links          = package:build_getenv("links")
        local syslinks       = package:build_getenv("syslinks")
        local linkdirs       = package:build_getenv("linkdirs")
        table.join2(cflags,   opt.cflags)
        table.join2(cflags,   opt.cxflags)
        table.join2(cxxflags, opt.cxxflags)
        table.join2(cxxflags, opt.cxflags)
        table.join2(cppflags, opt.cppflags) -- @see https://github.com/xmake-io/xmake/issues/1688
        table.join2(asflags,  opt.asflags)
        table.join2(ldflags,  opt.ldflags)
        table.join2(shflags,  opt.shflags)
        table.join2(cflags,   _map_compflags(package, "c", "define", defines))
        table.join2(cflags,   _map_compflags(package, "c", "includedir", includedirs))
        table.join2(cflags,   _map_compflags(package, "c", "sysincludedir", sysincludedirs))
        table.join2(asflags,  _map_compflags(package, "as", "define", defines))
        table.join2(asflags,  _map_compflags(package, "as", "includedir", includedirs))
        table.join2(asflags,  _map_compflags(package, "as", "sysincludedir", sysincludedirs))
        table.join2(cxxflags, _map_compflags(package, "cxx", "define", defines))
        table.join2(cxxflags, _map_compflags(package, "cxx", "includedir", includedirs))
        table.join2(cxxflags, _map_compflags(package, "cxx", "sysincludedir", sysincludedirs))
        table.join2(ldflags,  _map_linkflags(package, "binary", {"cxx"}, "link", links))
        table.join2(ldflags,  _map_linkflags(package, "binary", {"cxx"}, "syslink", syslinks))
        table.join2(ldflags,  _map_linkflags(package, "binary", {"cxx"}, "linkdir", linkdirs))
        table.join2(shflags,  _map_linkflags(package, "shared", {"cxx"}, "link", links))
        table.join2(shflags,  _map_linkflags(package, "shared", {"cxx"}, "syslink", syslinks))
        table.join2(shflags,  _map_linkflags(package, "shared", {"cxx"}, "linkdir", linkdirs))
        envs.CC        = package:build_getenv("cc")
        envs.AS        = package:build_getenv("as")
        envs.AR        = package:build_getenv("ar")
        envs.LD        = package:build_getenv("ld")
        envs.LDSHARED  = package:build_getenv("sh")
        envs.CPP       = package:build_getenv("cpp")
        envs.RANLIB    = package:build_getenv("ranlib")
        envs.CFLAGS    = table.concat(cflags, ' ')
        envs.CXXFLAGS  = table.concat(cxxflags, ' ')
        envs.CPPFLAGS  = table.concat(cppflags, ' ')
        envs.ASFLAGS   = table.concat(asflags, ' ')
        envs.ARFLAGS   = table.concat(arflags, ' ')
        envs.LDFLAGS   = table.concat(ldflags, ' ')
        envs.SHFLAGS   = table.concat(shflags, ' ')
        if package:is_plat("mingw") then
            -- fix linker error, @see https://github.com/xmake-io/xmake/issues/574
            -- libtool: line 1855: lib: command not found
            envs.ARFLAGS = nil
            local ld = envs.LD
            if ld then
                if ld:endswith("x86_64-w64-mingw32-g++") then
                    envs.LD = path.join(path.directory(ld), is_host("windows") and "ld" or "x86_64-w64-mingw32-ld")
                elseif ld:endswith("i686-w64-mingw32-g++") then
                    envs.LD = path.join(path.directory(ld), is_host("windows") and "ld" or "i686-w64-mingw32-ld")
                end
            end
            if is_host("windows") then
                envs.CC       = _translate_windows_bin_path(envs.CC)
                envs.AS       = _translate_windows_bin_path(envs.AS)
                envs.AR       = _translate_windows_bin_path(envs.AR)
                envs.LD       = _translate_windows_bin_path(envs.LD)
                envs.LDSHARED = _translate_windows_bin_path(envs.LDSHARED)
                envs.CPP      = _translate_windows_bin_path(envs.CPP)
                envs.RANLIB   = _translate_windows_bin_path(envs.RANLIB)
            end
        elseif package:is_plat("cross") then
            -- only for cross-toolchain
            envs.CXX = package:build_getenv("cxx")
            if not envs.ARFLAGS or envs.ARFLAGS == "" then
                envs.ARFLAGS = "-cr"
            end
        end
    end
    local ACLOCAL_PATH = {}
    local PKG_CONFIG_PATH = {}
    for _, dep in ipairs(package:orderdeps()) do
        local pkgconfig = path.join(dep:installdir(), "lib", "pkgconfig")
        if os.isdir(pkgconfig) then
            table.insert(PKG_CONFIG_PATH, pkgconfig)
        end
        pkgconfig = path.join(dep:installdir(), "share", "pkgconfig")
        if os.isdir(pkgconfig) then
            table.insert(PKG_CONFIG_PATH, pkgconfig)
        end
        local aclocal = path.join(dep:installdir(), "share", "aclocal")
        if os.isdir(aclocal) then
            table.insert(ACLOCAL_PATH, aclocal)
        end
    end
    envs.ACLOCAL_PATH    = path.joinenv(ACLOCAL_PATH)
    envs.PKG_CONFIG_PATH = path.joinenv(PKG_CONFIG_PATH)
    return envs
end

-- get the autogen environments
function autogen_envs(package, opt)
    opt = opt or {}
    local envs = {NOCONFIGURE = "yes"}
    local ACLOCAL_PATH = {}
    local PKG_CONFIG_PATH = {}
    for _, dep in ipairs(package:orderdeps()) do
        local pkgconfig = path.join(dep:installdir(), "lib", "pkgconfig")
        if os.isdir(pkgconfig) then
            table.insert(PKG_CONFIG_PATH, pkgconfig)
        end
        pkgconfig = path.join(dep:installdir(), "share", "pkgconfig")
        if os.isdir(pkgconfig) then
            table.insert(PKG_CONFIG_PATH, pkgconfig)
        end
        local aclocal = path.join(dep:installdir(), "share", "aclocal")
        if os.isdir(aclocal) then
            table.insert(ACLOCAL_PATH, aclocal)
        end
    end
    envs.ACLOCAL_PATH    = path.joinenv(ACLOCAL_PATH)
    envs.PKG_CONFIG_PATH = path.joinenv(PKG_CONFIG_PATH)
    return envs
end

-- configure package
function configure(package, configs, opt)

    -- init options
    opt = opt or {}

    -- get envs
    local envs = opt.envs or buildenvs(package, opt)

    -- generate configure file
    if not os.isfile("configure") then
        if os.isfile("autogen.sh") then
            os.vrunv("sh", {"./autogen.sh"}, {envs = autogen_envs(package, opt)})
        elseif os.isfile("configure.ac") then
            os.vrunv("sh", {"autoreconf", "--install", "--symlink"}, {envs = autogen_envs(package, opt)})
        end
    end

    -- pass configurations
    local argv = {"./configure"}
    for name, value in pairs(_get_configs(package, configs)) do
        value = tostring(value):trim()
        if value ~= "" then
            if type(name) == "number" then
                table.insert(argv, value)
            else
                table.insert(argv, "--" .. name .. "=" .. value)
            end
        end
    end

    -- do configure
    os.vrunv("sh", argv, {envs = envs})
end

-- do make
function make(package, argv, opt)
    opt = opt or {}
    local program
    if package:is_plat("mingw") and is_subhost("windows") then
        local mingw = assert(package:build_getenv("mingw") or package:build_getenv("sdk"), "mingw not found!")
        program = path.join(mingw, "bin", "mingw32-make.exe")
    else
        local tool = find_tool("make")
        if tool then
            program = tool.program
        end
    end
    assert(program, "make not found!")
    os.vrunv(program, argv)
end

-- build package
function build(package, configs, opt)

    -- do configure
    configure(package, configs, opt)

    -- do make and install
    opt = opt or {}
    local njob = opt.jobs or option.get("jobs") or tostring(os.default_njob())
    local argv = {"-j" .. njob}
    if option.get("verbose") then
        table.insert(argv, "V=1")
    end
    make(package, argv, opt)
end

-- install package
function install(package, configs, opt)

    -- do build
    opt = opt or {}
    build(package, configs, opt)

    -- do install
    local argv = {"install"}
    if option.get("verbose") then
        table.insert(argv, "V=1")
    end
    make(package, argv, opt)
end

