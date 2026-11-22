#pragma once

#include "grabber.h"

#include <KSharedConfig>

#include <QColor>
#include <QImage>
#include <QObject>
#include <QPointer>
#include <QQuickItem>
#include <QWindow>
#include <QTimer>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>

class QQmlEngine;
class QJSEngine;
class QQuickView;


class QProcess;
class QScreen;
class Recorder;
class MarkupCanvas;

class App : public QObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(Capture)
    QML_SINGLETON
    Q_PROPERTY(bool dark READ dark NOTIFY themeChanged)
    Q_PROPERTY(QColor accent READ accent NOTIFY themeChanged)
    Q_PROPERTY(int radius READ radius NOTIFY themeChanged)
    Q_PROPERTY(bool layered READ layered CONSTANT)
    Q_PROPERTY(QString desktop READ desktop CONSTANT)
    Q_PROPERTY(QString mode READ mode WRITE setMode NOTIFY optionsChanged)
    Q_PROPERTY(QString saveTo READ saveTo WRITE setSaveTo NOTIFY optionsChanged)
    Q_PROPERTY(int timer READ timer WRITE setTimer NOTIFY optionsChanged)
    Q_PROPERTY(bool microphone READ microphone WRITE setMicrophone NOTIFY optionsChanged)
    Q_PROPERTY(bool pointer READ pointer WRITE setPointer NOTIFY optionsChanged)
    Q_PROPERTY(bool recording READ recording NOTIFY recordingChanged)
    Q_PROPERTY(int recordSeconds READ recordSeconds NOTIFY tick)
    Q_PROPERTY(int countdown READ countdown NOTIFY countdownChanged)
    Q_PROPERTY(QString thumbSource READ thumbSource NOTIFY thumbChanged)
    Q_PROPERTY(QString thumbPath READ thumbPath NOTIFY thumbChanged)
    Q_PROPERTY(QSize thumbSize READ thumbSize NOTIFY thumbChanged)
    Q_PROPERTY(bool thumbVideo READ thumbVideo NOTIFY thumbChanged)
    Q_PROPERTY(QString toastTitle READ toastTitle NOTIFY toastChanged)
    Q_PROPERTY(QString toastBody READ toastBody NOTIFY toastChanged)
    Q_PROPERTY(QString toastAction READ toastAction NOTIFY toastChanged)
    Q_PROPERTY(QString toastIcon READ toastIcon NOTIFY toastChanged)
    Q_PROPERTY(qreal toastProgress READ toastProgress NOTIFY toastChanged)
    Q_PROPERTY(QColor picked READ picked NOTIFY pickedChanged)
    Q_PROPERTY(QStringList recent READ recent NOTIFY pickedChanged)

public:
    App(const QString &desktop, QObject *parent);
    ~App() override;

    static App *create(QQmlEngine *engine, QJSEngine *script);

    static App *instance();

    bool dark() const;
    QColor accent() const;
    int radius() const;
    bool layered() const;
    QString desktop() const;
    QString mode() const;
    void setMode(const QString &mode);
    QString saveTo() const;
    void setSaveTo(const QString &saveTo);
    int timer() const;
    void setTimer(int timer);
    bool microphone() const;
    void setMicrophone(bool on);
    bool pointer() const;
    void setPointer(bool on);
    bool recording() const;
    int recordSeconds() const;
    int countdown() const;
    QString thumbSource() const;
    QString thumbPath() const;
    QSize thumbSize() const;
    bool thumbVideo() const;
    QString toastTitle() const;
    QString toastBody() const;
    QString toastAction() const;
    QString toastIcon() const;
    qreal toastProgress() const;
    QColor picked() const;
    QStringList recent() const;

    void handle(const QStringList &arguments, const QString &workingDirectory);
    QImage provide(const QString &id) const;

    Q_INVOKABLE void showBar();
    Q_INVOKABLE void closeBar();
    Q_INVOKABLE void capture();
    Q_INVOKABLE void trigger(const QString &mode);
    Q_INVOKABLE void overlayDone(int screen, qreal x, qreal y, qreal w, qreal h);
    Q_INVOKABLE void overlayPoint(int screen, qreal x, qreal y);
    Q_INVOKABLE void overlayCancel();
    Q_INVOKABLE QColor colorAt(int screen, qreal x, qreal y) const;
    Q_INVOKABLE void thumbOpen();
    Q_INVOKABLE void thumbDismiss();
    Q_INVOKABLE void thumbHold(bool hold);
    Q_INVOKABLE void toastAccept();
    Q_INVOKABLE void toastDismiss();
    Q_INVOKABLE void toastHold(bool hold);
    Q_INVOKABLE void copyString(const QString &text);
    Q_INVOKABLE void pickColor();
    Q_INVOKABLE void choose(const QString &hex);
    Q_INVOKABLE void stopRecording();
    Q_INVOKABLE void cancelCountdown();
    Q_INVOKABLE void setMask(QWindow *window, const QVariantList &rects);
    Q_INVOKABLE void markupCopy(QQuickItem *canvas);
    Q_INVOKABLE void markupSave(QQuickItem *canvas, const QString &path);
    Q_INVOKABLE void markupSaveAs(QQuickItem *canvas, const QString &path);
    Q_INVOKABLE void markupShare(QQuickItem *canvas, const QString &path);
    Q_INVOKABLE void markupClose(QWindow *window);
    Q_INVOKABLE void openFile(const QString &path);

