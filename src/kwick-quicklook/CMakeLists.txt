cmake_minimum_required(VERSION 3.20)
project(kwick-quicklook VERSION 1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

find_package(Qt6 6.6 REQUIRED COMPONENTS Core Gui DBus Qml Quick Svg Widgets)
find_package(KF6Config 6.0 REQUIRED)
find_package(KF6CoreAddons 6.0 REQUIRED)
find_package(KF6KIO 6.0 REQUIRED)
find_package(PkgConfig REQUIRED)
pkg_check_modules(Poppler REQUIRED IMPORTED_TARGET poppler-qt6)
pkg_check_modules(Archive REQUIRED IMPORTED_TARGET libarchive)
include(GNUInstallDirs)

qt_standard_project_setup(REQUIRES 6.6)
qt_policy(SET QTP0001 NEW)

qt_add_executable(kwick-quicklook
    main.cpp
    quicklook.cpp quicklook.h
    previews.cpp previews.h
)

qt_add_qml_module(kwick-quicklook
    URI KwickQuickLook
    VERSION 1.0
    QML_FILES
        qml/Main.qml
        qml/ToolGlyph.qml
        qml/ImagePreview.qml
        qml/PdfPreview.qml
        qml/TextPreview.qml
        qml/MediaPreview.qml
        qml/ListPreview.qml
        qml/FontPreview.qml
        qml/InfoPreview.qml
    RESOURCES
        icons/open.svg icons/share.svg icons/reveal.svg icons/expand.svg icons/play.svg icons/pause.svg
        icons/prev.svg icons/next.svg icons/close.svg icons/nearby.svg
)

target_compile_definitions(kwick-quicklook PRIVATE QT_NO_KEYWORDS)
target_link_libraries(kwick-quicklook PRIVATE
    Qt6::Core Qt6::Gui Qt6::DBus Qt6::Qml Qt6::Quick Qt6::Svg
    KF6::ConfigCore KF6::KIOGui KF6::KIOCore
    PkgConfig::Poppler PkgConfig::Archive)
target_link_options(kwick-quicklook PRIVATE -Wl,--as-needed -Wl,-O1)

add_library(kwick_quicklook_dolphin MODULE dolphinhook.cpp)
target_link_libraries(kwick_quicklook_dolphin PRIVATE Qt6::Widgets Qt6::DBus KF6::KIOCore KF6::KIOWidgets KF6::KIOFileWidgets KF6::CoreAddons)
target_compile_definitions(kwick_quicklook_dolphin PRIVATE QT_NO_KEYWORDS)
set_target_properties(kwick_quicklook_dolphin PROPERTIES PREFIX "")

install(TARGETS kwick-quicklook RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(TARGETS kwick_quicklook_dolphin DESTINATION ${CMAKE_INSTALL_LIBDIR}/qt6/plugins/kf6/overlayicon)
install(FILES kwick-quicklook.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
install(FILES servicemenu/kwick-quicklook.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/kio/servicemenus)
install(FILES dbus/org.kwickos.QuickLook.service dbus/org.gnome.NautilusPreviewer.service DESTINATION ${CMAKE_INSTALL_DATADIR}/dbus-1/services)
install(FILES kwick-quicklook.svg DESTINATION ${CMAKE_INSTALL_DATADIR}/icons/hicolor/scalable/apps)
