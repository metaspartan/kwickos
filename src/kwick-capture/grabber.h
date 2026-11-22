#pragma once

#include <QImage>
#include <QObject>
#include <QRect>
#include <QVariantMap>

#include <functional>

struct Shot {
    QImage image;
    QRect geometry;
};

struct Failure {
    QString message;
    QString package;
    bool cancelled = false;
};

class Grabber : public QObject
{
    Q_OBJECT

public:
    using Ok = std::function<void(const Shot &)>;
    using Fail = std::function<void(const Failure &)>;

    Grabber(const QString &desktop, QObject *parent = nullptr);

    void desktop(bool pointer, Ok ok, Fail fail);
    void window(bool pointer, Ok ok, Fail fail);
    bool ownWindowPicker() const;
    QVariantList windows(const QRect &virtualGeometry) const;

    static QRect virtualGeometry();
    static bool hasTool(const QString &name);

private:
    void kwin(const QString &method, const QVariantList &leading, const QVariantMap &options, Ok ok, Fail fail, std::function<void()> fallback);
    void spectacle(const QStringList &arguments, Ok ok, Fail fail);
    void portal(bool interactive, Ok ok, Fail fail);
    void grim(bool pointer, Ok ok, Fail fail);
    void loadFile(const QString &path, bool remove, Ok ok, Fail fail);

    QString m_desktop;
};
