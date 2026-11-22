cmake_minimum_required(VERSION 3.20)
project(kwick-nearby VERSION 1.0 LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

find_package(Qt6 6.6 REQUIRED COMPONENTS Core Gui DBus Network Qml Quick Svg)
find_package(KF6Config 6.0 REQUIRED)
find_package(KF6DBusAddons 6.0 REQUIRED)
find_package(LayerShellQt REQUIRED)
find_package(OpenSSL 3 REQUIRED COMPONENTS Crypto)
find_package(PkgConfig)
include(GNUInstallDirs)

qt_standard_project_setup(REQUIRES 6.6)
qt_policy(SET QTP0001 NEW)

qt_add_executable(kwick-nearby
    main.cpp
    settings.cpp settings.h
    identity.cpp identity.h
    protocol.cpp protocol.h
    server.cpp server.h
    discovery.cpp discovery.h
    sender.cpp sender.h
    portal.cpp portal.h
    nearby.cpp nearby.h
    images.cpp images.h
)

set(NEARBY_ICONS
    icons/close.svg icons/phone.svg icons/laptop.svg icons/desktop.svg
    icons/globe.svg icons/server.svg icons/terminal.svg icons/doc.svg
    icons/folder.svg icons/text.svg icons/check.svg icons/chevron.svg
    icons/plus.svg icons/waves.svg icons/lock.svg icons/link.svg
    icons/image.svg icons/film.svg icons/music.svg icons/archive.svg
)

qt_add_qml_module(kwick-nearby
    URI KwickNearby
    VERSION 1.0
    QML_FILES
        qml/Look.qml
        qml/Glyph.qml
        qml/PushButton.qml
        qml/Avatar.qml
        qml/Radar.qml
        qml/DeviceTile.qml
        qml/ItemPreview.qml
        qml/VisibilityMenu.qml
        qml/ShareSheet.qml
        qml/Incoming.qml
    RESOURCES ${NEARBY_ICONS}
)

target_compile_definitions(kwick-nearby PRIVATE QT_NO_KEYWORDS)
target_link_libraries(kwick-nearby PRIVATE
    Qt6::Core Qt6::Gui Qt6::DBus Qt6::Network Qt6::Qml Qt6::Quick Qt6::Svg
    KF6::ConfigCore KF6::DBusAddons LayerShellQt::Interface OpenSSL::Crypto)
target_link_options(kwick-nearby PRIVATE -Wl,--as-needed -Wl,-O1)

install(TARGETS kwick-nearby RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES data/kwick-nearby.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
install(FILES data/kwick-nearby-autostart.desktop DESTINATION /etc/xdg/autostart RENAME kwick-nearby.desktop)
install(FILES data/kwick-nearby-servicemenu.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/kio/servicemenus RENAME kwick-nearby.desktop)
install(FILES data/org.kwickos.kwick-nearby.service DESTINATION ${CMAKE_INSTALL_DATADIR}/dbus-1/services)
install(FILES data/kwick-nearby.svg DESTINATION ${CMAKE_INSTALL_DATADIR}/icons/hicolor/scalable/apps)
install(FILES data/kwick-nearby-symbolic.svg DESTINATION ${CMAKE_INSTALL_DATADIR}/icons/hicolor/scalable/status)

if(PkgConfig_FOUND)
    pkg_check_modules(NAUTILUS IMPORTED_TARGET libnautilus-extension-4)
endif()
if(NAUTILUS_FOUND)
    add_library(kwick-nearby-nautilus MODULE nautilus/kwick-nearby-nautilus.c)
    target_link_libraries(kwick-nearby-nautilus PRIVATE PkgConfig::NAUTILUS)
    set_target_properties(kwick-nearby-nautilus PROPERTIES PREFIX "lib" C_VISIBILITY_PRESET hidden)
    pkg_get_variable(NAUTILUS_EXTDIR libnautilus-extension-4 extensiondir)
    if(NOT NAUTILUS_EXTDIR)
        set(NAUTILUS_EXTDIR ${CMAKE_INSTALL_LIBDIR}/nautilus/extensions-4)
    endif()
    install(TARGETS kwick-nearby-nautilus DESTINATION ${NAUTILUS_EXTDIR})
endif()
