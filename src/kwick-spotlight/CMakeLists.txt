cmake_minimum_required(VERSION 3.20)
project(kwick-spotlight VERSION 1.0 LANGUAGES CXX)

set(QT_MIN_VERSION "6.6.0")
set(KF_MIN_VERSION "6.0.0")
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(ECM ${KF_MIN_VERSION} REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} ${ECM_MODULE_PATH})

include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)

find_package(Qt6 ${QT_MIN_VERSION} CONFIG REQUIRED COMPONENTS Core Gui DBus Qml Quick)
find_package(Qt6Gui ${QT_MIN_VERSION} CONFIG REQUIRED COMPONENTS Private)
find_package(KF6 ${KF_MIN_VERSION} REQUIRED COMPONENTS Config CoreAddons DBusAddons GlobalAccel KIO Runner Service WindowSystem)
find_package(LayerShellQt REQUIRED)
find_package(PkgConfig REQUIRED)
pkg_check_modules(WaylandClient REQUIRED IMPORTED_TARGET wayland-client)

add_executable(kwick-spotlight main.cpp spotlight.cpp resultmodel.cpp)
target_link_libraries(kwick-spotlight PRIVATE Qt6::DBus Qt6::GuiPrivate Qt6::Quick PkgConfig::WaylandClient KF6::ConfigCore KF6::DBusAddons KF6::GlobalAccel KF6::Runner KF6::WindowSystem LayerShellQt::Interface)
install(TARGETS kwick-spotlight DESTINATION ${KDE_INSTALL_BINDIR})

kcoreaddons_add_plugin(krunner_kwick SOURCES kwickrunner.cpp fileindex.cpp INSTALL_NAMESPACE "kf6/krunner")
target_link_libraries(krunner_kwick PRIVATE Qt6::DBus Qt6::Gui KF6::KIOGui KF6::Runner KF6::Service)
