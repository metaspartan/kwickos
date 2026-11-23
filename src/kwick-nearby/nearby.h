#pragma once

#include "discovery.h"
#include "identity.h"
#include "protocol.h"
#include "sender.h"
#include "server.h"
#include "settings.h"

#include <QColor>
#include <QFileSystemWatcher>
#include <QHash>
#include <QObject>
#include <QPointer>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>

class QNetworkAccessManager;
class QQmlEngine;
class QQuickView;

class Nearby : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool dark READ dark NOTIFY themeChanged)
    Q_PROPERTY(QColor accent READ accent NOTIFY themeChanged)
    Q_PROPERTY(int radius READ radius NOTIFY themeChanged)
    Q_PROPERTY(QString alias READ alias NOTIFY configChanged)
    Q_PROPERTY(QString visibility READ visibility NOTIFY configChanged)
    Q_PROPERTY(QString visibilityText READ visibilityText NOTIFY configChanged)
    Q_PROPERTY(QVariantList devices READ devices NOTIFY devicesChanged)
    Q_PROPERTY(QVariantList items READ items NOTIFY itemsChanged)
    Q_PROPERTY(QString itemsTitle READ itemsTitle NOTIFY itemsChanged)
    Q_PROPERTY(QString itemsSubtitle READ itemsSubtitle NOTIFY itemsChanged)
    Q_PROPERTY(QString draft READ draft WRITE setDraft NOTIFY itemsChanged)
    Q_PROPERTY(bool composing READ composing NOTIFY itemsChanged)
    Q_PROPERTY(bool canSend READ canSend NOTIFY itemsChanged)
    Q_PROPERTY(bool searching READ searching NOTIFY searchingChanged)
    Q_PROPERTY(QString networkProblem READ networkProblem NOTIFY searchingChanged)
    Q_PROPERTY(QVariantMap incoming READ incoming NOTIFY incomingChanged)
    Q_PROPERTY(bool layered READ layered CONSTANT)

public:
    explicit Nearby(QObject *parent = nullptr);
    ~Nearby() override;

    void handle(const QStringList &arguments, const QString &workingDirectory);

    bool dark() const { return m_dark; }
    QColor accent() const { return m_accent; }
    int radius() const { return m_radius; }
    QString alias() const { return m_settings.alias; }
    QString visibility() const;
    QString visibilityText() const;
    QVariantList devices() const;
    QVariantList items() const { return m_itemList; }
    QString itemsTitle() const;
    QString itemsSubtitle() const;
    QString draft() const { return m_draft; }
    void setDraft(const QString &text);
    bool composing() const { return m_composing; }
    bool canSend() const { return !m_paths.isEmpty() || !m_draft.trimmed().isEmpty(); }
    bool searching() const { return m_searching; }
    QString networkProblem() const { return m_networkProblem; }
    QVariantMap incoming() const { return m_incoming; }
    bool layered() const { return m_layered; }

    Q_INVOKABLE void send(const QString &id);
    Q_INVOKABLE void cancelSend(const QString &id);
    Q_INVOKABLE void submitPin(const QString &id, const QString &pin);
    Q_INVOKABLE void chooseFiles();
    Q_INVOKABLE void removeItem(int index);
    Q_INVOKABLE void closeSheet();
    Q_INVOKABLE void setVisibility(const QString &mode);
    Q_INVOKABLE void openSettings();
    Q_INVOKABLE void accept();
    Q_INVOKABLE void decline();
    Q_INVOKABLE void cancelIncoming();
    Q_INVOKABLE void closeIncoming();
    Q_INVOKABLE void openReceived();
    Q_INVOKABLE void revealReceived();
    Q_INVOKABLE void copyMessage();
    Q_INVOKABLE void openMessageLink();
    Q_INVOKABLE void holdIncoming(bool hold);
    Q_INVOKABLE QString formatSize(double bytes) const;
    Q_INVOKABLE QString icon(const QString &name, const QColor &tint) const;

Q_SIGNALS:
    void themeChanged();
    void configChanged();
    void devicesChanged();
    void itemsChanged();
    void searchingChanged();
    void incomingChanged();

private:
    void reloadSettings();
    void refreshTheme();
    void updateNetwork();
    bool wantNetwork() const;
    bool ensureIdentity();
    SelfInfo selfInfo() const;
    QString effectiveVisibility() const;
    bool visibleTo(const QString &fingerprint) const;
    QString uploadRefusal(const QString &certFingerprint) const;
    void addDevice(const Device &device);
    void openSheet(const QStringList &paths, const QString &text, bool compose);
    void setItems(const QStringList &paths);
    void ensureEngine();
    QQuickView *createView(const QString &type);
    void showIncoming();
    void placeIncoming();
    void setIncoming(const QVariantMap &map);
    void patchIncoming(const QVariantMap &changes);
    void scheduleIdle();
    void pruneDevices();
    void onRequest(const QString &sessionId, const Device &sender, const QString &certFingerprint, const QJsonArray &files, qint64 total, bool message);

    Settings m_settings;
    Identity m_identity;
    bool m_identityLoaded = false;
    QNetworkAccessManager *m_nam = nullptr;
    Server *m_server = nullptr;
    Discovery *m_discovery = nullptr;
    QFileSystemWatcher m_watcher;
    QTimer m_reload;
    QTimer m_expiry;
    QTimer m_idle;
    QTimer m_reannounce;
    QTimer m_searchTimer;
    QTimer m_incomingTimer;
    QTimer m_devicesTimer;
    QHash<QString, Device> m_devices;
    QHash<QString, QPointer<Transfer>> m_transfers;
    QStringList m_paths;
    QVariantList m_itemList;
    QString m_draft;
    bool m_composing = false;
    bool m_searching = false;
    QString m_networkProblem;
    QVariantMap m_incoming;
    bool m_incomingHeld = false;
    bool m_daemon = false;
    QString m_desktop;
    bool m_layered = false;
    bool m_dark = true;
    QColor m_accent = QColor(10, 132, 255);
    int m_radius = 10;
    QQmlEngine *m_engine = nullptr;
    QPointer<QQuickView> m_sheet;
    QPointer<QQuickView> m_incomingView;
    bool m_visibleBefore = false;
};
