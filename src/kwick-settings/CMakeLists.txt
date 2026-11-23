cmake_minimum_required(VERSION 3.20)
project(kwick-settings VERSION 1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 6.6.0 CONFIG REQUIRED COMPONENTS Core Gui Widgets Qml Quick)
find_package(KF6WindowSystem 6.0.0 REQUIRED)

add_executable(kwick-settings-app main.cpp platform.h)
target_link_libraries(kwick-settings-app PRIVATE Qt6::Widgets Qt6::Qml Qt6::Quick KF6::WindowSystem)
install(TARGETS kwick-settings-app DESTINATION lib/kwick)
