#pragma once

#include "grabber.h"

#include <QElapsedTimer>
#include <QObject>
#include <QPointer>
#include <QProcess>
#include <QRect>

class Recorder : public QObject
{
    Q_OBJECT

public:
    struct Request {
        bool region = false;
        QRect area;
        QRect screen;
        qreal scale = 1;
        bool microphone = false;
        bool pointer = false;
        QString folder;
        QString stem;
    };

    Recorder(const QString &desktop, QObject *parent = nullptr);

    void start(const Request &request);
    void stop();
    bool active() const;
    qint64 elapsed() const;
    QString restoreToken() const;
    void setRestoreToken(const QString &token);

Q_SIGNALS:
    void started();
    void finished(const QString &path);
    void failed(const Failure &failure);
    void tokenChanged(const QString &token);

private:
    void startWf(const Request &request);
    void startPortal(const Request &request);
    void startSpectacle(const Request &request);
    void launchGst(const Request &request, int fd, uint node, const QSize &streamSize);
    void watch(QProcess *process, const QString &path);
    void closeSession();
    QString uniquePath(const Request &request, const QString &extension) const;

    QString m_desktop;
    QPointer<QProcess> m_process;
    QString m_session;
    QString m_token;
    QString m_path;
    QElapsedTimer m_clock;
    bool m_stopping = false;
};