Q_SIGNALS:
    void themeChanged();
    void optionsChanged();
    void recordingChanged();
    void tick();
    void countdownChanged();
    void thumbChanged();
    void toastChanged();
    void pickedChanged();
    void barShown();
    void flashCopied(const QString &what);

private:
    struct Surface {
        QString scope;
        int anchors = 0;
        QMargins margins;
        QSize size;
        bool overlay = true;
        bool keyboard = false;
        bool exclusive = false;
        bool fill = false;
        QScreen *screen = nullptr;
    };

    QQuickView *makeView(const QString &type, const QVariantMap &properties);
    void present(QQuickView *view, const Surface &surface);
    void dismiss(QPointer<QQuickView> &view);
    void refreshTheme();
    void readOptions();
    void writeOption(const char *key, const QVariant &value);
    void run(const QString &mode);
    void withDesktop(std::function<void(const Shot &)> next);
    void showOverlay(const QString &purpose);
    void closeOverlays();
    void releaseFrozen();
    void finishShot(const QImage &image);
    void showThumb();
    void showToast(const QString &title, const QString &body, const QString &icon, const QString &action = QString(), qreal progress = -1, int timeout = 4200);
    void showFailure(const Failure &failure);
    void showColor(const QColor &color);
    void showPill();
    void copyImage(const QByteArray &png, const QImage &image);
    void copyText(const QString &text);
    void recognize(const QImage &image);
    void installOcr();
    void startRecording(bool region, const QRect &area);
    void openMarkup(const QString &path, const QImage &image);
    void saveDialog(const QString &suggested, std::function<void(const QString &)> done);
    void updateIdle();
    QString folder(bool video) const;
    QString stamp(const QString &kind) const;
    QString uniquePath(const QString &directory, const QString &stem, const QString &extension) const;
    QRect pixelRect(const QRectF &global) const;

    static App *s_instance;
    QQmlEngine *m_engine = nullptr;
    KSharedConfig::Ptr m_config;
    Grabber *m_grabber = nullptr;
    Recorder *m_recorder = nullptr;
    QString m_desktop;
    bool m_layered = false;
    bool m_dark = true;
    QColor m_accent;
    int m_radius = 10;
    QString m_mode = QStringLiteral("selection");
    QString m_saveTo = QStringLiteral("desktop");
    int m_timer = 0;
    bool m_microphone = false;
    bool m_pointer = false;
    int m_countdown = 0;
    QString m_pendingMode;
    QTimer m_countdownTimer;
    QTimer m_tickTimer;
    QTimer m_thumbTimer;
    QTimer m_toastTimer;
    QTimer m_idleTimer;
    QPointer<QQuickView> m_bar;
    QPointer<QQuickView> m_thumb;
    QPointer<QQuickView> m_toast;
    QPointer<QQuickView> m_pill;
    QPointer<QQuickView> m_color;
    QList<QPointer<QQuickView>> m_overlays;
    QList<QPointer<QQuickView>> m_markups;
    Shot m_frozen;
    QString m_purpose;
    int m_serial = 0;
    QImage m_last;
    QString m_lastPath;
    bool m_lastVideo = false;
    bool m_lastTemporary = false;
    QString m_toastTitle;
    QString m_toastBody;
    QString m_toastAction;
    QString m_toastIcon;
    qreal m_toastProgress = -1;
    std::function<void()> m_toastCallback;
    QImage m_pendingOcr;
    QPointer<QProcess> m_installer;
    QColor m_picked;
    QStringList m_recent;
    bool m_busy = false;
};
