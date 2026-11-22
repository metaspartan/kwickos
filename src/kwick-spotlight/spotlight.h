#pragma once

#include "resultmodel.h"

#include <KPluginMetaData>

#include <QColor>
#include <QElapsedTimer>
#include <QObject>
#include <QPointer>
#include <QSet>

class QAction;
class QFileSystemWatcher;
class QQuickView;

namespace KRunner
{
class RunnerManager;
}

namespace LayerShellQt
{
class Window;
}

class Spotlight : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString query READ query WRITE setQuery NOTIFY queryChanged)
    Q_PROPERTY(QString mode READ mode WRITE setMode NOTIFY modeChanged)
    Q_PROPERTY(QString material READ material NOTIFY materialChanged)
    Q_PROPERTY(int cornerRadius READ cornerRadius NOTIFY cornerRadiusChanged)
    Q_PROPERTY(QColor accent READ accent NOTIFY accentChanged)
    Q_PROPERTY(bool querying READ querying NOTIFY queryingChanged)
    Q_PROPERTY(bool clipboard READ clipboard NOTIFY clipboardChanged)
    Q_PROPERTY(bool shown READ shown NOTIFY shownChanged)
    Q_PROPERTY(QString layout READ layout NOTIFY layoutChanged)
    Q_PROPERTY(bool dark READ dark NOTIFY darkChanged)
    Q_PROPERTY(bool current READ current NOTIFY currentChanged)

public:
    explicit Spotlight(QObject *parent = nullptr);
    ~Spotlight() override;

    QString query() const;
    void setQuery(const QString &query);
    QString mode() const;
    void setMode(const QString &mode);
    QString material() const;
    int cornerRadius() const;
    QColor accent() const;
    bool querying() const;
    bool clipboard() const;
    bool shown() const;
    QString layout() const;
    bool dark() const;
    bool current() const;

    void handle(const QStringList &arguments);

    Q_INVOKABLE void toggle();
    Q_INVOKABLE void show();
    Q_INVOKABLE void hide();
    Q_INVOKABLE void run(int row, bool alternate);
    Q_INVOKABLE bool preview(int row);
    Q_INVOKABLE void setPanel(qreal x, qreal y, qreal width, qreal height, qreal radius);

protected:
    bool eventFilter(QObject *object, QEvent *event) override;

Q_SIGNALS:
    void queryChanged();
    void modeChanged();
    void materialChanged();
    void cornerRadiusChanged();
    void accentChanged();
    void queryingChanged();
    void clipboardChanged();
    void shownChanged();
    void layoutChanged();
    void darkChanged();
    void currentChanged();
    void activated();
    void queryReplaced(const QString &text, int cursor);
    void typed(const QString &text);
    void submitted();

private:
    void createView();
    void launch();
    void relaunch();
    void commit();
    void refreshEnvironment();
    void refreshFiles();
    void watchFiles();
    void applyShortcuts();
    void setMaterial(const QString &material);
    void probeHyprland();
    void queueRunners();
    void loadNextRunner();
    bool ensureRunner(const QString &id);
    void setCurrent(bool current);
    void trace(const char *what, qint64 ms) const;

    KRunner::RunnerManager *m_manager = nullptr;
    ResultModel m_results;
    QPointer<QQuickView> m_view;
    LayerShellQt::Window *m_layer = nullptr;
    QAction *m_action = nullptr;
    QFileSystemWatcher *m_watcher = nullptr;
    QList<KPluginMetaData> m_pendingRunners;
    QSet<QString> m_loaded;
    QString m_desktop;
    QString m_query;
    QString m_mode;
    QString m_layout;
    QString m_material = QStringLiteral("solid");
    QString m_launched;
    int m_cornerRadius = 10;
    QColor m_accent;
    bool m_layered = false;
    bool m_dark = true;
    bool m_current = true;
    bool m_clipboard = false;
    bool m_shown = false;
    bool m_wasActive = false;
    bool m_tracing = false;
    bool m_waitFrame = false;
    bool m_waitResults = false;
    bool m_relaunchQueued = false;
    QElapsedTimer m_openClock;
    QElapsedTimer m_keyClock;
};
