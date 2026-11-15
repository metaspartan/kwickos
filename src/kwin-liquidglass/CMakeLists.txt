cmake_minimum_required(VERSION 3.20)
project(kwick_liquidglass VERSION 1.0 LANGUAGES CXX)

set(QT_MIN_VERSION "6.6.0")
set(KF_MIN_VERSION "6.0.0")
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(ECM ${KF_MIN_VERSION} REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} ${ECM_MODULE_PATH})

include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)

find_package(Qt6 ${QT_MIN_VERSION} CONFIG REQUIRED COMPONENTS Core Gui Quick Widgets)
find_package(KF6 ${KF_MIN_VERSION} REQUIRED COMPONENTS Config CoreAddons WindowSystem)
find_package(KWin REQUIRED)

list(APPEND CMAKE_AUTOMOC_MACRO_NAMES "KWIN_EFFECT_FACTORY_SUPPORTED")

kcoreaddons_add_plugin(kwick_liquidglass INSTALL_NAMESPACE "kwin/effects/plugins")

target_sources(kwick_liquidglass PRIVATE
    main.cpp
    liquidglasseffect.cpp
)

qt_add_resources(kwick_liquidglass "kwick_liquidglass_shaders"
    PREFIX "/effects/kwick_liquidglass"
    FILES
        shaders/pass.vert
        shaders/down.frag
        shaders/up.frag
        shaders/glass.frag
)

target_link_libraries(kwick_liquidglass PRIVATE
    KWin::kwin
    Qt6::Core
    Qt6::Gui
    KF6::ConfigCore
    KF6::CoreAddons
    epoxy::epoxy
)
