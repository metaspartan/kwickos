cmake_minimum_required(VERSION 3.20)
project(kwick-capture VERSION 1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

find_package(Qt6 6.6 REQUIRED COMPONENTS Core Gui DBus Qml Quick Svg)
find_package(KF6Config 6.0 REQUIRED)
find_package(KF6DBusAddons 6.0 REQUIRED)
find_package(LayerShellQt REQUIRED)
include(GNUInstallDirs)

qt_standard_project_setup(REQUIRES 6.6)
qt_policy(SET QTP0001 NEW)

qt_add_executable(kwick-capture
    main.cpp
    app.cpp app.h
    grabber.cpp grabber.h
    portal.cpp portal.h
    recorder.cpp recorder.h
    canvas.cpp canvas.h
    images.cpp images.h
)

set(CAPTURE_ICONS
    icons/close.svg icons/screen.svg icons/window.svg icons/selection.svg
    icons/rec-screen.svg icons/rec-selection.svg icons/text.svg icons/color.svg
    icons/chevron.svg icons/check.svg icons/pen.svg icons/highlighter.svg
    icons/line.svg icons/arrow.svg icons/rect.svg icons/ellipse.svg
    icons/type.svg icons/redact.svg icons/crop.svg icons/undo.svg
    icons/redo.svg icons/share.svg icons/copy.svg icons/save.svg
    icons/stop.svg icons/timer.svg icons/mic.svg icons/pointer.svg
    icons/folder.svg icons/markup.svg icons/select.svg
)

qt_add_qml_module(kwick-capture
    URI KwickCapture
    VERSION 1.0
    QML_FILES
        qml/Palette.qml
        qml/Glyph.qml
        qml/ToolButton.qml
        qml/PanelBox.qml
        qml/MenuRow.qml
        qml/Bar.qml
        qml/Overlay.qml
        qml/Thumb.qml
        qml/Toast.qml
        qml/Pill.qml
        qml/ColorPanel.qml
        qml/Markup.qml
    RESOURCES ${CAPTURE_ICONS}
)

target_compile_definitions(kwick-capture PRIVATE QT_NO_KEYWORDS)
target_link_libraries(kwick-capture PRIVATE
    Qt6::Core Qt6::Gui Qt6::DBus Qt6::Qml Qt6::Quick Qt6::Svg
    KF6::ConfigCore KF6::DBusAddons LayerShellQt::Interface)
target_link_options(kwick-capture PRIVATE -Wl,--as-needed -Wl,-O1)

install(TARGETS kwick-capture RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES kwick-capture.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
install(FILES kwick-capture.svg DESTINATION ${CMAKE_INSTALL_DATADIR}/icons/hicolor/scalable/apps)
