#pragma once

#include <QColor>
#include <QDBusAbstractAdaptor>
#include <QFileInfo>
#include <QMimeDatabase>
#include <QObject>
#include <QPointer>
#include <QSize>
#include <QSizeF>
#include <QStringList>
#include <QUrl>
#include <QVariantList>

class QQuickView;
class QFileSystemWatcher;
class QProcess;

class QuickLook : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool dark READ dark NOTIFY themeChanged)
    Q_PROPERTY(QColor accent READ accent NOTIFY themeChanged)
    Q_PROPERTY(int radius READ radius NOTIFY themeChanged)
    Q_PROPERTY(QString layout READ layout NOTIFY themeChanged)
    Q_PROPERTY(int index READ index NOTIFY currentChanged)
    Q_PROPERTY(int count READ count NOTIFY currentChanged)
    Q_PROPERTY(QString path READ path NOTIFY currentChanged)
    Q_PROPERTY(QString url READ url NOTIFY currentChanged)
    Q_PROPERTY(QString name READ name NOTIFY currentChanged)
    Q_PROPERTY(QString kind READ kind NOTIFY currentChanged)
    Q_PROPERTY(QString mimeName READ mimeName NOTIFY currentChanged)
    Q_PROPERTY(QString iconName READ iconName NOTIFY currentChanged)
    Q_PROPERTY(QString details READ details NOTIFY currentChanged)
    Q_PROPERTY(QString text READ text NOTIFY contentChanged)
    Q_PROPERTY(bool truncated READ truncated NOTIFY contentChanged)
    Q_PROPERTY(QVariantList entries READ entries NOTIFY contentChanged)
    Q_PROPERTY(QString summary READ summary NOTIFY contentChanged)
    Q_PROPERTY(QString pdf READ pdf NOTIFY contentChanged)
    Q_PROPERTY(int pages READ pages NOTIFY contentChanged)
    Q_PROPERTY(QSizeF pageSize READ pageSize NOTIFY contentChanged)
    Q_PROPERTY(QSize imageSize READ imageSize NOTIFY contentChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY contentChanged)
    Q_PROPERTY(QString appName READ appName NOTIFY currentChanged)
    Q_PROPERTY(bool shown READ shown NOTIFY shownChanged)

public:
    explicit QuickLook(QObject *parent = nullptr);
    ~QuickLook() override;

    bool dark() const { return m_dark; }
    QColor accent() const { return m_accent; }
    int radius() const { return m_radius; }
    QString layout() const { return m_layout; }
    int index() const { return m_index; }
    int count() const { return m_files.size(); }
    QString path() const;
    QString url() const;
    QString name() const;
    QString kind() const { return m_kind; }
    QString mimeName() const { return m_mime; }
    QString iconName() const { return m_icon; }
    QString details() const { return m_details; }
    QString text() const { return m_text; }
    bool truncated() const { return m_truncated; }
    QVariantList entries() const { return m_entries; }
    QString summary() const { return m_summary; }
    QString pdf() const { return m_pdf; }
    int pages() const { return m_pages; }
    QSizeF pageSize() const { return m_pageSize; }
    QSize imageSize() const { return m_imageSize; }
    bool busy() const { return m_busy; }
    QString appName() const { return m_appName; }
    bool shown() const;

    void show(const QStringList &files, int index, const QString &host = QString());
    void showUri(const QString &uri, bool closeIfShown);

    Q_INVOKABLE void close();
    Q_INVOKABLE void step(int delta, int direction);
    Q_INVOKABLE void open();
    Q_INVOKABLE void reveal();
    Q_INVOKABLE void share();
    Q_INVOKABLE void toggleFullScreen();
    Q_INVOKABLE void copyPath();
    Q_INVOKABLE void fit(qreal width, qreal height, bool keepAspect);

Q_SIGNALS:
    void themeChanged();
    void currentChanged();
    void contentChanged();
    void shownChanged();
    void selectionEvent(uint direction);
    void visibleChanged(bool visible);

private:
    void createView();
    void refreshTheme();
    void load();
    void siblings();
    void readText(qint64 limit);
    void readArchive();
    void readFolder();
    void readPdf(const QString &file);
    void convertOffice();
    void resetContent();

    QPointer<QQuickView> m_view;
    QFileSystemWatcher *m_watcher = nullptr;
    QMimeDatabase m_db;
    QStringList m_files;
    QString m_host;
    int m_index = -1;
    bool m_expanded = false;
    bool m_dark = true;
    QColor m_accent;
    int m_radius = 10;
    QString m_layout;
    QString m_kind;
    QString m_mime;
    QString m_icon;
    QString m_details;
    QString m_text;
    bool m_truncated = false;
    QVariantList m_entries;
    QString m_summary;
    QString m_pdf;
    int m_pages = 0;
    QSizeF m_pageSize;
    QSize m_imageSize;
    bool m_busy = false;
    QString m_appName;
    QString m_appId;
    int m_serial = 0;
    QPointer<QProcess> m_converter;
};

class NautilusPreviewer : public QDBusAbstractAdaptor
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.gnome.NautilusPreviewer2")
    Q_PROPERTY(bool Visible READ visible)

public:
    explicit NautilusPreviewer(QuickLook *parent);
    bool visible() const;

public Q_SLOTS:
    void ShowFile(const QString &uri, const QString &windowHandle, bool closeIfShown);
    void Close();

Q_SIGNALS:
    void SelectionEvent(uint direction);

private:
    QuickLook *m_ql;
};

class QuickLookService : public QDBusAbstractAdaptor
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.kwickos.QuickLook")

public:
    explicit QuickLookService(QuickLook *parent);

public Q_SLOTS:
    void Show(const QStringList &files, int index, const QString &host);
    void Toggle(const QStringList &files, int index, const QString &host);
    void Close();
    bool IsVisible();

private:
    QuickLook *m_ql;
};
