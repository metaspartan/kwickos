#include <KOverlayIconPlugin>
#include <KUrlNavigator>

#include <QAbstractSpinBox>
#include <QAccessible>
#include <QApplication>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QElapsedTimer>
#include <QFileInfo>
#include <QGraphicsProxyWidget>
#include <QGraphicsScene>
#include <QGraphicsView>
#include <QKeyEvent>
#include <QLineEdit>
#include <QPlainTextEdit>
#include <QPointer>
#include <QTextEdit>
#include <QTimer>
#include <QUrl>

namespace
{
QWidget *ancestor(QWidget *w, const char *className)
{
    for (QWidget *p = w; p; p = p->parentWidget()) {
        if (p->inherits(className)) {
            return p;
        }
    }
    return nullptr;
}

QStringList selectedNames(QWidget *container)
{
    QStringList names;
    QAccessibleInterface *root = QAccessible::queryAccessibleInterface(container);
    if (!root) {
        return names;
    }
    QList<QAccessibleInterface *> candidates{root};
    for (int i = 0; i < root->childCount(); ++i) {
        if (QAccessibleInterface *c = root->child(i)) {
            candidates.append(c);
        }
    }
    for (QAccessibleInterface *iface : candidates) {
        if (QAccessibleSelectionInterface *sel = iface->selectionInterface()) {
            for (QAccessibleInterface *item : sel->selectedItems()) {
                names.append(item->text(QAccessible::Name));
            }
        } else if (QAccessibleTableInterface *table = iface->tableInterface()) {
            for (QAccessibleInterface *cell : table->selectedCells()) {
                names.append(cell->text(QAccessible::Name));
            }
        }
        if (!names.isEmpty()) {
            break;
        }
    }
    names.removeAll(QString());
    names.removeDuplicates();
    return names;
}

QUrl folderOf(QWidget *view)
{
    QWidget *box = ancestor(view, "DolphinViewContainer");
    QList<KUrlNavigator *> navs;
    if (box) {
        navs = box->findChildren<KUrlNavigator *>();
    }
    if (navs.isEmpty()) {
        navs = view->window()->findChildren<KUrlNavigator *>();
    }
    for (KUrlNavigator *nav : std::as_const(navs)) {
        if (nav->isVisible()) {
            return nav->locationUrl();
        }
    }
    return navs.isEmpty() ? QUrl() : navs.constFirst()->locationUrl();
}

class Hook : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.kwickos.QuickLookHost")

public:
    static Hook *instance()
    {
        static Hook *hook = nullptr;
        if (!hook) {
            hook = new Hook(qApp);
        }
        return hook;
    }

public Q_SLOTS:
    bool Step(int direction)
    {
        QWidget *target = m_target.data();
        if (!target) {
            return false;
        }
        const QStringList before = files(target);
        const int key = direction == 2 ? Qt::Key_Up : direction == 3 ? Qt::Key_Down : direction == 4 ? Qt::Key_Left : Qt::Key_Right;
        QKeyEvent press(QEvent::KeyPress, key, Qt::NoModifier);
        QKeyEvent release(QEvent::KeyRelease, key, Qt::NoModifier);
        QApplication::sendEvent(target, &press);
        QApplication::sendEvent(target, &release);
        const QStringList after = files(target);
        if (after.isEmpty() || after == before) {
            return false;
        }
        QTimer::singleShot(0, this, [this, after]() {
            send(QStringLiteral("Show"), after);
        });
        return true;
    }

protected:
    bool eventFilter(QObject *object, QEvent *event) override
    {
        const bool override = event->type() == QEvent::ShortcutOverride;
        if (event->type() != QEvent::KeyPress && !override) {
            return QObject::eventFilter(object, event);
        }
        auto *key = static_cast<QKeyEvent *>(event);
        QWidget *focus = QApplication::focusWidget();
        if (!focus || object != focus) {
            return QObject::eventFilter(object, event);
        }
        if (override) {
            if (key->key() == Qt::Key_Space && !(key->modifiers() & ~Qt::KeypadModifier) && wanted(focus)) {
                event->accept();
                return true;
            }
            return QObject::eventFilter(object, event);
        }
        if (key->key() != Qt::Key_Space) {
            if (!key->text().isEmpty() && key->text().at(0).isPrint() && !(key->modifiers() & (Qt::ControlModifier | Qt::AltModifier | Qt::MetaModifier))) {
                m_typing.start();
            }
            return QObject::eventFilter(object, event);
        }
        if (m_trace) {
            QWidget *c = ancestor(focus, "KItemListContainer");
            qInfo("kwick-quicklook: space on %s view=%d container=%d folder=%s names=%s", focus->metaObject()->className(), ancestor(focus, "DolphinView") != nullptr, c != nullptr,
                  qPrintable(folderOf(focus).toString()), qPrintable(c ? selectedNames(c).join(QLatin1Char('|')) : QString()));
        }
        if (key->modifiers() & ~Qt::KeypadModifier || !wanted(focus)) {
            return QObject::eventFilter(object, event);
        }
        if (key->isAutoRepeat()) {
            return true;
        }
        const QStringList list = files(focus);
        if (list.isEmpty()) {
            return QObject::eventFilter(object, event);
        }
        m_target = focus;
        send(QStringLiteral("Toggle"), list);
        return true;
    }

private:
    bool wanted(QWidget *focus) const
    {
        if (m_typing.isValid() && m_typing.elapsed() < 900) {
            return false;
        }
        if (qobject_cast<QLineEdit *>(focus) || qobject_cast<QTextEdit *>(focus) || qobject_cast<QPlainTextEdit *>(focus) || qobject_cast<QAbstractSpinBox *>(focus)) {
            return false;
        }
        if (!ancestor(focus, "DolphinView") || !ancestor(focus, "KItemListContainer")) {
            return false;
        }
        if (auto *gv = qobject_cast<QGraphicsView *>(focus)) {
            if (gv->scene() && gv->scene()->focusItem() && gv->scene()->focusItem()->type() == QGraphicsProxyWidget::Type) {
                return false;
            }
        }
        return !files(focus).isEmpty();
    }

