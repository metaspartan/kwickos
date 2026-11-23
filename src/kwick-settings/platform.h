#pragma once

#include <KWindowEffects>

#include <QObject>
#include <QWindow>

class Platform : public QObject
{
    Q_OBJECT

public:
    using QObject::QObject;

    Q_INVOKABLE void setBlur(QWindow *window, bool enable) const
    {
        if (window) {
            KWindowEffects::enableBlurBehind(window, enable);
        }
    }
};
