#pragma once

#include <QDBusObjectPath>
#include <QObject>
#include <QVariantMap>

#include <functional>

class PortalRequest : public QObject
{
    Q_OBJECT

public:
    using Done = std::function<void(uint, const QVariantMap &)>;
    PortalRequest(const QString &path, Done done, QObject *parent);

public Q_SLOTS:
    void response(uint code, const QVariantMap &results);

private:
    QString m_path;
    Done m_done;
};

namespace Portal
{
QString service();
QString path();
void call(const QString &interface, const QString &method, const QVariantList &leading, QVariantMap options, PortalRequest::Done done, QObject *parent);
QString sessionToken();
bool hasInterface(const QString &interface);
}