    explicit Hook(QObject *parent)
        : QObject(parent)
    {
        qApp->installEventFilter(this);
        QDBusConnection::sessionBus().registerObject(QStringLiteral("/org/kwickos/QuickLookHost"), this, QDBusConnection::ExportScriptableSlots | QDBusConnection::ExportNonScriptableSlots);
    }

    QStringList files(QWidget *focus) const
    {
        QWidget *container = ancestor(focus, "KItemListContainer");
        if (!container) {
            return {};
        }
        const QUrl folder = folderOf(focus);
        if (!folder.isLocalFile()) {
            return {};
        }
        QStringList out;
        const QString base = folder.toLocalFile();
        for (const QString &name : selectedNames(container)) {
            const QString path = base + (base.endsWith(QLatin1Char('/')) ? QString() : QStringLiteral("/")) + name;
            if (QFileInfo::exists(path)) {
                out.append(path);
            }
        }
        return out;
    }

    void send(const QString &method, const QStringList &files) const
    {
        QDBusMessage msg = QDBusMessage::createMethodCall(QStringLiteral("org.kwickos.QuickLook"), QStringLiteral("/org/kwickos/QuickLook"), QStringLiteral("org.kwickos.QuickLook"), method);
        msg.setArguments({files, 0, QStringLiteral("dolphin:") + QDBusConnection::sessionBus().baseService()});
        QDBusConnection::sessionBus().asyncCall(msg);
    }

    QPointer<QWidget> m_target;
    bool m_trace = qEnvironmentVariableIsSet("KWICK_QUICKLOOK_TRACE");
    QElapsedTimer m_typing;
};
}

class QuickLookOverlay : public KOverlayIconPlugin
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID "org.kde.overlayicon.kwickquicklook" FILE "dolphinhook.json")

public:
    explicit QuickLookOverlay(QObject *parent = nullptr)
        : KOverlayIconPlugin(parent)
    {
        if (qEnvironmentVariableIsSet("KWICK_QUICKLOOK_TRACE")) {
            qInfo("kwick-quicklook: overlay plugin in %s", qPrintable(QCoreApplication::applicationName()));
        }
        if (QCoreApplication::applicationName() == QLatin1String("dolphin") && qobject_cast<QApplication *>(qApp) && !qEnvironmentVariableIsSet("KWICK_QUICKLOOK_NO_SPACE")) {
            Hook::instance();
        }
    }

    QStringList getOverlays(const QUrl &item) override
    {
        Q_UNUSED(item)
        return {};
    }
};


#include "dolphinhook.moc"
