cmake_minimum_required(VERSION 3.20)
project(kwickmac VERSION 1.0 LANGUAGES CXX)

set(QT_MIN_VERSION "6.6.0")
set(KF_MIN_VERSION "6.0.0")
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(ECM ${KF_MIN_VERSION} REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} ${ECM_MODULE_PATH})

include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)

find_package(Qt6 ${QT_MIN_VERSION} CONFIG REQUIRED COMPONENTS Core Gui Widgets)

add_library(kwickmac MODULE kwickmacstyle.cpp)
target_link_libraries(kwickmac PRIVATE Qt6::Core Qt6::Gui Qt6::Widgets)
install(TARGETS kwickmac DESTINATION ${KDE_INSTALL_QTPLUGINDIR}/styles)
