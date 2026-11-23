#include <algorithm>
#include <cmath>

#include <KWindowEffects>
#include <KWindowShadow>

#include <QAbstractItemView>
#include <QAbstractScrollArea>
#include <QAbstractSpinBox>
#include <QApplication>
#include <QCheckBox>
#include <QComboBox>
#include <QDateTime>
#include <QDialog>
#include <QDialogButtonBox>
#include <QEvent>
#include <QGraphicsView>
#include <QGroupBox>
#include <QLabel>
#include <QLineEdit>
#include <QListView>
#include <QMainWindow>
#include <QMenu>
#include <QMenuBar>
#include <QPainter>
#include <QPaintEvent>
#include <QPainterPath>
#include <QPlainTextEdit>
#include <QPlatformSurfaceEvent>
#include <QProgressBar>
#include <QProxyStyle>
#include <QPushButton>
#include <QRadioButton>
#include <QScrollBar>
#include <QSettings>
#include <QSlider>
#include <QStandardPaths>
#include <QStyleFactory>
#include <QStyleOptionMenuItem>
#include <QStylePlugin>
#include <QStyledItemDelegate>
#include <QTabBar>
#include <QTabWidget>
#include <QTextEdit>
#include <QTimer>
#include <QVariantAnimation>
#include <QWindow>

namespace
{

struct Look {
    bool fluent;
    int itemHeight;
    int separatorHeight;
    int headerHeight;
    int inset;
    int itemVInset;
    int panelRadius;
    int radius;
    int vMargin;
    int leftPad;
    int rightPad;
    int iconSize;
    int iconGap;
    int shortcutGap;
    int arrowWidth;
    int minWidth;
    int shadowBlur;
    int shadowOffset;
    int shadowAlpha;
    int shadowRimAlpha;
    qreal panelAlpha;
    int submenuDelay;

    constexpr int shadowMargin() const
    {
        return shadowBlur + shadowOffset;
    }
};

constexpr Look MacLook{false, 24, 11, 24, 5, 0, 12, 7, 5, 14, 14, 16, 7, 28, 16, 160, 22, 8, 165, 90, 0.78, 150};
constexpr Look FluentLook{true, 32, 9, 28, 4, 2, 8, 4, 2, 12, 12, 16, 12, 32, 20, 200, 18, 8, 110, 0, 0.92, 300};

QString labelOf(const QString &text)
{
    const int tab = text.indexOf(QLatin1Char('\t'));
    QString label = tab >= 0 ? text.left(tab) : text;
    QString out;
    out.reserve(label.size());
    for (int i = 0; i < label.size(); ++i) {
        if (label.at(i) == QLatin1Char('&') && i + 1 < label.size()) {
            ++i;
        }
        out.append(label.at(i));
    }
    return out;
}

QString glyphKey(const QString &key, const QFontMetrics &fm)
{
    static const QHash<QString, QString> keys{
        {QStringLiteral("Return"), QStringLiteral("↩")},    {QStringLiteral("Enter"), QStringLiteral("⌤")},
        {QStringLiteral("Backspace"), QStringLiteral("⌫")}, {QStringLiteral("Esc"), QStringLiteral("⎋")},
        {QStringLiteral("Escape"), QStringLiteral("⎋")},    {QStringLiteral("Tab"), QStringLiteral("⇥")},
        {QStringLiteral("Backtab"), QStringLiteral("⇤")},   {QStringLiteral("Left"), QStringLiteral("←")},
        {QStringLiteral("Right"), QStringLiteral("→")},     {QStringLiteral("Up"), QStringLiteral("↑")},
        {QStringLiteral("Down"), QStringLiteral("↓")},      {QStringLiteral("PgUp"), QStringLiteral("⇞")},
        {QStringLiteral("PgDown"), QStringLiteral("⇟")},    {QStringLiteral("Home"), QStringLiteral("↖")},
        {QStringLiteral("End"), QStringLiteral("↘")},
    };
    const QString glyph = keys.value(key);
    if (!glyph.isEmpty() && fm.inFontUcs4(glyph.at(0).unicode())) {
        return glyph;
    }
    return key.size() == 1 ? key.toUpper() : key;
}

QString shortcutOf(const QString &text, const QFont &font)
{
    const int tab = text.indexOf(QLatin1Char('\t'));
    if (tab < 0) {
        return QString();
    }
    const QString raw = text.mid(tab + 1).section(QStringLiteral("; "), 0, 0).trimmed();
    QStringList parts = raw.split(QLatin1Char('+'));
    if (raw.endsWith(QLatin1String("++"))) {
        parts.removeLast();
        parts.last() = QStringLiteral("+");
    }
    if (parts.size() < 2 && parts.value(0).size() > 1 && !parts.value(0).startsWith(QLatin1Char('F'))) {
        return raw;
    }
    static const QList<QPair<QString, QString>> order{
        {QStringLiteral("Ctrl"), QStringLiteral("⌃")},
        {QStringLiteral("Alt"), QStringLiteral("⌥")},
        {QStringLiteral("Shift"), QStringLiteral("⇧")},
        {QStringLiteral("Meta"), QStringLiteral("⌘")},
    };
    const QString key = parts.takeLast();
    QString out;
    for (const auto &mod : order) {
        if (parts.contains(mod.first)) {
            out += mod.second;
            parts.removeAll(mod.first);
        }
    }
    if (!parts.isEmpty()) {
        return raw;
    }
    return out + glyphKey(key, QFontMetrics(font));
}

bool menuShowsIcons(const QWidget *widget)
{
    const auto menu = qobject_cast<const QMenu *>(widget);
    if (!menu) {
        return false;
    }
    int items = 0;
    const auto actions = menu->actions();
    for (const QAction *action : actions) {
        if (!action->isVisible() || action->isSeparator()) {
            continue;
        }
        if (action->icon().isNull() || !action->isIconVisibleInMenu()) {
            return false;
        }
        ++items;
    }
    return items > 1;
}

bool menuHasIcon(const QWidget *widget)
{
    const auto menu = qobject_cast<const QMenu *>(widget);
    if (!menu) {
        return false;
    }
    const auto actions = menu->actions();
    for (const QAction *action : actions) {
        if (action->isVisible() && !action->isSeparator() && !action->icon().isNull() && action->isIconVisibleInMenu()) {
            return true;
        }
    }
    return false;
}

bool hasLeadColumn(const Look &look, const QStyleOptionMenuItem *item, const QWidget *widget)
{
    if (look.fluent) {
        return item->menuHasCheckableItems || menuHasIcon(widget);
    }
    return item->menuHasCheckableItems || menuShowsIcons(widget);
}

bool drawsIcon(const Look &look, const QWidget *widget)
{
    return look.fluent ? menuHasIcon(widget) : menuShowsIcons(widget);
}

QString rawShortcutOf(const QString &text)
{
    const int tab = text.indexOf(QLatin1Char('\t'));
    if (tab < 0) {
        return QString();
    }
    QStringList parts = text.mid(tab + 1).section(QStringLiteral("; "), 0, 0).trimmed().split(QLatin1Char('+'));
    static const QHash<QString, QString> names{
        {QStringLiteral("Return"), QStringLiteral("Enter")},
        {QStringLiteral("PgDown"), QStringLiteral("PgDn")},
        {QStringLiteral("Meta"), QStringLiteral("Win")},
    };
    for (QString &part : parts) {
        part = names.value(part, part);
    }
    return parts.join(QLatin1Char('+'));
}

QString shortcutFor(const Look &look, const QString &text, const QFont &font)
{
    return look.fluent ? rawShortcutOf(text) : shortcutOf(text, font);
}

QColor accentColor()
{
    const QString path = QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) + QStringLiteral("/kdeglobals");
    QSettings settings(path, QSettings::IniFormat);
    const QStringList parts = settings.value(QStringLiteral("AccentColor")).toStringList();
    if (parts.size() >= 3) {
        const QColor color(parts.at(0).trimmed().toInt(), parts.at(1).trimmed().toInt(), parts.at(2).trimmed().toInt());
        if (color.isValid()) {
            return color;
        }
    }
    return QColor(255, 159, 10);
}

QPainterPath panelPath(const QRectF &rect, int radius)
{
    QPainterPath path;
    path.addRoundedRect(rect, radius, radius);
    return path;
}

QImage blurredAlpha(QImage image, int radius)
{
    const int w = image.width();
    const int h = image.height();
    QList<int> line(std::max(w, h));
    for (int pass = 0; pass < 3; ++pass) {
        for (int y = 0; y < h; ++y) {
            auto row = reinterpret_cast<QRgb *>(image.scanLine(y));
            for (int x = 0; x < w; ++x) {
                line[x] = qAlpha(row[x]);
            }
            int sum = 0;
            for (int x = -radius; x <= radius; ++x) {
                sum += line[std::clamp(x, 0, w - 1)];
            }
            for (int x = 0; x < w; ++x) {
                row[x] = qRgba(0, 0, 0, sum / (2 * radius + 1));
                sum += line[std::min(x + radius + 1, w - 1)] - line[std::max(x - radius, 0)];
            }
        }
        for (int x = 0; x < w; ++x) {
            for (int y = 0; y < h; ++y) {
                line[y] = qAlpha(reinterpret_cast<const QRgb *>(image.constScanLine(y))[x]);
            }
            int sum = 0;
            for (int y = -radius; y <= radius; ++y) {
                sum += line[std::clamp(y, 0, h - 1)];
            }
            for (int y = 0; y < h; ++y) {
                reinterpret_cast<QRgb *>(image.scanLine(y))[x] = qRgba(0, 0, 0, sum / (2 * radius + 1));
                sum += line[std::min(y + radius + 1, h - 1)] - line[std::max(y - radius, 0)];
            }
        }
    }
    return image;
}

QList<KWindowShadowTile::Ptr> shadowTiles(const Look &look, qreal dpr)
{
    static QHash<int, QList<KWindowShadowTile::Ptr>> cache;
    const int key = qRound(dpr * 100) * 2 + (look.fluent ? 1 : 0);
    if (cache.contains(key)) {
        return cache.value(key);
    }
    const int PanelRadius = look.panelRadius;
    const int ShadowMargin = look.shadowMargin();
    const int ShadowBlur = look.shadowBlur;
    const int ShadowOffset = look.shadowOffset;
    const int core = 2 * PanelRadius + 1;
    const int side = 2 * ShadowMargin + core;
    const int px = qCeil(side * dpr);
    QImage image(px, px, QImage::Format_ARGB32_Premultiplied);
    image.fill(Qt::transparent);
    {
        QPainter p(&image);
        p.setRenderHint(QPainter::Antialiasing);
        p.scale(dpr, dpr);
        p.setPen(Qt::NoPen);
        p.setBrush(QColor(0, 0, 0, look.shadowAlpha));
        p.drawPath(panelPath(QRectF(ShadowMargin, ShadowMargin + ShadowOffset, core, core).adjusted(2, 2, -2, -2), PanelRadius));
    }
    image = blurredAlpha(image, qMax(1, qRound(ShadowBlur * dpr / 3.0)));
    {
        QPainter p(&image);
        p.setRenderHint(QPainter::Antialiasing);
        p.scale(dpr, dpr);
        if (look.shadowRimAlpha > 0) {
            p.setPen(QPen(QColor(0, 0, 0, look.shadowRimAlpha), 1.0));
            p.setBrush(Qt::NoBrush);
            p.drawPath(panelPath(QRectF(ShadowMargin, ShadowMargin, core, core).adjusted(-0.5, -0.5, 0.5, 0.5), PanelRadius));
        }
        p.setCompositionMode(QPainter::CompositionMode_DestinationOut);
        p.setPen(Qt::NoPen);
        p.setBrush(Qt::black);
        p.drawPath(panelPath(QRectF(ShadowMargin, ShadowMargin, core, core), PanelRadius));
    }
    image.setDevicePixelRatio(dpr);
    const int a = ShadowMargin + PanelRadius;
    const QList<QRect> parts{
        QRect(0, 0, a, a),         QRect(a, 0, 1, a),         QRect(a + 1, 0, a, a),         QRect(a + 1, a, a, 1),
        QRect(a + 1, a + 1, a, a), QRect(a, a + 1, 1, a),     QRect(0, a + 1, a, a),         QRect(0, a, a, 1),
    };
    QList<KWindowShadowTile::Ptr> tiles;
    for (const QRect &part : parts) {
        const QRect src(qRound(part.x() * dpr), qRound(part.y() * dpr), qRound(part.width() * dpr), qRound(part.height() * dpr));
        QImage tileImage = image.copy(src);
        tileImage.setDevicePixelRatio(dpr);
        auto tile = KWindowShadowTile::Ptr::create();
        tile->setImage(tileImage);
        tiles.append(tile);
    }
    cache.insert(key, tiles);
    return tiles;
}

QString kwickSetting(const QString &key, const QString &fallback)
{
    const QString path = QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) + QStringLiteral("/kdeglobals");
    QSettings settings(path, QSettings::IniFormat);
    return settings.value(QStringLiteral("KwickOS/") + key, fallback).toString();
}

bool isSidebarView(const QWidget *widget)
{
    return widget && widget->inherits("KFilePlacesView");
}

QColor sidebarSelectionColor(const QPalette &palette)
{
    const bool dark = palette.color(QPalette::Window).lightness() < 128;
    QColor color = dark ? QColor(255, 255, 255) : QColor(0, 0, 0);
    color.setAlphaF(dark ? 0.1 : 0.08);
    return color;
}

class SidebarDecorator : public QObject
{
public:
    SidebarDecorator(const Look &look, QObject *parent)
        : QObject(parent)
        , m_look(look)
    {
    }

    bool neutral() const
    {
        return kwickSetting(QStringLiteral("SidebarSelection"), m_look.fluent ? QStringLiteral("highlight") : QStringLiteral("neutral")) == QLatin1String("neutral");
    }

    void apply(QWidget *view) const
    {
        QPalette palette = view->palette();
        const QPalette base = QApplication::palette(view);
        const bool clear = view->window()->testAttribute(Qt::WA_TranslucentBackground) && view->window()->property("_kwick_tint").toBool();
        for (const auto group : {QPalette::Active, QPalette::Inactive, QPalette::Disabled}) {
            palette.setColor(group, QPalette::Base, clear ? QColor(Qt::transparent) : base.color(group, QPalette::Base));
        }
        if (auto area = qobject_cast<QAbstractScrollArea *>(view)) {
            area->viewport()->setAutoFillBackground(!clear);
        }
        if (neutral()) {
            for (const auto group : {QPalette::Active, QPalette::Inactive}) {
                palette.setColor(group, QPalette::Highlight, sidebarSelectionColor(base));
                palette.setColor(group, QPalette::HighlightedText, base.color(group, QPalette::Text));
            }
        } else {
            for (const auto group : {QPalette::Active, QPalette::Inactive}) {
                palette.setColor(group, QPalette::Highlight, base.color(group, QPalette::Highlight));
                palette.setColor(group, QPalette::HighlightedText, base.color(group, QPalette::HighlightedText));
            }
        }
        view->setPalette(palette);
    }

    bool eventFilter(QObject *object, QEvent *event) override
    {
        if (event->type() == QEvent::ApplicationPaletteChange) {
            if (auto view = qobject_cast<QWidget *>(object)) {
                apply(view);
            }
        }
        return false;
    }

private:
    Look m_look;
};

class TintDecorator : public QObject
{
public:
    using QObject::QObject;

    static bool wanted(const QWidget *widget)
    {
        if (!widget->isWindow() || !qobject_cast<const QMainWindow *>(widget) || widget->isVisible()) {
            return false;
        }
        if (kwickSetting(QStringLiteral("WallpaperTint"), QStringLiteral("false")) != QLatin1String("true")) {
            return false;
        }
        const QStringList apps = kwickSetting(QStringLiteral("TintApps"), QStringLiteral("dolphin")).split(QLatin1Char(','), Qt::SkipEmptyParts);
        return apps.contains(QCoreApplication::applicationName());
    }

    static QColor tint(const QPalette &palette)
    {
        QColor color = palette.color(QPalette::Active, QPalette::Window);
        color.setAlphaF(color.lightness() < 128 ? 0.82 : 0.84);
        return color;
    }

    void install(QWidget *window)
    {
        const bool created = window->testAttribute(Qt::WA_WState_Created);
        window->setAttribute(Qt::WA_TranslucentBackground);
        if (created) {
            window->setWindowFlags(window->windowFlags());
        }
        window->setAttribute(Qt::WA_NoSystemBackground, false);
        window->setProperty("_kwick_tint", true);
        window->removeEventFilter(this);
        window->installEventFilter(this);
    }

    bool eventFilter(QObject *object, QEvent *event) override
    {
        auto window = qobject_cast<QWidget *>(object);
        if (!window) {
            return false;
        }
        switch (event->type()) {
        case QEvent::Paint: {
            QPainter painter(window);
            painter.setCompositionMode(QPainter::CompositionMode_Source);
            painter.fillRect(static_cast<QPaintEvent *>(event)->rect(), tint(window->palette()));
            break;
        }
        case QEvent::Show:
        case QEvent::Resize:
            if (window->windowHandle()) {
                KWindowEffects::enableBlurBehind(window->windowHandle(), true);
            }
            break;
        default:
            break;
        }
        return false;
    }
};

class MenuDecorator : public QObject
{
public:
    MenuDecorator(const Look &look, QObject *parent)
        : QObject(parent)
        , m_look(look)
    {
    }

    bool eventFilter(QObject *object, QEvent *event) override
    {
        if (!object->isWidgetType()) {
            return false;
        }
        auto menu = static_cast<QWidget *>(object);
        switch (event->type()) {
        case QEvent::PlatformSurface:
            if (static_cast<QPlatformSurfaceEvent *>(event)->surfaceEventType() == QPlatformSurfaceEvent::SurfaceCreated) {
                install(m_look, menu);
            }
            break;
        case QEvent::Show:
        case QEvent::Resize: {
            updateBlur(m_look, menu);
            const Look look = m_look;
            QTimer::singleShot(0, menu, [look, menu] {
                updateBlur(look, menu);
            });
            break;
        }
        default:
            break;
        }
        return false;
    }

    static void install(const Look &look, QWidget *menu)
    {
        QWindow *window = menu->windowHandle();
        if (!window) {
            return;
        }
        auto shadow = window->findChild<KWindowShadow *>(QString(), Qt::FindDirectChildrenOnly);
        if (!shadow) {
            shadow = new KWindowShadow(window);
        }
        shadow->destroy();
        const auto tiles = shadowTiles(look, window->devicePixelRatio());
        const int ShadowMargin = look.shadowMargin();
        shadow->setTopLeftTile(tiles.at(0));
        shadow->setTopTile(tiles.at(1));
        shadow->setTopRightTile(tiles.at(2));
        shadow->setRightTile(tiles.at(3));
        shadow->setBottomRightTile(tiles.at(4));
        shadow->setBottomTile(tiles.at(5));
        shadow->setBottomLeftTile(tiles.at(6));
        shadow->setLeftTile(tiles.at(7));
        shadow->setPadding(QMargins(ShadowMargin, ShadowMargin, ShadowMargin, ShadowMargin));
        shadow->setWindow(window);
        shadow->create();
        updateBlur(look, menu);
    }

    static void updateBlur(const Look &look, QWidget *menu)
    {
        QWindow *window = menu->windowHandle();
        if (!window || !blurAvailable()) {
            return;
        }
        const QRegion region(panelPath(QRectF(menu->rect()), look.panelRadius).toFillPolygon().toPolygon());
        KWindowEffects::enableBlurBehind(window, true, region);
    }

    static bool blurAvailable()
    {
        return KWindowEffects::isEffectAvailable(KWindowEffects::BlurBehind);
    }

private:
    Look m_look;
};

constexpr int Ring = 3;
constexpr int ControlHeight = 22;
constexpr int SwitchWidth = 32;
constexpr int SwitchHeight = 18;
constexpr int CheckSize = 14;
constexpr int RadioSize = 16;
constexpr int ArrowBox = 16;
constexpr int StepperWidth = 13;
constexpr int TabHeight = 24;
constexpr int KnobSize = 20;

QColor withAlpha(QColor color, qreal alpha)
{
    color.setAlphaF(alpha);
    return color;
}

QColor blend(const QColor &a, const QColor &b, qreal t)
{
    return QColor::fromRgbF(a.redF() + (b.redF() - a.redF()) * t, a.greenF() + (b.greenF() - a.greenF()) * t, a.blueF() + (b.blueF() - a.blueF()) * t,
                            a.alphaF() + (b.alphaF() - a.alphaF()) * t);
}

bool darkPalette(const QPalette &palette)
{
    return palette.color(QPalette::Window).lightnessF() < 0.5;
}

QColor unemphasized(const QPalette &palette)
{
    return darkPalette(palette) ? QColor(70, 70, 70) : QColor(220, 220, 220);
}

QColor textSelection(const QPalette &palette, const QColor &accent)
{
    return blend(palette.color(QPalette::Active, QPalette::Base), accent, darkPalette(palette) ? 0.45 : 0.32);
}

struct Ink {
    bool dark;
    QColor text;
    QColor bezel;
    QColor bezelPressed;
    QColor bezelStroke;
    QColor shadow;
    QColor field;
    QColor fieldStroke;
    QColor box;
    QColor boxStroke;
    QColor track;
    QColor knob;
    QColor knobStroke;
    QColor card;
    QColor cardStroke;
    QColor segmentTrack;
    QColor segment;
};

Ink inkOf(const QPalette &palette)
{
    Ink k;
    k.dark = darkPalette(palette);
    k.text = palette.color(QPalette::Active, QPalette::WindowText);
    if (k.dark) {
        k.bezel = QColor(255, 255, 255, 56);
        k.bezelPressed = QColor(255, 255, 255, 84);
        k.bezelStroke = QColor(255, 255, 255, 18);
        k.shadow = QColor(0, 0, 0, 70);
        k.field = QColor(255, 255, 255, 13);
        k.fieldStroke = QColor(255, 255, 255, 36);
        k.box = QColor(255, 255, 255, 26);
        k.boxStroke = QColor(255, 255, 255, 46);
        k.track = QColor(255, 255, 255, 40);
        k.knob = QColor(222, 222, 222);
        k.knobStroke = QColor(0, 0, 0, 60);
        k.card = QColor(255, 255, 255, 10);
        k.cardStroke = QColor(255, 255, 255, 22);
        k.segmentTrack = QColor(255, 255, 255, 20);
        k.segment = QColor(255, 255, 255, 62);
    } else {
        k.bezel = QColor(255, 255, 255);
        k.bezelPressed = QColor(232, 232, 232);
        k.bezelStroke = QColor(0, 0, 0, 34);
        k.shadow = QColor(0, 0, 0, 22);
        k.field = QColor(255, 255, 255);
        k.fieldStroke = QColor(0, 0, 0, 44);
        k.box = QColor(255, 255, 255);
        k.boxStroke = QColor(0, 0, 0, 66);
        k.track = QColor(0, 0, 0, 26);
        k.knob = QColor(255, 255, 255);
        k.knobStroke = QColor(0, 0, 0, 30);
        k.card = QColor(0, 0, 0, 8);
        k.cardStroke = QColor(0, 0, 0, 18);
        k.segmentTrack = QColor(0, 0, 0, 15);
        k.segment = QColor(255, 255, 255);
    }
    return k;
}

bool insideItemView(const QWidget *widget)
{
    for (const QWidget *p = widget ? widget->parentWidget() : nullptr; p; p = p->parentWidget()) {
        if (qobject_cast<const QAbstractItemView *>(p)) {
            return true;
        }
        if (p->isWindow()) {
            break;
        }
    }
    return false;
}

bool isSwitch(const QWidget *widget)
{
    const auto box = qobject_cast<const QCheckBox *>(widget);
    return box && !box->isTristate() && !box->property("_kwick_checkbox").toBool() && !insideItemView(box);
}

bool isPageList(const QWidget *widget)
{
    return widget && widget->inherits("KDEPrivate::KPageListView");
}

QPainterPath roundedPath(const QRectF &rect, qreal radius)
{
    QPainterPath path;
    path.addRoundedRect(rect, radius, radius);
    return path;
}

void drawRing(QPainter *painter, const QRectF &rect, qreal radius, const QColor &accent)
{
    painter->save();
    painter->setRenderHint(QPainter::Antialiasing, true);
    painter->setBrush(Qt::NoBrush);
    painter->setPen(QPen(withAlpha(accent, 0.5), Ring));
    painter->drawPath(roundedPath(rect.adjusted(-1.5, -1.5, 1.5, 1.5), radius + 1.5));
    painter->restore();
}

void drawChevron(QPainter *painter, const QPointF &center, qreal size, bool up, const QColor &color, qreal width)
{
    painter->save();
    painter->setRenderHint(QPainter::Antialiasing, true);
    painter->setPen(QPen(color, width, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin));
    painter->setBrush(Qt::NoBrush);
    const qreal h = size / 2.0;
    const qreal d = up ? -h / 2.0 : h / 2.0;
    QPainterPath path;
    path.moveTo(center.x() - h, center.y() - d);
    path.lineTo(center.x(), center.y() + d);
    path.lineTo(center.x() + h, center.y() - d);
    painter->drawPath(path);
    painter->restore();
}

class TextTint : public QObject
{
public:
    TextTint(const QColor &accent, QObject *parent)
        : QObject(parent)
        , m_accent(accent)
    {
    }

    void apply(QWidget *widget) const
    {
        const QPalette app = QApplication::palette(widget);
        QPalette pal = widget->palette();
        pal.setColor(QPalette::Active, QPalette::Highlight, textSelection(app, m_accent));
        pal.setColor(QPalette::Active, QPalette::HighlightedText, app.color(QPalette::Active, QPalette::Text));
        pal.setColor(QPalette::Inactive, QPalette::Highlight, unemphasized(app));
        pal.setColor(QPalette::Inactive, QPalette::HighlightedText, app.color(QPalette::Inactive, QPalette::Text));
        widget->setPalette(pal);
    }

    bool eventFilter(QObject *object, QEvent *event) override
    {
        if (event->type() == QEvent::ApplicationPaletteChange && object->isWidgetType()) {
            apply(static_cast<QWidget *>(object));
        }
        return false;
    }

private:
    QColor m_accent;
};

class PageDelegate : public QStyledItemDelegate
{
public:
    static constexpr int RowHeight = 28;
    static constexpr int IconSize = 20;
    static constexpr int Inset = 8;
    static constexpr int Pad = 8;
    static constexpr int Gap = 8;

    explicit PageDelegate(QObject *parent)
        : QStyledItemDelegate(parent)
    {
    }

    QSize sizeHint(const QStyleOptionViewItem &option, const QModelIndex &index) const override
    {
        const QFontMetrics fm(option.font);
        const int text = fm.horizontalAdvance(index.data(Qt::DisplayRole).toString());
        return QSize(2 * Inset + 2 * Pad + IconSize + Gap + text + 6, RowHeight);
    }

    void paint(QPainter *painter, const QStyleOptionViewItem &option, const QModelIndex &index) const override
    {
        painter->save();
        painter->setRenderHint(QPainter::Antialiasing, true);
        const QRectF row = QRectF(option.rect).adjusted(Inset, 1, -Inset, -1);
        const bool selected = option.state & QStyle::State_Selected;
        const bool active = option.state & QStyle::State_Active;
        const bool emphasized = selected && active;
        if (selected) {
            painter->setPen(Qt::NoPen);
            painter->setBrush(emphasized ? option.palette.color(QPalette::Active, QPalette::Highlight) : unemphasized(option.palette));
            painter->drawRoundedRect(row, 6, 6);
        } else if ((option.state & QStyle::State_MouseOver) && (option.state & QStyle::State_Enabled)) {
            painter->setPen(Qt::NoPen);
            painter->setBrush(withAlpha(option.palette.color(QPalette::Text), 0.06));
            painter->drawRoundedRect(row, 6, 6);
        }
        const int x = qRound(row.left()) + Pad;
        const int cy = option.rect.top() + option.rect.height() / 2;
        const QIcon icon = index.data(Qt::DecorationRole).value<QIcon>();
        const QIcon::Mode mode = (option.state & QStyle::State_Enabled) ? QIcon::Normal : QIcon::Disabled;
        icon.paint(painter, QRect(x, cy - IconSize / 2, IconSize, IconSize), Qt::AlignCenter, mode, QIcon::Off);
        const int tx = x + IconSize + Gap;
        const QRect textRect(tx, option.rect.top(), qRound(row.right()) - Pad - tx, option.rect.height());
        QColor fg = emphasized ? option.palette.color(QPalette::Active, QPalette::HighlightedText) : option.palette.color(QPalette::Active, QPalette::Text);
        if (!(option.state & QStyle::State_Enabled)) {
            fg = option.palette.color(QPalette::Disabled, QPalette::Text);
        }
        painter->setFont(option.font);
        painter->setPen(fg);
        const QString text = option.fontMetrics.elidedText(index.data(Qt::DisplayRole).toString(), Qt::ElideRight, textRect.width());
        painter->drawText(textRect, Qt::AlignLeft | Qt::AlignVCenter | Qt::TextSingleLine, text);
        painter->restore();
    }
};

class KwickMacStyle : public QProxyStyle
{
public:
    explicit KwickMacStyle(const Look &look)
        : QProxyStyle(QStyleFactory::create(QStringLiteral("Breeze")))
        , m_look(look)
        , m_accent(accentColor())
        , m_decorator(new MenuDecorator(look, this))
        , m_textTint(new TextTint(m_accent, this))
        , m_sidebar(new SidebarDecorator(look, this))
        , m_tint(new TintDecorator(this))
    {
    }

    void polish(QWidget *widget) override
    {
        if (TintDecorator::wanted(widget)) {
            m_tint->install(widget);
        }
        if (isSidebarView(widget)) {
            widget->removeEventFilter(m_sidebar);
            widget->installEventFilter(m_sidebar);
            m_sidebar->apply(widget);
        }
        if (auto menu = qobject_cast<QMenu *>(widget)) {
            menu->setAttribute(Qt::WA_TranslucentBackground);
            menu->removeEventFilter(m_decorator);
            menu->installEventFilter(m_decorator);
            if (menu->testAttribute(Qt::WA_WState_Created)) {
                MenuDecorator::install(m_look, menu);
            }
            return;
        }
        if (!m_look.fluent && widget && widget->inherits("QComboBoxPrivateContainer")) {
            widget->setAttribute(Qt::WA_TranslucentBackground);
            widget->removeEventFilter(m_decorator);
            widget->installEventFilter(m_decorator);
            if (widget->testAttribute(Qt::WA_WState_Created)) {
                MenuDecorator::install(m_look, widget);
            }
            return;
        }
        QProxyStyle::polish(widget);
        if (m_look.fluent || !widget) {
            return;
        }
        if (qobject_cast<QLineEdit *>(widget) || qobject_cast<QTextEdit *>(widget) || qobject_cast<QPlainTextEdit *>(widget)) {
            m_textTint->apply(widget);
            widget->removeEventFilter(m_textTint);
            widget->installEventFilter(m_textTint);
        }
        if (auto box = qobject_cast<QCheckBox *>(widget); box && isSwitch(box) && !box->property("_kwick_switch").toBool()) {
            box->setProperty("_kwick_switch", true);
            box->setAttribute(Qt::WA_Hover);
            connect(box, &QCheckBox::toggled, this, [box](bool on) {
                auto anim = box->findChild<QVariantAnimation *>(QStringLiteral("_kwick_knob"), Qt::FindDirectChildrenOnly);
                if (!anim) {
                    anim = new QVariantAnimation(box);
                    anim->setObjectName(QStringLiteral("_kwick_knob"));
                    anim->setDuration(160);
                    anim->setEasingCurve(QEasingCurve::OutCubic);
                    connect(anim, &QVariantAnimation::valueChanged, box, [box] {
                        box->update();
                    });
                }
                const qreal from = anim->state() == QAbstractAnimation::Running ? anim->currentValue().toReal() : (on ? 0.0 : 1.0);
                anim->stop();
                anim->setStartValue(from);
                anim->setEndValue(on ? 1.0 : 0.0);
                if (box->isVisible()) {
                    anim->start();
                } else {
                    anim->setCurrentTime(anim->duration());
                }
            });
        }
        if (qobject_cast<QAbstractButton *>(widget) || qobject_cast<QComboBox *>(widget) || qobject_cast<QAbstractSpinBox *>(widget)
            || qobject_cast<QSlider *>(widget) || qobject_cast<QTabBar *>(widget)) {
            widget->setAttribute(Qt::WA_Hover);
        }
        if (auto bar = qobject_cast<QTabBar *>(widget); bar && bar->documentMode() && segmentedTab(nullptr, bar)) {
            bar->setExpanding(false);
            bar->setDrawBase(false);
        }
        if (isPageList(widget)) {
            auto view = static_cast<QListView *>(widget);
            if (!dynamic_cast<PageDelegate *>(view->itemDelegate())) {
                auto old = view->itemDelegate();
                view->setItemDelegate(new PageDelegate(view));
                if (old && old->parent() == view) {
                    old->deleteLater();
                }
            }
            view->setFrameShape(QFrame::NoFrame);
            view->setSpacing(0);
            view->setIconSize(QSize(PageDelegate::IconSize, PageDelegate::IconSize));
            view->setProperty("_breeze_borders_sides", QVariant());
            QPalette pal = view->palette();
            const QPalette app = QApplication::palette(view);
            pal.setColor(QPalette::Base, blend(app.color(QPalette::Window), app.color(QPalette::WindowText), darkPalette(app) ? 0.035 : 0.025));
            view->setPalette(pal);
            QTimer::singleShot(0, view, [view] {
                QFont font = view->font();
                if (font.bold()) {
                    font.setBold(false);
                    view->setFont(font);
                }
            });
        }
        if (auto label = qobject_cast<QLabel *>(widget)) {
            const QWidget *title = label->parentWidget();
            if (title && title->inherits("KTitleWidget") && title->objectName().startsWith(QLatin1String("KPageView::TitleWidget")) && !label->wordWrap()
                && (label->textInteractionFlags() & Qt::TextSelectableByMouse)) {
                QTimer::singleShot(0, label, [label] {
                    QFont font = label->font();
                    if (font.weight() != QFont::Bold) {
                        font.setWeight(QFont::Bold);
                        label->setFont(font);
                    }
                });
            }
        }
    }

    void unpolish(QWidget *widget) override
    {
        if (isSidebarView(widget)) {
            widget->removeEventFilter(m_sidebar);
        }
        if (auto menu = qobject_cast<QMenu *>(widget)) {
            menu->removeEventFilter(m_decorator);
            return;
        }
        if (widget) {
            widget->removeEventFilter(m_textTint);
            widget->removeEventFilter(m_tint);
            if (widget->inherits("QComboBoxPrivateContainer")) {
                widget->removeEventFilter(m_decorator);
            }
        }
        QProxyStyle::unpolish(widget);
    }

    void polish(QPalette &palette) override
    {
        QProxyStyle::polish(palette);
        if (m_look.fluent) {
            return;
        }
        palette.setColor(QPalette::Inactive, QPalette::Highlight, unemphasized(palette));
        palette.setColor(QPalette::Inactive, QPalette::HighlightedText, palette.color(QPalette::Active, QPalette::Text));
    }

    int pixelMetric(PixelMetric metric, const QStyleOption *option, const QWidget *widget) const override
    {
        switch (metric) {
        case PM_MenuHMargin:
            return 0;
        case PM_MenuVMargin:
            return m_look.vMargin;
        case PM_MenuPanelWidth:
            return 0;
        case PM_SubMenuOverlap:
            return -m_look.inset;
        default:
            break;
        }
        if (!m_look.fluent) {
            switch (metric) {
            case PM_IndicatorWidth:
                return isSwitch(widget) ? SwitchWidth + 2 * Ring : QProxyStyle::pixelMetric(metric, option, widget);
            case PM_IndicatorHeight:
                return isSwitch(widget) ? SwitchHeight + 2 * Ring : QProxyStyle::pixelMetric(metric, option, widget);
            case PM_ScrollBarExtent:
                return 14;
            case PM_ScrollBarSliderMin:
                return 32;
            case PM_SliderThickness:
                return ControlHeight;
            case PM_SliderLength:
            case PM_SliderControlThickness:
                return KnobSize;
            case PM_SliderTickmarkOffset:
                return 5;
            case PM_TabBarTabHSpace:
                if (segmentedTab(option, widget)) {
                    return 28;
                }
                break;
            case PM_TabBarTabVSpace:
                if (segmentedTab(option, widget)) {
                    return 6;
                }
                break;
            case PM_TabBarBaseOverlap:
            case PM_TabBarTabShiftHorizontal:
            case PM_TabBarTabShiftVertical:
                if (segmentedTab(option, widget)) {
                    return 0;
                }
                break;
            case PM_ButtonShiftHorizontal:
            case PM_ButtonShiftVertical:
                return 0;
            default:
                break;
            }
        }
        return QProxyStyle::pixelMetric(metric, option, widget);
    }

    int styleHint(StyleHint hint, const QStyleOption *option, const QWidget *widget, QStyleHintReturn *returnData) const override
    {
        switch (hint) {
        case SH_Menu_SubMenuPopupDelay:
            return m_look.submenuDelay;
        case SH_Menu_Scrollable:
            return true;
        case SH_Menu_MouseTracking:
            return true;
        case SH_Menu_FadeOutOnHide:
            return false;
        default:
            break;
        }
        if (!m_look.fluent) {
            switch (hint) {
            case SH_DialogButtonLayout:
                return QDialogButtonBox::MacLayout;
            case SH_DialogButtonBox_ButtonsHaveIcons:
                return false;
            case SH_TabBar_Alignment:
                return Qt::AlignCenter;
            case SH_ComboBox_Popup:
                return true;
            case SH_ComboBox_AllowWheelScrolling:
                return false;
            case SH_LineEdit_PasswordCharacter:
                return 0x2022;
            case SH_ItemView_ShowDecorationSelected:
                return true;
            case SH_FocusFrame_AboveWidget:
            case SH_UnderlineShortcut:
                return false;
            default:
                break;
            }
        }
        return QProxyStyle::styleHint(hint, option, widget, returnData);
    }

    QSize sizeFromContents(ContentsType type, const QStyleOption *option, const QSize &contentsSize, const QWidget *widget) const override
    {
        if (type == CT_MenuItem) {
            if (const auto item = qstyleoption_cast<const QStyleOptionMenuItem *>(option)) {
                if (item->menuItemType == QStyleOptionMenuItem::Separator) {
                    return QSize(contentsSize.width(), item->text.isEmpty() ? m_look.separatorHeight : m_look.headerHeight);
                }
                const QFontMetrics fm(item->font);
                int width = m_look.leftPad + (hasLeadColumn(m_look, item, widget) ? m_look.iconSize + m_look.iconGap : 0)
                    + fm.horizontalAdvance(labelOf(item->text)) + m_look.rightPad;
                const QString shortcut = shortcutFor(m_look, item->text, item->font);
                if (item->reservedShortcutWidth > 0 || !shortcut.isEmpty()) {
                    width += m_look.shortcutGap + std::max(item->reservedShortcutWidth, fm.horizontalAdvance(shortcut));
                }
                if (item->menuItemType == QStyleOptionMenuItem::SubMenu) {
                    width += m_look.arrowWidth;
                }
                if (m_look.fluent) {
                    width += 2 * m_look.inset;
                }
                return QSize(std::max(width, m_look.minWidth), m_look.itemHeight);
            }
        }
        if (type == CT_MenuBarItem && m_look.fluent) {
            if (const auto item = qstyleoption_cast<const QStyleOptionMenuItem *>(option)) {
                if (item->menuItemType != QStyleOptionMenuItem::Separator) {
                    const QFontMetrics fm(item->font);
                    return QSize(fm.horizontalAdvance(labelOf(item->text)) + 20, 30);
                }
            }
        }
        if (!m_look.fluent) {
            const QSize mac = macSize(type, option, contentsSize, widget);
            if (mac.isValid()) {
                return mac;
            }
        }
        return QProxyStyle::sizeFromContents(type, option, contentsSize, widget);
    }

    QRect subElementRect(SubElement element, const QStyleOption *option, const QWidget *widget) const override
    {
        if (!m_look.fluent) {
            const QRect mac = macSubElement(element, option, widget);
            if (mac.isValid()) {
                return mac;
            }
        }
        return QProxyStyle::subElementRect(element, option, widget);
    }

    QRect subControlRect(ComplexControl control, const QStyleOptionComplex *option, SubControl sub, const QWidget *widget) const override
    {
        if (!m_look.fluent) {
            const QRect mac = macSubControl(control, option, sub, widget);
            if (mac.isValid()) {
                return mac;
            }
        }
        return QProxyStyle::subControlRect(control, option, sub, widget);
    }

    SubControl hitTestComplexControl(ComplexControl control, const QStyleOptionComplex *option, const QPoint &pos, const QWidget *widget) const override
    {
        if (!m_look.fluent && (control == CC_ComboBox || control == CC_SpinBox || control == CC_Slider || control == CC_GroupBox)) {
            return QCommonStyle::hitTestComplexControl(control, option, pos, widget);
        }
        return QProxyStyle::hitTestComplexControl(control, option, pos, widget);
    }

    void drawPrimitive(PrimitiveElement element, const QStyleOption *option, QPainter *painter, const QWidget *widget) const override
    {
        if (element == PE_PanelMenu || element == PE_FrameMenu) {
            if (!widget || widget->isWindow()) {
                if (element == PE_PanelMenu) {
                    drawMenuPanel(option, painter, widget);
                }
                return;
            }
        }
        if (element == PE_PanelItemViewItem && isSidebarView(widget) && m_sidebar->neutral()) {
            const bool selected = option->state & State_Selected;
            const bool hovered = option->state & State_MouseOver;
            if (selected || hovered) {
                QColor color = sidebarSelectionColor(option->palette);
                if (!selected) {
                    color.setAlphaF(color.alphaF() * 0.5);
                }
                painter->save();
                painter->setRenderHint(QPainter::Antialiasing);
                painter->setPen(Qt::NoPen);
                painter->setBrush(color);
                painter->drawRoundedRect(QRectF(option->rect).adjusted(0.5, 0.5, -0.5, -0.5), 6, 6);
                painter->restore();
            }
            return;
        }
        if (!m_look.fluent && drawMacPrimitive(element, option, painter, widget)) {
            return;
        }
        QProxyStyle::drawPrimitive(element, option, painter, widget);
    }

    void drawControl(ControlElement element, const QStyleOption *option, QPainter *painter, const QWidget *widget) const override
    {
        if (element == CE_MenuItem) {
            if (const auto item = qstyleoption_cast<const QStyleOptionMenuItem *>(option)) {
                drawMenuItem(item, painter, widget);
                return;
            }
        }
        if (element == CE_MenuEmptyArea) {
            return;
        }
        if (m_look.fluent && element == CE_MenuBarItem) {
            if (const auto item = qstyleoption_cast<const QStyleOptionMenuItem *>(option)) {
                drawFluentMenuBarItem(item, painter, widget);
                return;
            }
        }
        if (m_look.fluent && element == CE_MenuBarEmptyArea) {
            painter->fillRect(option->rect, option->palette.color(QPalette::Window));
            return;
        }
        if (!m_look.fluent && drawMacControl(element, option, painter, widget)) {
            return;
        }
        QProxyStyle::drawControl(element, option, painter, widget);
    }

    void drawComplexControl(ComplexControl control, const QStyleOptionComplex *option, QPainter *painter, const QWidget *widget) const override
    {
        if (!m_look.fluent && drawMacComplex(control, option, painter, widget)) {
            return;
        }
        QProxyStyle::drawComplexControl(control, option, painter, widget);
    }
private:
    static bool keyboardFocus(const QStyleOption *option)
    {
        return (option->state & State_HasFocus) && (option->state & State_KeyboardFocusChange);
    }

    static bool inDialog(const QWidget *widget)
    {
        const QWidget *window = widget ? widget->window() : nullptr;
        return window && (qobject_cast<const QDialog *>(window) || window->inherits("KPageDialog"));
    }

    static bool segmentedTab(const QStyleOption *option, const QWidget *widget)
    {
        if (const auto tab = qstyleoption_cast<const QStyleOptionTab *>(option)) {
            return (!tab->documentMode || inDialog(widget)) && (tab->shape == QTabBar::RoundedNorth || tab->shape == QTabBar::TriangularNorth);
        }
        if (const auto bar = qobject_cast<const QTabBar *>(widget)) {
            return (!bar->documentMode() || inDialog(widget)) && (bar->shape() == QTabBar::RoundedNorth || bar->shape() == QTabBar::TriangularNorth);
        }
        return false;
    }

    static bool segmentedPane(const QStyleOptionTabWidgetFrame *frame, const QWidget *widget)
    {
        const auto tabs = qobject_cast<const QTabWidget *>(widget);
        return frame && (!tabs || !tabs->documentMode() || inDialog(widget)) && (frame->shape == QTabBar::RoundedNorth || frame->shape == QTabBar::TriangularNorth)
            && frame->leftCornerWidgetSize.isEmpty() && frame->rightCornerWidgetSize.isEmpty();
    }

    static bool switchTrails(const QRect &rect, const QWidget *widget)
    {
        const auto box = qobject_cast<const QCheckBox *>(widget);
        return box && !box->text().isEmpty() && rect.width() >= box->sizeHint().width() + 48;
    }

    static bool stripIcon(const QWidget *widget)
    {
        return widget && qobject_cast<const QDialogButtonBox *>(widget->parentWidget());
    }

    static bool hostsField(const QWidget *widget)
    {
        const QWidget *parent = widget ? widget->parentWidget() : nullptr;
        return parent && (qobject_cast<const QComboBox *>(parent) || qobject_cast<const QAbstractSpinBox *>(parent));
    }

    static QPainterPath sidePath(const QRectF &rect, qreal radius, bool left, bool right)
    {
        QPainterPath path;
        const qreal l = left ? radius : 0.0;
        const qreal r = right ? radius : 0.0;
        path.moveTo(rect.left() + l, rect.top());
        path.lineTo(rect.right() - r, rect.top());
        if (r > 0) {
            path.arcTo(QRectF(rect.right() - 2 * r, rect.top(), 2 * r, 2 * r), 90, -90);
        }
        path.lineTo(rect.right(), rect.bottom() - r);
        if (r > 0) {
            path.arcTo(QRectF(rect.right() - 2 * r, rect.bottom() - 2 * r, 2 * r, 2 * r), 0, -90);
        }
        path.lineTo(rect.left() + l, rect.bottom());
        if (l > 0) {
            path.arcTo(QRectF(rect.left(), rect.bottom() - 2 * l, 2 * l, 2 * l), 270, -90);
        }
        path.lineTo(rect.left(), rect.top() + l);
        if (l > 0) {
            path.arcTo(QRectF(rect.left(), rect.top(), 2 * l, 2 * l), 180, -90);
        }
        path.closeSubpath();
        return path;
    }

    QColor disabledText(const QPalette &palette) const
    {
        return withAlpha(palette.color(QPalette::Active, QPalette::WindowText), 0.3);
    }

    QRectF switchTrack(const QRect &area) const
    {
        return QRectF(area.left() + std::floor((area.width() - SwitchWidth) / 2.0), area.top() + std::floor((area.height() - SwitchHeight) / 2.0), SwitchWidth,
                      SwitchHeight);
    }

    void drawSwitch(QPainter *painter, const QRect &area, const QStyleOption *option, const QWidget *widget) const
    {
        const Ink k = inkOf(option->palette);
        const bool on = option->state & State_On;
        const bool enabled = option->state & State_Enabled;
        qreal t = on ? 1.0 : 0.0;
        if (widget) {
            if (auto anim = widget->findChild<QVariantAnimation *>(QStringLiteral("_kwick_knob"), Qt::FindDirectChildrenOnly);
                anim && anim->state() == QAbstractAnimation::Running) {
                t = anim->currentValue().toReal();
            }
        }
        const QRectF track = switchTrack(area);
        const qreal radius = SwitchHeight / 2.0;
        painter->save();
        painter->setRenderHint(QPainter::Antialiasing, true);
        if (!enabled) {
            painter->setOpacity(0.45);
        }
        QColor fill = blend(k.track, m_accent, t);
        if (option->state & State_Sunken) {
            fill = fill.darker(108);
        }
        painter->setPen(Qt::NoPen);
        painter->setBrush(fill);
        painter->drawRoundedRect(track, radius, radius);
        if (t < 1.0) {
            painter->setBrush(Qt::NoBrush);
            painter->setPen(QPen(withAlpha(k.dark ? QColor(255, 255, 255) : QColor(0, 0, 0), (k.dark ? 0.06 : 0.05) * (1.0 - t)), 1.0));
            painter->drawRoundedRect(track.adjusted(0.5, 0.5, -0.5, -0.5), radius - 0.5, radius - 0.5);
        }
        const qreal d = SwitchHeight - 2.0;
        const QRectF knob(track.left() + 1.0 + t * (SwitchWidth - 2.0 - d), track.top() + 1.0, d, d);
        painter->setPen(Qt::NoPen);
        painter->setBrush(QColor(0, 0, 0, k.dark ? 70 : 40));
        painter->drawEllipse(knob.translated(0, 0.5).adjusted(-0.5, -0.5, 0.5, 0.5));
        painter->setBrush(k.dark ? QColor(240, 240, 240) : QColor(255, 255, 255));
        painter->drawEllipse(knob);
        painter->restore();
        if (enabled && keyboardFocus(option)) {
            drawRing(painter, track, radius, m_accent);
        }
    }

    void drawCheck(QPainter *painter, const QRect &area, const QStyleOption *option, bool radio) const
    {
        const Ink k = inkOf(option->palette);
        const int size = radio ? RadioSize : CheckSize;
        const QRectF box(area.left() + std::floor((area.width() - size) / 2.0), area.top() + std::floor((area.height() - size) / 2.0), size, size);
        const bool on = option->state & State_On;
        const bool mixed = option->state & State_NoChange;
        const bool enabled = option->state & State_Enabled;
        const bool sunken = option->state & State_Sunken;
        const qreal radius = radio ? size / 2.0 : 3.5;
        painter->save();
        painter->setRenderHint(QPainter::Antialiasing, true);
        if (!enabled) {
            painter->setOpacity(0.45);
        }
        painter->setPen(Qt::NoPen);
        if (on || mixed) {
            painter->setBrush(sunken ? m_accent.darker(112) : m_accent);
            painter->drawRoundedRect(box, radius, radius);
            if (radio) {
                painter->setBrush(QColor(255, 255, 255));
                painter->drawEllipse(box.center(), 3.0, 3.0);
            } else {
                painter->setPen(QPen(QColor(255, 255, 255), 1.75, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin));
                painter->setBrush(Qt::NoBrush);
                QPainterPath mark;
                if (mixed) {
                    mark.moveTo(box.left() + 4.0, box.top() + 7.0);
                    mark.lineTo(box.left() + 10.0, box.top() + 7.0);
                } else {
                    mark.moveTo(box.left() + 3.6, box.top() + 7.4);
                    mark.lineTo(box.left() + 6.0, box.top() + 9.8);
                    mark.lineTo(box.left() + 10.6, box.top() + 4.4);
                }
                painter->drawPath(mark);
            }
        } else {
            if (!k.dark) {
                painter->setBrush(QColor(0, 0, 0, 14));
                painter->drawRoundedRect(box.translated(0, 0.5), radius, radius);
            }
            painter->setBrush(sunken ? (k.dark ? QColor(255, 255, 255, 46) : QColor(232, 232, 232)) : k.box);
            painter->drawRoundedRect(box, radius, radius);
            painter->setBrush(Qt::NoBrush);
            painter->setPen(QPen(k.boxStroke, 1.0));
            painter->drawRoundedRect(box.adjusted(0.5, 0.5, -0.5, -0.5), radius - 0.5, radius - 0.5);
        }
        painter->restore();
        if (enabled && keyboardFocus(option)) {
            drawRing(painter, box, radius, m_accent);
        }
    }

    void drawBezel(QPainter *painter, const QRectF &bezel, const QStyleOption *option, bool primary, qreal radius = 6.0) const
    {
        const Ink k = inkOf(option->palette);
        const bool enabled = option->state & State_Enabled;
        const bool sunken = option->state & (State_Sunken | State_On);
        primary = primary && enabled && (option->state & State_Active);
        painter->save();
        painter->setRenderHint(QPainter::Antialiasing, true);
        painter->setPen(Qt::NoPen);
        painter->setBrush(primary ? QColor(0, 0, 0, k.dark ? 70 : 30) : k.shadow);
        painter->drawRoundedRect(bezel.translated(0, 1.0), radius, radius);
        QColor fill = primary ? (sunken ? m_accent.darker(115) : m_accent) : (sunken ? k.bezelPressed : k.bezel);
        if (!enabled && !k.dark) {
            fill = blend(option->palette.color(QPalette::Window), fill, 0.6);
        } else if (!enabled) {
            fill = withAlpha(fill, fill.alphaF() * 0.6);
        }
        painter->setBrush(fill);
        painter->drawRoundedRect(bezel, radius, radius);
        if (!primary) {
            painter->setBrush(Qt::NoBrush);
            painter->setPen(QPen(k.bezelStroke, 1.0));
            painter->drawRoundedRect(bezel.adjusted(0.5, 0.5, -0.5, -0.5), radius - 0.5, radius - 0.5);
        } else {
            QLinearGradient sheen(bezel.topLeft(), bezel.bottomLeft());
            sheen.setColorAt(0.0, QColor(255, 255, 255, 34));
            sheen.setColorAt(1.0, QColor(255, 255, 255, 0));
            painter->setBrush(sheen);
            painter->drawRoundedRect(bezel, radius, radius);
        }
        painter->restore();
    }

    void drawField(QPainter *painter, const QRectF &bezel, const QStyleOption *option, bool focus) const
    {
        const Ink k = inkOf(option->palette);
        const bool enabled = option->state & State_Enabled;
        const qreal radius = 5.0;
        painter->save();
        painter->setRenderHint(QPainter::Antialiasing, true);
        painter->setPen(Qt::NoPen);
        painter->setBrush(enabled ? k.field : withAlpha(k.field, k.field.alphaF() * 0.5));
        painter->drawRoundedRect(bezel, radius, radius);
        painter->setBrush(Qt::NoBrush);
        painter->setPen(QPen(enabled ? k.fieldStroke : withAlpha(k.fieldStroke, k.fieldStroke.alphaF() * 0.6), 1.0));
        painter->drawRoundedRect(bezel.adjusted(0.5, 0.5, -0.5, -0.5), radius - 0.5, radius - 0.5);
        painter->restore();
        if (enabled && focus) {
            drawRing(painter, bezel, radius, m_accent);
        }
    }

    void drawCard(QPainter *painter, const QRectF &rect, const QPalette &palette) const
    {
        const Ink k = inkOf(palette);
        painter->save();
        painter->setRenderHint(QPainter::Antialiasing, true);
        painter->setPen(Qt::NoPen);
        painter->setBrush(k.card);
        painter->drawRoundedRect(rect, 8, 8);
        painter->setBrush(Qt::NoBrush);
        painter->setPen(QPen(k.cardStroke, 1.0));
        painter->drawRoundedRect(rect.adjusted(0.5, 0.5, -0.5, -0.5), 7.5, 7.5);
        painter->restore();
    }

    QRect arrowBox(const QRect &bezel) const
    {
        return QRect(bezel.right() - 3 - ArrowBox + 1, bezel.top() + (bezel.height() - ArrowBox) / 2, ArrowBox, ArrowBox);
    }

    QRect spinField(const QStyleOptionSpinBox *spin) const
    {
        const QRect r = spin->rect;
        if (spin->buttonSymbols == QAbstractSpinBox::NoButtons) {
            return r.adjusted(Ring, Ring, -Ring, -Ring);
        }
        return r.adjusted(Ring, Ring, -(Ring + StepperWidth + 4), -Ring);
    }

    QRect spinStepper(const QStyleOptionSpinBox *spin) const
    {
        const QRect r = spin->rect;
        return QRect(r.right() - Ring - StepperWidth + 1, r.top() + (r.height() - ControlHeight) / 2, StepperWidth, ControlHeight);
    }

    QFont titleFont(const QWidget *widget) const
    {
        QFont font = widget ? widget->font() : QApplication::font();
        font.setWeight(QFont::DemiBold);
        return font;
    }

    QSize macSize(ContentsType type, const QStyleOption *option, const QSize &size, const QWidget *widget) const
    {
        switch (type) {
        case CT_PushButton: {
            const auto button = qstyleoption_cast<const QStyleOptionButton *>(option);
            if (!button || (button->features & QStyleOptionButton::Flat)) {
                return QSize();
            }
            int w = size.width();
            if (!button->icon.isNull() && !button->text.isEmpty() && stripIcon(widget)) {
                w -= button->iconSize.width() + 4;
            }
            const bool textual = !button->text.isEmpty();
            w += 2 * Ring + (textual ? 28 : 12);
            if (button->features & QStyleOptionButton::HasMenu) {
                w += ArrowBox;
            }
            if (textual) {
                w = std::max(w, 76 + 2 * Ring);
            }
            return QSize(w, std::max(ControlHeight + 2 * Ring, size.height() + 2 * Ring + 4));
        }
        case CT_CheckBox:
            if (isSwitch(widget)) {
                const int text = size.width() > 0 ? size.width() + 8 : 0;
                return QSize(text + SwitchWidth + 2 * Ring, std::max(size.height(), SwitchHeight + 2 * Ring));
            }
            return QSize();
        case CT_LineEdit: {
            const auto frame = qstyleoption_cast<const QStyleOptionFrame *>(option);
            if (!frame || frame->lineWidth <= 0 || hostsField(widget)) {
                return QSize();
            }
            return QSize(size.width() + 2 * Ring + 8, std::max(ControlHeight + 2 * Ring, size.height() + 2 * Ring + 2));
        }
        case CT_ComboBox:
            return QSize(size.width() + 2 * Ring + 10 + ArrowBox + 10, std::max(ControlHeight + 2 * Ring, size.height() + 2 * Ring + 4));
        case CT_SpinBox: {
            const auto spin = qstyleoption_cast<const QStyleOptionSpinBox *>(option);
            const int stepper = spin && spin->buttonSymbols == QAbstractSpinBox::NoButtons ? 0 : StepperWidth + 4;
            return QSize(size.width() + 2 * Ring + 10 + stepper, std::max(ControlHeight + 2 * Ring, size.height() + 2 * Ring + 2));
        }
        case CT_Slider:
            return size;
        case CT_TabBarTab:
            if (segmentedTab(option, widget)) {
                return QSize(size.width(), TabHeight);
            }
            return QSize();
        default:
            return QSize();
        }
    }

    QRect macSubElement(SubElement element, const QStyleOption *option, const QWidget *widget) const
    {
        const QRect r = option->rect;
        switch (element) {
        case SE_PushButtonContents:
            if (const auto button = qstyleoption_cast<const QStyleOptionButton *>(option); button && !(button->features & QStyleOptionButton::Flat)) {
                return r.adjusted(Ring + 8, Ring, -(Ring + 8), -Ring);
            }
            return QRect();
        case SE_CheckBoxIndicator:
            if (isSwitch(widget)) {
                const int w = SwitchWidth + 2 * Ring;
                const int h = SwitchHeight + 2 * Ring;
                const int x = switchTrails(r, widget) ? r.right() - w + 1 : r.left();
                return visualRect(option->direction, r, QRect(x, r.top() + (r.height() - h) / 2, w, h));
            }
            return QRect();
        case SE_CheckBoxContents:
            if (isSwitch(widget)) {
                const int w = SwitchWidth + 2 * Ring;
                if (switchTrails(r, widget)) {
                    return visualRect(option->direction, r, QRect(r.left(), r.top(), std::max(0, r.width() - w - 12), r.height()));
                }
                return visualRect(option->direction, r, QRect(r.left() + w + 5, r.top(), std::max(0, r.width() - w - 5), r.height()));
            }
            return QRect();
        case SE_CheckBoxClickRect:
            if (isSwitch(widget)) {
                return r;
            }
            return QRect();
        case SE_CheckBoxFocusRect:
            if (isSwitch(widget)) {
                return macSubElement(SE_CheckBoxIndicator, option, widget);
            }
            return QRect();
        case SE_LineEditContents:
            if (const auto frame = qstyleoption_cast<const QStyleOptionFrame *>(option); frame && frame->lineWidth > 0 && !hostsField(widget)) {
                return r.adjusted(Ring + 3, Ring, -(Ring + 3), -Ring);
            }
            return QRect();
        case SE_TabWidgetTabBar:
        case SE_TabWidgetTabPane:
        case SE_TabWidgetTabContents: {
            const auto frame = qstyleoption_cast<const QStyleOptionTabWidgetFrame *>(option);
            if (!segmentedPane(frame, widget)) {
                return QRect();
            }
            const QSize bar = frame->tabBarSize;
            if (element == SE_TabWidgetTabBar) {
                int w = std::min(bar.width(), r.width());
                if (const auto tabs = qobject_cast<const QTabWidget *>(widget); tabs && tabs->tabBar()) {
                    w = std::min(w, tabs->tabBar()->sizeHint().width());
                }
                return QRect(r.left() + (r.width() - w) / 2, r.top(), w, bar.height());
            }
            if (element == SE_TabWidgetTabPane) {
                return r.adjusted(0, bar.height() / 2, 0, 0);
            }
            const auto tabs = qobject_cast<const QTabWidget *>(widget);
            if (tabs && tabs->documentMode()) {
                return r.adjusted(0, bar.height() + 8, 0, 0);
            }
            return r.adjusted(10, bar.height() + 8, -10, -10);
        }
        default:
            return QRect();
        }
    }

    QRect macSubControl(ComplexControl control, const QStyleOptionComplex *option, SubControl sub, const QWidget *widget) const
    {
        const QRect r = option->rect;
        switch (control) {
        case CC_ComboBox: {
            const auto combo = qstyleoption_cast<const QStyleOptionComboBox *>(option);
            if (!combo) {
                return QRect();
            }
            const QRect bezel = r.adjusted(Ring, Ring, -Ring, -Ring);
            const QRect arrow = arrowBox(bezel);
            QRect out;
            switch (sub) {
            case SC_ComboBoxFrame:
            case SC_ComboBoxListBoxPopup:
                out = r;
                break;
            case SC_ComboBoxEditField:
                out = combo->editable ? QRect(bezel.left() + 4, bezel.top() + 1, arrow.left() - 4 - (bezel.left() + 4), bezel.height() - 2)
                                      : QRect(bezel.left() + 9, bezel.top(), arrow.left() - 6 - (bezel.left() + 9), bezel.height());
                break;
            case SC_ComboBoxArrow:
                out = combo->editable ? QRect(arrow.left() - 3, bezel.top(), bezel.right() - arrow.left() + 4, bezel.height()) : arrow;
                break;
            default:
                return QRect();
            }
            return visualRect(option->direction, r, out);
        }
        case CC_SpinBox: {
            const auto spin = qstyleoption_cast<const QStyleOptionSpinBox *>(option);
            if (!spin) {
                return QRect();
            }
            const bool buttons = spin->buttonSymbols != QAbstractSpinBox::NoButtons;
            const QRect stepper = spinStepper(spin);
            QRect out;
            switch (sub) {
            case SC_SpinBoxFrame:
                out = r;
                break;
            case SC_SpinBoxEditField:
                out = spinField(spin).adjusted(5, 1, -4, -1);
                break;
            case SC_SpinBoxUp:
                if (!buttons) {
                    return QRect();
                }
                out = QRect(stepper.left(), stepper.top(), stepper.width(), stepper.height() / 2);
                break;
            case SC_SpinBoxDown:
                if (!buttons) {
                    return QRect();
                }
                out = QRect(stepper.left(), stepper.top() + stepper.height() / 2, stepper.width(), stepper.height() - stepper.height() / 2);
                break;
            default:
                return QRect();
            }
            return visualRect(option->direction, r, out);
        }
        case CC_Slider: {
            const auto slider = qstyleoption_cast<const QStyleOptionSlider *>(option);
            if (!slider) {
                return QRect();
            }
            const bool horizontal = slider->orientation == Qt::Horizontal;
            const int tickOffset = (slider->tickPosition & QSlider::TicksAbove) ? 5 : 0;
            if (horizontal) {
                const QRect band(r.left(), r.top() + tickOffset, r.width(), ControlHeight);
                switch (sub) {
                case SC_SliderGroove:
                    return band;
                case SC_SliderHandle: {
                    const int pos = sliderPositionFromValue(slider->minimum, slider->maximum, slider->sliderPosition, r.width() - KnobSize, slider->upsideDown);
                    return visualRect(option->direction, r, QRect(r.left() + pos, band.top() + (ControlHeight - KnobSize) / 2, KnobSize, KnobSize));
                }
                case SC_SliderTickmarks:
                    return r;
                default:
                    return QRect();
                }
            }
            const QRect band(r.left() + tickOffset, r.top(), ControlHeight, r.height());
            switch (sub) {
            case SC_SliderGroove:
                return band;
            case SC_SliderHandle: {
                const int pos = sliderPositionFromValue(slider->minimum, slider->maximum, slider->sliderPosition, r.height() - KnobSize, !slider->upsideDown);
                return QRect(band.left() + (ControlHeight - KnobSize) / 2, r.top() + pos, KnobSize, KnobSize);
            }
            case SC_SliderTickmarks:
                return r;
            default:
                return QRect();
            }
        }
        case CC_GroupBox: {
            const auto group = qstyleoption_cast<const QStyleOptionGroupBox *>(option);
            if (!group) {
                return QRect();
            }
            const QFontMetrics fm(titleFont(widget));
            const bool checkable = group->subControls & SC_GroupBoxCheckBox;
            const bool titled = !group->text.isEmpty() || checkable;
            const int titleHeight = titled ? std::max(fm.height(), checkable ? CheckSize + 4 : 0) : 0;
            const QRect check = checkable ? QRect(r.left() + 2, r.top() + (titleHeight - CheckSize) / 2, CheckSize, CheckSize) : QRect();
            const int labelX = checkable ? check.right() + 7 : r.left() + 2;
            const QRect label(labelX, r.top(), fm.horizontalAdvance(group->text) + 2, titleHeight);
            const int frameTop = titled ? r.top() + titleHeight + 5 : r.top();
            const QRect frame(r.left(), frameTop, r.width(), r.bottom() - frameTop + 1);
            const bool flat = group->features & QStyleOptionFrame::Flat;
            QRect out;
            switch (sub) {
            case SC_GroupBoxCheckBox:
                out = check;
                break;
            case SC_GroupBoxLabel:
                out = label;
                break;
            case SC_GroupBoxFrame:
                out = frame;
                break;
            case SC_GroupBoxContents:
                out = flat ? frame.adjusted(0, 4, 0, 0) : frame.adjusted(10, 10, -10, -10);
                break;
            default:
                return QRect();
            }
            return visualRect(option->direction, r, out);
        }
        default:
            return QRect();
        }
    }

    bool drawMacPrimitive(PrimitiveElement element, const QStyleOption *option, QPainter *painter, const QWidget *widget) const
    {
        switch (element) {
        case PE_IndicatorCheckBox:
            if (isSwitch(widget)) {
                drawSwitch(painter, option->rect, option, widget);
            } else {
                drawCheck(painter, option->rect, option, false);
            }
            return true;
        case PE_IndicatorItemViewItemCheck:
            drawCheck(painter, option->rect, option, false);
            return true;
        case PE_IndicatorRadioButton:
            drawCheck(painter, option->rect, option, true);
            return true;
        case PE_PanelButtonCommand: {
            const auto button = qstyleoption_cast<const QStyleOptionButton *>(option);
            const bool primary = button && (button->features & QStyleOptionButton::DefaultButton);
            drawBezel(painter, QRectF(option->rect).adjusted(Ring, Ring, -Ring, -Ring), option, primary);
            return true;
        }
        case PE_FrameDefaultButton:
            return true;
        case PE_FrameFocusRect:
            if (qobject_cast<const QAbstractButton *>(widget) || qobject_cast<const QAbstractItemView *>(widget) || qobject_cast<const QGraphicsView *>(widget)
                || qobject_cast<const QComboBox *>(widget) || qobject_cast<const QSlider *>(widget) || qobject_cast<const QTabBar *>(widget)
                || (widget && qobject_cast<const QAbstractItemView *>(widget->parentWidget()))) {
                return true;
            }
            return false;
        case PE_PanelLineEdit:
        case PE_FrameLineEdit: {
            const auto frame = qstyleoption_cast<const QStyleOptionFrame *>(option);
            if (!frame) {
                return false;
            }
            if (frame->lineWidth <= 0) {
                return hostsField(widget);
            }
            drawField(painter, QRectF(option->rect).adjusted(Ring, Ring, -Ring, -Ring), option, option->state & State_HasFocus);
            return true;
        }
        case PE_PanelItemViewItem: {
            const auto item = qstyleoption_cast<const QStyleOptionViewItem *>(option);
            if (!item) {
                return false;
            }
            painter->save();
            painter->setRenderHint(QPainter::Antialiasing, true);
            if (item->backgroundBrush.style() != Qt::NoBrush) {
                painter->fillRect(item->rect, item->backgroundBrush);
            }
            const bool selected = item->state & State_Selected;
            const bool hover = (item->state & State_MouseOver) && (item->state & State_Enabled);
            if (selected || hover) {
                bool left = true;
                bool right = true;
                switch (item->viewItemPosition) {
                case QStyleOptionViewItem::Beginning:
                    right = false;
                    break;
                case QStyleOptionViewItem::Middle:
                    left = right = false;
                    break;
                case QStyleOptionViewItem::End:
                    left = false;
                    break;
                default:
                    break;
                }
                if (item->direction == Qt::RightToLeft) {
                    std::swap(left, right);
                }
                QColor fill;
                if (selected) {
                    fill = (item->state & State_Active) ? item->palette.color(QPalette::Active, QPalette::Highlight) : unemphasized(item->palette);
                } else {
                    fill = withAlpha(item->palette.color(QPalette::Active, QPalette::Text), 0.06);
                }
                painter->setPen(Qt::NoPen);
                painter->setBrush(fill);
                painter->drawPath(sidePath(QRectF(item->rect), 5.0, left, right));
            }
            painter->restore();
            return true;
        }
        case PE_FrameTabBarBase:
            if (const auto base = qstyleoption_cast<const QStyleOptionTabBarBase *>(option);
                base && (!base->documentMode || inDialog(widget)) && (base->shape == QTabBar::RoundedNorth || base->shape == QTabBar::TriangularNorth)) {
                return true;
            }
            return false;
        case PE_FrameTabWidget:
            if (const auto frame = qstyleoption_cast<const QStyleOptionTabWidgetFrame *>(option); segmentedPane(frame, widget)) {
                drawCard(painter, QRectF(option->rect), option->palette);
                return true;
            }
            return false;
        default:
            return false;
        }
    }

    bool drawMacControl(ControlElement element, const QStyleOption *option, QPainter *painter, const QWidget *widget) const
    {
        switch (element) {
        case CE_PushButtonBevel: {
            const auto button = qstyleoption_cast<const QStyleOptionButton *>(option);
            if (!button) {
                return false;
            }
            if (button->features & QStyleOptionButton::Flat) {
                const bool sunken = button->state & (State_Sunken | State_On);
                const bool hover = (button->state & State_MouseOver) && (button->state & State_Enabled);
                if (sunken || hover) {
                    painter->save();
                    painter->setRenderHint(QPainter::Antialiasing, true);
                    painter->setPen(Qt::NoPen);
                    painter->setBrush(withAlpha(option->palette.color(QPalette::Active, QPalette::WindowText), sunken ? 0.12 : 0.06));
                    painter->drawRoundedRect(QRectF(option->rect).adjusted(1, 1, -1, -1), 6, 6);
                    painter->restore();
                }
                return true;
            }
            const QRectF bezel = QRectF(option->rect).adjusted(Ring, Ring, -Ring, -Ring);
            drawBezel(painter, bezel, option, button->features & QStyleOptionButton::DefaultButton);
            if ((button->state & State_Enabled) && keyboardFocus(option)) {
                drawRing(painter, bezel, 6.0, m_accent);
            }
            return true;
        }
        case CE_PushButtonLabel: {
            const auto button = qstyleoption_cast<const QStyleOptionButton *>(option);
            if (!button) {
                return false;
            }
            const bool enabled = button->state & State_Enabled;
            const bool primary = (button->features & QStyleOptionButton::DefaultButton) && !(button->features & QStyleOptionButton::Flat) && enabled
                && (button->state & State_Active);
            QColor fg = primary ? QColor(255, 255, 255) : button->palette.color(QPalette::Active, QPalette::ButtonText);
            if (!enabled) {
                fg = disabledText(button->palette);
            }
            QRect r = button->rect;
            if (button->features & QStyleOptionButton::HasMenu) {
                drawChevron(painter, QPointF(r.right() - 5, r.center().y() + 0.5), 7.0, false, fg, 1.5);
                r.setRight(r.right() - ArrowBox);
            }
            const bool showIcon = !button->icon.isNull() && !(stripIcon(widget) && !button->text.isEmpty());
            const QFontMetrics fm = button->fontMetrics;
            const int textWidth = button->text.isEmpty() ? 0 : fm.horizontalAdvance(labelOf(button->text));
            const QSize iconSize = showIcon ? button->iconSize : QSize();
            const int total = iconSize.width() + (showIcon && textWidth ? 4 : 0) + textWidth;
            int x = r.left() + std::max(0, (r.width() - total) / 2);
            painter->save();
            if (showIcon) {
                const QIcon::Mode mode = enabled ? QIcon::Normal : QIcon::Disabled;
                button->icon.paint(painter, QRect(x, r.top() + (r.height() - iconSize.height()) / 2, iconSize.width(), iconSize.height()), Qt::AlignCenter, mode,
                                   (button->state & State_On) ? QIcon::On : QIcon::Off);
                x += iconSize.width() + 4;
            }
            if (!button->text.isEmpty()) {
                const bool mnemonics = proxy()->styleHint(SH_UnderlineShortcut, button, widget);
                painter->setPen(fg);
                painter->drawText(QRect(x, r.top(), r.right() - x + 1, r.height()),
                                  Qt::AlignLeft | Qt::AlignVCenter | Qt::TextShowMnemonic | (mnemonics ? 0 : Qt::TextHideMnemonic), button->text);
            }
            painter->restore();
            return true;
        }
        case CE_CheckBox: {
            const auto button = qstyleoption_cast<const QStyleOptionButton *>(option);
            if (!button || !isSwitch(widget)) {
                return false;
            }
            const QRect indicator = proxy()->subElementRect(SE_CheckBoxIndicator, option, widget);
            const QRect contents = proxy()->subElementRect(SE_CheckBoxContents, option, widget);
            drawSwitch(painter, indicator, option, widget);
            painter->save();
            int x = contents.left();
            if (!button->icon.isNull()) {
                const QIcon::Mode mode = (button->state & State_Enabled) ? QIcon::Normal : QIcon::Disabled;
                button->icon.paint(painter, QRect(x, contents.top() + (contents.height() - button->iconSize.height()) / 2, button->iconSize.width(),
                                                  button->iconSize.height()),
                                   Qt::AlignCenter, mode);
                x += button->iconSize.width() + 4;
            }
            if (!button->text.isEmpty()) {
                const bool mnemonics = proxy()->styleHint(SH_UnderlineShortcut, button, widget);
                painter->setPen((button->state & State_Enabled) ? button->palette.color(QPalette::Active, QPalette::WindowText) : disabledText(button->palette));
                const QRect textRect = visualRect(button->direction, contents, QRect(x, contents.top(), contents.right() - x + 1, contents.height()));
                painter->drawText(textRect, Qt::AlignLeft | Qt::AlignVCenter | Qt::TextShowMnemonic | (mnemonics ? 0 : Qt::TextHideMnemonic), button->text);
            }
            painter->restore();
            return true;
        }
        case CE_ComboBoxLabel: {
            const auto combo = qstyleoption_cast<const QStyleOptionComboBox *>(option);
            if (!combo) {
                return false;
            }
            if (combo->editable) {
                return true;
            }
            QRect edit = proxy()->subControlRect(CC_ComboBox, combo, SC_ComboBoxEditField, widget);
            painter->save();
            if (!combo->currentIcon.isNull()) {
                const QIcon::Mode mode = (combo->state & State_Enabled) ? QIcon::Normal : QIcon::Disabled;
                const QSize is = combo->iconSize;
                const QRect iconRect(edit.left(), edit.top() + (edit.height() - is.height()) / 2, is.width(), is.height());
                combo->currentIcon.paint(painter, visualRect(combo->direction, edit, iconRect), Qt::AlignCenter, mode);
                edit.setLeft(edit.left() + is.width() + 5);
            }
            painter->setPen((combo->state & State_Enabled) ? combo->palette.color(QPalette::Active, QPalette::ButtonText) : disabledText(combo->palette));
            const QString text = combo->fontMetrics.elidedText(combo->currentText, Qt::ElideRight, edit.width());
            painter->drawText(visualRect(combo->direction, combo->rect, edit), Qt::AlignLeft | Qt::AlignVCenter | Qt::TextSingleLine, text);
            painter->restore();
            return true;
        }
        case CE_TabBarTabShape: {
            const auto tab = qstyleoption_cast<const QStyleOptionTab *>(option);
            if (!tab || !segmentedTab(option, widget)) {
                return false;
            }
            const Ink k = inkOf(tab->palette);
            bool first = tab->position == QStyleOptionTab::Beginning || tab->position == QStyleOptionTab::OnlyOneTab;
            bool last = tab->position == QStyleOptionTab::End || tab->position == QStyleOptionTab::OnlyOneTab;
            if (tab->direction == Qt::RightToLeft) {
                std::swap(first, last);
            }
            const QRectF r(tab->rect);
            painter->save();
            painter->setRenderHint(QPainter::Antialiasing, true);
            painter->setPen(Qt::NoPen);
            painter->setBrush(k.segmentTrack);
            painter->drawPath(sidePath(r, 7.0, first, last));
            const bool selected = tab->state & State_Selected;
            if (selected) {
                const QRectF pill = r.adjusted(2, 2, -2, -2);
                if (!k.dark) {
                    painter->setBrush(QColor(0, 0, 0, 26));
                    painter->drawRoundedRect(pill.translated(0, 0.5).adjusted(-0.5, -0.5, 0.5, 0.5), 5.5, 5.5);
                }
                painter->setBrush((tab->state & State_Enabled) ? k.segment : withAlpha(k.segment, k.segment.alphaF() * 0.6));
                painter->drawRoundedRect(pill, 5, 5);
            } else {
                const bool nextSelected = tab->selectedPosition == (tab->direction == Qt::RightToLeft ? QStyleOptionTab::PreviousIsSelected : QStyleOptionTab::NextIsSelected);
                if (!last && !nextSelected) {
                    painter->setBrush(withAlpha(k.text, k.dark ? 0.16 : 0.14));
                    painter->drawRect(QRectF(r.right(), r.center().y() - 6.0, 1.0, 12.0));
                }
            }
            painter->restore();
            return true;
        }
        case CE_TabBarTabLabel: {
            const auto tab = qstyleoption_cast<const QStyleOptionTab *>(option);
            if (!tab || !segmentedTab(option, widget)) {
                return false;
            }
            QRect r = tab->rect;
            if (!tab->leftButtonSize.isEmpty()) {
                r.setLeft(r.left() + tab->leftButtonSize.width() + 4);
            }
            if (!tab->rightButtonSize.isEmpty()) {
                r.setRight(r.right() - tab->rightButtonSize.width() - 4);
            }
            const bool enabled = tab->state & State_Enabled;
            const QFontMetrics fm = tab->fontMetrics;
            const bool showIcon = !tab->icon.isNull();
            const QSize is = showIcon ? (tab->iconSize.isValid() ? tab->iconSize : QSize(16, 16)) : QSize();
            const int textWidth = fm.horizontalAdvance(labelOf(tab->text));
            const int total = is.width() + (showIcon && textWidth ? 5 : 0) + textWidth;
            int x = r.left() + std::max(0, (r.width() - total) / 2);
            painter->save();
            if (showIcon) {
                tab->icon.paint(painter, QRect(x, r.top() + (r.height() - is.height()) / 2, is.width(), is.height()), Qt::AlignCenter,
                                enabled ? QIcon::Normal : QIcon::Disabled);
                x += is.width() + 5;
            }
            const bool mnemonics = proxy()->styleHint(SH_UnderlineShortcut, tab, widget);
            painter->setPen(enabled ? tab->palette.color(QPalette::Active, QPalette::WindowText) : disabledText(tab->palette));
            painter->drawText(QRect(x, r.top(), r.right() - x + 1, r.height()),
                              Qt::AlignLeft | Qt::AlignVCenter | Qt::TextShowMnemonic | (mnemonics ? 0 : Qt::TextHideMnemonic), tab->text);
            painter->restore();
            return true;
        }
        case CE_ProgressBar: {
            const auto bar = qstyleoption_cast<const QStyleOptionProgressBar *>(option);
            if (!bar || !(bar->state & State_Horizontal)) {
                return false;
            }
            const Ink k = inkOf(bar->palette);
            const QRect r = bar->rect;
            const bool label = bar->textVisible && !bar->text.isEmpty();
            const int labelWidth = label ? bar->fontMetrics.horizontalAdvance(QStringLiteral("100%")) + 8 : 0;
            const QRectF groove(r.left(), r.top() + std::floor((r.height() - 6) / 2.0), r.width() - labelWidth, 6.0);
            painter->save();
            painter->setRenderHint(QPainter::Antialiasing, true);
            if (!(bar->state & State_Enabled)) {
                painter->setOpacity(0.5);
            }
            painter->setPen(Qt::NoPen);
            painter->setBrush(k.track);
            const QPainterPath track = roundedPath(groove, 3.0);
            painter->drawPath(track);
            const bool busy = bar->minimum == 0 && bar->maximum == 0;
            painter->setClipPath(track);
            painter->setBrush(m_accent);
            if (busy) {
                const qreal phase = (QDateTime::currentMSecsSinceEpoch() % 1400) / 1400.0;
                const qreal seg = groove.width() * 0.3;
                const qreal x = groove.left() - seg + phase * (groove.width() + seg);
                painter->drawRoundedRect(QRectF(x, groove.top(), seg, groove.height()), 3.0, 3.0);
                if (widget) {
                    QTimer::singleShot(33, const_cast<QWidget *>(widget), [w = const_cast<QWidget *>(widget)] {
                        w->update();
                    });
                }
            } else {
                const qreal span = std::max(1, bar->maximum - bar->minimum);
                const qreal frac = std::clamp((bar->progress - bar->minimum) / span, 0.0, 1.0);
                const qreal w = frac > 0 ? std::max(groove.height(), frac * groove.width()) : 0.0;
                const bool reversed = bar->invertedAppearance != (bar->direction == Qt::RightToLeft);
                const QRectF fill = reversed ? QRectF(groove.right() - w, groove.top(), w, groove.height()) : QRectF(groove.left(), groove.top(), w, groove.height());
                painter->drawRoundedRect(fill, 3.0, 3.0);
            }
            painter->setClipping(false);
            if (label) {
                painter->setPen(withAlpha(k.text, 0.6));
                painter->drawText(QRect(r.right() - labelWidth + 1, r.top(), labelWidth, r.height()), Qt::AlignRight | Qt::AlignVCenter, bar->text);
            }
            painter->restore();
            return true;
        }
        default:
            return false;
        }
    }

    bool drawMacComplex(ComplexControl control, const QStyleOptionComplex *option, QPainter *painter, const QWidget *widget) const
    {
        switch (control) {
        case CC_ComboBox: {
            const auto combo = qstyleoption_cast<const QStyleOptionComboBox *>(option);
            if (!combo) {
                return false;
            }
            const bool enabled = combo->state & State_Enabled;
            const QRect bezel = combo->rect.adjusted(Ring, Ring, -Ring, -Ring);
            if (combo->editable) {
                drawField(painter, QRectF(bezel), option, combo->state & State_HasFocus);
            } else if (combo->frame) {
                drawBezel(painter, QRectF(bezel), option, false);
                if (enabled && keyboardFocus(option)) {
                    drawRing(painter, QRectF(bezel), 6.0, m_accent);
                }
            }
            const QRect box = visualRect(combo->direction, combo->rect, arrowBox(bezel));
            painter->save();
            painter->setRenderHint(QPainter::Antialiasing, true);
            painter->setPen(Qt::NoPen);
            painter->setBrush(enabled ? m_accent : withAlpha(combo->palette.color(QPalette::Active, QPalette::WindowText), 0.18));
            painter->drawRoundedRect(QRectF(box), 4, 4);
            painter->restore();
            const QPointF c = QRectF(box).center();
            if (combo->editable) {
                drawChevron(painter, c + QPointF(0, 0.5), 7.0, false, QColor(255, 255, 255), 1.5);
            } else {
                drawChevron(painter, c + QPointF(0, -2.75), 6.0, true, QColor(255, 255, 255), 1.4);
                drawChevron(painter, c + QPointF(0, 2.75), 6.0, false, QColor(255, 255, 255), 1.4);
            }
            return true;
        }
        case CC_SpinBox: {
            const auto spin = qstyleoption_cast<const QStyleOptionSpinBox *>(option);
            if (!spin) {
                return false;
            }
            const QRect field = visualRect(spin->direction, spin->rect, spinField(spin));
            if (spin->frame) {
                drawField(painter, QRectF(field), option, spin->state & State_HasFocus);
            }
            if (spin->buttonSymbols == QAbstractSpinBox::NoButtons) {
                return true;
            }
            const QRect stepper = visualRect(spin->direction, spin->rect, spinStepper(spin));
            QStyleOption plain(*option);
            plain.state &= ~(State_Sunken | State_On);
            drawBezel(painter, QRectF(stepper), &plain, false, 5.0);
            const QColor ink = spin->palette.color(QPalette::Active, QPalette::ButtonText);
            const bool enabled = spin->state & State_Enabled;
            const QRect up = proxy()->subControlRect(CC_SpinBox, spin, SC_SpinBoxUp, widget);
            const QRect down = proxy()->subControlRect(CC_SpinBox, spin, SC_SpinBoxDown, widget);
            const bool sunken = spin->state & State_Sunken;
            const Ink k = inkOf(spin->palette);
            painter->save();
            painter->setRenderHint(QPainter::Antialiasing, true);
            painter->setClipPath(roundedPath(QRectF(stepper), 5.0));
            painter->setPen(Qt::NoPen);
            painter->setBrush(withAlpha(k.dark ? QColor(255, 255, 255) : QColor(0, 0, 0), 0.12));
            if (sunken && (spin->activeSubControls & SC_SpinBoxUp)) {
                painter->drawRect(up);
            }
            if (sunken && (spin->activeSubControls & SC_SpinBoxDown)) {
                painter->drawRect(down);
            }
            painter->restore();
            const bool upOn = enabled && (spin->stepEnabled & QAbstractSpinBox::StepUpEnabled);
            const bool downOn = enabled && (spin->stepEnabled & QAbstractSpinBox::StepDownEnabled);
            drawChevron(painter, QPointF(QRectF(stepper).center().x(), up.bottom() - 4.0), 6.0, true, upOn ? ink : withAlpha(ink, 0.3), 1.4);
            drawChevron(painter, QPointF(QRectF(stepper).center().x(), down.top() + 5.0), 6.0, false, downOn ? ink : withAlpha(ink, 0.3), 1.4);
            return true;
        }
        case CC_Slider: {
            const auto slider = qstyleoption_cast<const QStyleOptionSlider *>(option);
            if (!slider) {
                return false;
            }
            const Ink k = inkOf(slider->palette);
            const bool horizontal = slider->orientation == Qt::Horizontal;
            const QRect groove = proxy()->subControlRect(CC_Slider, slider, SC_SliderGroove, widget);
            const QRect handle = proxy()->subControlRect(CC_Slider, slider, SC_SliderHandle, widget);
            painter->save();
            painter->setRenderHint(QPainter::Antialiasing, true);
            if (!(slider->state & State_Enabled)) {
                painter->setOpacity(0.45);
            }
            painter->setPen(Qt::NoPen);
            const qreal half = KnobSize / 2.0;
            QRectF track;
            QRectF filled;
            if (horizontal) {
                track = QRectF(groove.left() + half - 2, QRectF(handle).center().y() - 2, groove.width() - KnobSize + 4, 4);
                const qreal cx = QRectF(handle).center().x();
                const bool fromRight = slider->upsideDown != (slider->direction == Qt::RightToLeft);
                filled = fromRight ? QRectF(cx, track.top(), track.right() - cx, 4) : QRectF(track.left(), track.top(), cx - track.left(), 4);
            } else {
                track = QRectF(QRectF(handle).center().x() - 2, groove.top() + half - 2, 4, groove.height() - KnobSize + 4);
                const qreal cy = QRectF(handle).center().y();
                filled = slider->upsideDown ? QRectF(track.left(), track.top(), 4, cy - track.top()) : QRectF(track.left(), cy, 4, track.bottom() - cy);
            }
            painter->setBrush(k.track);
            painter->drawRoundedRect(track, 2, 2);
            painter->setBrush(m_accent);
            painter->drawRoundedRect(filled, 2, 2);
            if (slider->tickPosition != QSlider::NoTicks && (slider->subControls & SC_SliderTickmarks)) {
                const int interval = slider->tickInterval > 0 ? slider->tickInterval : std::max(1, slider->pageStep);
                painter->setBrush(withAlpha(k.text, 0.35));
                const int span = (horizontal ? groove.width() : groove.height()) - KnobSize;
                for (int v = slider->minimum; v <= slider->maximum; v += interval) {
                    const int pos = sliderPositionFromValue(slider->minimum, slider->maximum, v, span, horizontal ? slider->upsideDown : !slider->upsideDown);
                    if (horizontal) {
                        const qreal x = groove.left() + half + pos - 0.5;
                        if (slider->tickPosition & QSlider::TicksBelow) {
                            painter->drawRect(QRectF(x, groove.bottom() + 2, 1, 4));
                        }
                        if (slider->tickPosition & QSlider::TicksAbove) {
                            painter->drawRect(QRectF(x, groove.top() - 5, 1, 4));
                        }
                    } else {
                        const qreal y = groove.top() + half + pos - 0.5;
                        if (slider->tickPosition & QSlider::TicksBelow) {
                            painter->drawRect(QRectF(groove.right() + 2, y, 4, 1));
                        }
                        if (slider->tickPosition & QSlider::TicksAbove) {
                            painter->drawRect(QRectF(groove.left() - 5, y, 4, 1));
                        }
                    }
                    if (v > slider->maximum - interval) {
                        break;
                    }
                }
            }
            const QRectF knob = QRectF(handle).adjusted(0.5, 0.5, -0.5, -0.5);
            painter->setBrush(QColor(0, 0, 0, k.dark ? 80 : 36));
            painter->drawEllipse(knob.translated(0, 0.5).adjusted(-0.5, -0.5, 0.5, 0.5));
            const bool pressed = (slider->state & State_Sunken) && (slider->activeSubControls & SC_SliderHandle);
            painter->setBrush(pressed ? k.knob.darker(106) : k.knob);
            painter->drawEllipse(knob);
            painter->setBrush(Qt::NoBrush);
            painter->setPen(QPen(k.knobStroke, 1.0));
            painter->drawEllipse(knob.adjusted(0.5, 0.5, -0.5, -0.5));
            painter->restore();
            if ((slider->state & State_Enabled) && keyboardFocus(option)) {
                drawRing(painter, knob, KnobSize / 2.0, m_accent);
            }
            return true;
        }
        case CC_ScrollBar: {
            const auto bar = qstyleoption_cast<const QStyleOptionSlider *>(option);
            if (!bar) {
                return false;
            }
            const bool horizontal = bar->orientation == Qt::Horizontal;
            const QRect r = bar->rect;
            const QRect slider = proxy()->subControlRect(CC_ScrollBar, bar, SC_ScrollBarSlider, widget);
            const bool pressed = (bar->state & State_Sunken) && (bar->activeSubControls & SC_ScrollBarSlider);
            const bool hover = (bar->state & State_MouseOver) || pressed;
            const QColor ink = bar->palette.color(QPalette::Active, QPalette::WindowText);
            const bool dark = darkPalette(bar->palette);
            painter->save();
            painter->setRenderHint(QPainter::Antialiasing, true);
            painter->setPen(Qt::NoPen);
            if (hover) {
                painter->setBrush(withAlpha(ink, dark ? 0.05 : 0.035));
                painter->drawRect(r);
                painter->setBrush(withAlpha(ink, dark ? 0.08 : 0.07));
                painter->drawRect(horizontal ? QRectF(r.left(), r.top(), r.width(), 1) : QRectF(r.left(), r.top(), 1, r.height()));
            }
            if ((bar->state & State_Enabled) && bar->maximum > bar->minimum && slider.isValid()) {
                const qreal thick = hover ? 8.0 : 6.0;
                QRectF thumb;
                if (horizontal) {
                    thumb = QRectF(slider.left() + 2, r.top() + (r.height() - thick) / 2.0, slider.width() - 4, thick);
                } else {
                    thumb = QRectF(r.left() + (r.width() - thick) / 2.0, slider.top() + 2, thick, slider.height() - 4);
                }
                painter->setBrush(withAlpha(dark ? QColor(255, 255, 255) : QColor(0, 0, 0), pressed ? 0.55 : hover ? 0.45 : 0.32));
                painter->drawRoundedRect(thumb, thick / 2.0, thick / 2.0);
            }
            painter->restore();
            return true;
        }
        case CC_GroupBox: {
            const auto group = qstyleoption_cast<const QStyleOptionGroupBox *>(option);
            if (!group) {
                return false;
            }
            const bool flat = group->features & QStyleOptionFrame::Flat;
            const QRect frame = proxy()->subControlRect(CC_GroupBox, group, SC_GroupBoxFrame, widget);
            if (!flat && (group->subControls & SC_GroupBoxFrame)) {
                drawCard(painter, QRectF(frame), group->palette);
            }
            if (!group->text.isEmpty() && (group->subControls & SC_GroupBoxLabel)) {
                const QRect label = proxy()->subControlRect(CC_GroupBox, group, SC_GroupBoxLabel, widget);
                painter->save();
                painter->setFont(titleFont(widget));
                painter->setPen((group->state & State_Enabled) ? group->palette.color(QPalette::Active, QPalette::WindowText) : disabledText(group->palette));
                const bool mnemonics = proxy()->styleHint(SH_UnderlineShortcut, group, widget);
                painter->drawText(label, Qt::AlignLeft | Qt::AlignVCenter | Qt::TextShowMnemonic | (mnemonics ? 0 : Qt::TextHideMnemonic), group->text);
                painter->restore();
            }
            if (group->subControls & SC_GroupBoxCheckBox) {
                QStyleOptionButton box;
                box.QStyleOption::operator=(*group);
                box.rect = proxy()->subControlRect(CC_GroupBox, group, SC_GroupBoxCheckBox, widget);
                drawCheck(painter, box.rect, &box, false);
            }
            return true;
        }
        default:
            return false;
        }
    }

    static bool isDark(const QPalette &palette)
    {
        return palette.color(QPalette::Window).lightnessF() < 0.5;
    }

    static QPalette menuPalette(const QStyleOption *option, const QWidget *widget)
    {
        return widget ? QApplication::palette(widget) : option->palette;
    }

    void drawFluentMenuPanel(const QStyleOption *option, QPainter *painter) const
    {
        painter->save();
        painter->setRenderHint(QPainter::Antialiasing, true);
        painter->setCompositionMode(QPainter::CompositionMode_Source);
        const QRectF r(option->rect);
        const bool dark = isDark(option->palette);
        QColor base = dark ? QColor(44, 44, 44) : QColor(249, 249, 249);
        base.setAlphaF(MenuDecorator::blurAvailable() ? std::min(1.0, m_look.panelAlpha + (dark ? 0.0 : 0.05)) : 1.0);
        painter->setPen(Qt::NoPen);
        painter->setBrush(base);
        painter->drawPath(panelPath(r, m_look.panelRadius));
        painter->setCompositionMode(QPainter::CompositionMode_SourceOver);
        const QColor rim = dark ? QColor(255, 255, 255, 23) : QColor(0, 0, 0, 26);
        painter->setPen(QPen(rim, 1.0));
        painter->setBrush(Qt::NoBrush);
        QPainterPath inner;
        inner.addRoundedRect(r.adjusted(0.5, 0.5, -0.5, -0.5), m_look.panelRadius - 0.5, m_look.panelRadius - 0.5);
        painter->drawPath(inner);
        painter->restore();
    }

    void drawFluentMenuBarItem(const QStyleOptionMenuItem *item, QPainter *painter, const QWidget *widget) const
    {
        painter->save();
        painter->setRenderHint(QPainter::Antialiasing, true);
        const bool dark = isDark(item->palette);
        painter->fillRect(item->rect, item->palette.color(QPalette::Window));
        const bool enabled = item->state & State_Enabled;
        const bool sunken = item->state & State_Sunken;
        const bool hot = enabled && (item->state & State_Selected);
        if (hot) {
            const QColor fill = dark ? QColor(255, 255, 255, sunken ? 11 : 15) : QColor(0, 0, 0, sunken ? 6 : 10);
            painter->setPen(Qt::NoPen);
            painter->setBrush(fill);
            painter->drawRoundedRect(QRectF(item->rect).adjusted(1.0, 2.0, -1.0, -2.0), 4.0, 4.0);
        }
        QColor fg = item->palette.color(QPalette::Active, QPalette::WindowText);
        if (!enabled) {
            fg.setAlphaF(0.36);
        }
        painter->setPen(fg);
        painter->setFont(item->font);
        const bool mnemonics = proxy()->styleHint(SH_UnderlineShortcut, item, widget);
        painter->drawText(item->rect, Qt::AlignCenter | Qt::TextShowMnemonic | (mnemonics ? 0 : Qt::TextHideMnemonic), item->text);
        painter->restore();
    }

    void drawFluentMenuItem(const QStyleOptionMenuItem *item, QPainter *painter, const QWidget *widget) const
    {
        painter->save();
        painter->setRenderHint(QPainter::Antialiasing, true);
        const QRect r = item->rect;
        const bool dark = isDark(item->palette);
        const QColor text = dark ? QColor(255, 255, 255) : QColor(0, 0, 0, 228);
        const int x0 = r.left() + m_look.inset;
        const int x1 = r.right() + 1 - m_look.inset;

        if (item->menuItemType == QStyleOptionMenuItem::Separator) {
            if (item->text.isEmpty()) {
                const QColor line = dark ? QColor(255, 255, 255, 21) : QColor(0, 0, 0, 20);
                painter->fillRect(QRectF(r.left(), r.top() + r.height() / 2, r.width(), 1.0), line);
            } else {
                QColor header = text;
                header.setAlphaF(dark ? 0.786 : 0.62);
                QFont font = item->font;
                font.setWeight(QFont::DemiBold);
                painter->setFont(font);
                painter->setPen(header);
                painter->drawText(QRect(x0 + m_look.leftPad, r.top(), x1 - x0 - m_look.leftPad - m_look.rightPad, r.height()),
                                  Qt::AlignLeft | Qt::AlignVCenter | Qt::TextSingleLine, labelOf(item->text));
            }
            painter->restore();
            return;
        }

        const bool enabled = item->state & State_Enabled;
        const bool selected = enabled && (item->state & State_Selected);
        const bool sunken = selected && (item->state & State_Sunken);
        if (selected) {
            const QColor fill = dark ? QColor(255, 255, 255, sunken ? 11 : 15) : QColor(0, 0, 0, sunken ? 6 : 10);
            painter->setPen(Qt::NoPen);
            painter->setBrush(fill);
            painter->drawRoundedRect(QRectF(x0, r.top() + m_look.itemVInset, x1 - x0, r.height() - 2 * m_look.itemVInset), m_look.radius, m_look.radius);
        }

        QColor fg = text;
        if (!enabled) {
            fg = dark ? QColor(255, 255, 255, 93) : QColor(0, 0, 0, 92);
        }
        QColor secondary = dark ? QColor(255, 255, 255, 200) : QColor(0, 0, 0, 158);
        if (!enabled) {
            secondary = fg;
        }

        int x = x0 + m_look.leftPad;
        const int cy = r.top() + r.height() / 2;
        if (hasLeadColumn(m_look, item, widget)) {
            const QRect iconRect(x, cy - m_look.iconSize / 2, m_look.iconSize, m_look.iconSize);
            if (item->checkType != QStyleOptionMenuItem::NotCheckable && item->checked) {
                if (item->checkType == QStyleOptionMenuItem::Exclusive) {
                    painter->setBrush(fg);
                    painter->setPen(Qt::NoPen);
                    painter->drawEllipse(QPointF(iconRect.center()) + QPointF(0.5, 0.5), 3.0, 3.0);
                } else {
                    QPen pen(fg, 1.25, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin);
                    painter->setPen(pen);
                    painter->setBrush(Qt::NoBrush);
                    QPainterPath check;
                    check.moveTo(iconRect.left() + 2.5, cy + 0.5);
                    check.lineTo(iconRect.left() + 6.0, cy + 4.0);
                    check.lineTo(iconRect.left() + 13.5, cy - 3.5);
                    painter->drawPath(check);
                }
            } else if (!item->icon.isNull() && drawsIcon(m_look, widget)) {
                const QIcon::Mode mode = !enabled ? QIcon::Disabled : QIcon::Normal;
                item->icon.paint(painter, iconRect, Qt::AlignCenter, mode, QIcon::Off);
            }
            x += m_look.iconSize + m_look.iconGap;
        }

        int right = x1 - m_look.rightPad;
        if (item->menuItemType == QStyleOptionMenuItem::SubMenu) {
            QPen pen(secondary, 1.0, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin);
            painter->setPen(pen);
            painter->setBrush(Qt::NoBrush);
            const qreal ax = right - 3.0;
            QPainterPath arrow;
            arrow.moveTo(ax - 2.5, cy - 4.5);
            arrow.lineTo(ax + 2.0, cy + 0.0);
            arrow.lineTo(ax - 2.5, cy + 4.5);
            painter->drawPath(arrow);
            right -= m_look.arrowWidth;
        }

        painter->setFont(item->font);
        const QFontMetrics fm(item->font);
        const QString shortcut = shortcutFor(m_look, item->text, item->font);
        if (!shortcut.isEmpty()) {
            painter->setPen(secondary);
            painter->drawText(QRect(x, r.top(), right - x, r.height()), Qt::AlignRight | Qt::AlignVCenter | Qt::TextSingleLine, shortcut);
        }
        painter->setPen(fg);
        const int labelWidth = right - x - (shortcut.isEmpty() ? 0 : fm.horizontalAdvance(shortcut) + m_look.shortcutGap);
        const QString label = fm.elidedText(labelOf(item->text), Qt::ElideRight, std::max(0, labelWidth));
        painter->drawText(QRect(x, r.top(), std::max(0, labelWidth), r.height()), Qt::AlignLeft | Qt::AlignVCenter | Qt::TextSingleLine, label);
        painter->restore();
    }

    void drawMenuPanel(const QStyleOption *option, QPainter *painter, const QWidget *widget) const
    {
        if (m_look.fluent) {
            drawFluentMenuPanel(option, painter);
            return;
        }
        painter->save();
        painter->setRenderHint(QPainter::Antialiasing, true);
        painter->setCompositionMode(QPainter::CompositionMode_Source);
        const QRectF r(option->rect);
        QColor base = menuPalette(option, widget).color(QPalette::Window);
        const bool dark = base.lightnessF() < 0.5;
        base = dark ? QColor::fromRgbF(base.redF() * 0.86, base.greenF() * 0.86, base.blueF() * 0.86) : base.lighter(103);
        base.setAlphaF(MenuDecorator::blurAvailable() ? m_look.panelAlpha : 1.0);
        painter->setPen(Qt::NoPen);
        painter->setBrush(base);
        painter->drawPath(panelPath(r, m_look.panelRadius));
        painter->setCompositionMode(QPainter::CompositionMode_SourceOver);
        QColor rim = dark ? QColor(255, 255, 255, 38) : QColor(0, 0, 0, 30);
        painter->setPen(QPen(rim, 1.0));
        painter->setBrush(Qt::NoBrush);
        QPainterPath inner;
        inner.addRoundedRect(r.adjusted(0.5, 0.5, -0.5, -0.5), m_look.panelRadius - 0.5, m_look.panelRadius - 0.5);
        painter->drawPath(inner);
        painter->restore();
    }

    void drawMenuItem(const QStyleOptionMenuItem *item, QPainter *painter, const QWidget *widget) const
    {
        if (m_look.fluent) {
            drawFluentMenuItem(item, painter, widget);
            return;
        }
        const int LeftPad = m_look.leftPad;
        const int RightPad = m_look.rightPad;
        const int Inset = m_look.inset;
        const int Radius = m_look.radius;
        const int IconSize = m_look.iconSize;
        const int IconGap = m_look.iconGap;
        const int ShortcutGap = m_look.shortcutGap;
        const int ArrowWidth = m_look.arrowWidth;
        painter->save();
        painter->setRenderHint(QPainter::Antialiasing, true);
        const QRect r = item->rect;
        const QColor text = menuPalette(item, widget).color(QPalette::Active, QPalette::WindowText);

        if (item->menuItemType == QStyleOptionMenuItem::Separator) {
            if (item->text.isEmpty()) {
                QColor line = text;
                line.setAlphaF(0.12);
                painter->fillRect(QRectF(r.left() + LeftPad - 4.0, r.top() + r.height() / 2, r.width() - 2.0 * (LeftPad - 4.0), 1.0), line);
            } else {
                QColor header = text;
                header.setAlphaF(0.5);
                QFont font = item->font;
                font.setWeight(QFont::DemiBold);
                font.setPointSizeF(font.pointSizeF() * 0.85);
                painter->setFont(font);
                painter->setPen(header);
                painter->drawText(QRect(r.left() + LeftPad, r.top(), r.width() - LeftPad - RightPad, r.height()),
                                  Qt::AlignLeft | Qt::AlignVCenter | Qt::TextSingleLine, labelOf(item->text));
            }
            painter->restore();
            return;
        }

        const bool enabled = item->state & State_Enabled;
        const bool selected = enabled && (item->state & State_Selected);
        if (selected) {
            painter->setPen(Qt::NoPen);
            painter->setBrush(m_accent);
            painter->drawRoundedRect(QRectF(r).adjusted(Inset, 0.0, -Inset, 0.0), Radius, Radius);
        }

        QColor fg = selected ? QColor(Qt::white) : text;
        if (!enabled) {
            fg.setAlphaF(0.25);
        }
        QColor secondary = fg;
        secondary.setAlphaF(selected ? 0.85 : (enabled ? 0.5 : 0.2));

        int x = r.left() + LeftPad;
        const int cy = r.top() + r.height() / 2;
        if (hasLeadColumn(m_look, item, widget)) {
            const QRect iconRect(x, cy - IconSize / 2, IconSize, IconSize);
            if (item->checkType != QStyleOptionMenuItem::NotCheckable && item->checked) {
                QPen pen(fg, 1.6, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin);
                painter->setPen(pen);
                painter->setBrush(Qt::NoBrush);
                if (item->checkType == QStyleOptionMenuItem::Exclusive && item->icon.isNull()) {
                    painter->setBrush(fg);
                    painter->setPen(Qt::NoPen);
                    painter->drawEllipse(QPointF(iconRect.center()) + QPointF(0.5, 0.5), 3.0, 3.0);
                } else {
                    QPainterPath check;
                    check.moveTo(iconRect.left() + 3.5, cy + 0.5);
                    check.lineTo(iconRect.left() + 6.5, cy + 3.5);
                    check.lineTo(iconRect.left() + 12.5, cy - 3.5);
                    painter->drawPath(check);
                }
            } else if (!item->icon.isNull() && menuShowsIcons(widget)) {
                const QIcon::Mode mode = !enabled ? QIcon::Disabled : QIcon::Normal;
                item->icon.paint(painter, iconRect, Qt::AlignCenter, mode, QIcon::Off);
            }
            x += IconSize + IconGap;
        }

        int right = r.right() - RightPad + 1;
        if (item->menuItemType == QStyleOptionMenuItem::SubMenu) {
            QPen pen(selected ? fg : secondary, 1.5, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin);
            painter->setPen(pen);
            painter->setBrush(Qt::NoBrush);
            const qreal ax = r.right() - RightPad - 1.5;
            QPainterPath arrow;
            arrow.moveTo(ax - 2.5, cy - 4.0);
            arrow.lineTo(ax + 1.5, cy + 0.0);
            arrow.lineTo(ax - 2.5, cy + 4.0);
            painter->drawPath(arrow);
            right -= ArrowWidth;
        }

        painter->setFont(item->font);
        const QString shortcut = shortcutOf(item->text, item->font);
        if (!shortcut.isEmpty()) {
            painter->setPen(secondary);
            painter->drawText(QRect(x, r.top(), right - x, r.height()), Qt::AlignRight | Qt::AlignVCenter | Qt::TextSingleLine, shortcut);
        }
        painter->setPen(fg);
        const int labelWidth = right - x - (shortcut.isEmpty() ? 0 : QFontMetrics(item->font).horizontalAdvance(shortcut) + ShortcutGap);
        const QString label = QFontMetrics(item->font).elidedText(labelOf(item->text), Qt::ElideRight, std::max(0, labelWidth));
        painter->drawText(QRect(x, r.top(), std::max(0, labelWidth), r.height()), Qt::AlignLeft | Qt::AlignVCenter | Qt::TextSingleLine, label);
        painter->restore();
    }

    Look m_look;
    QColor m_accent;
    MenuDecorator *m_decorator;
    TextTint *m_textTint;
    SidebarDecorator *m_sidebar;
    TintDecorator *m_tint;
};

}

class KwickMacStylePlugin : public QStylePlugin
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QStyleFactoryInterface_iid FILE "kwickmac.json")

public:
    QStyle *create(const QString &key) override
    {
        if (key.compare(QStringLiteral("KwickMac"), Qt::CaseInsensitive) == 0) {
            return new KwickMacStyle(MacLook);
        }
        if (key.compare(QStringLiteral("KwickFluent"), Qt::CaseInsensitive) == 0) {
            return new KwickMacStyle(FluentLook);
        }
        return nullptr;
    }
};

#include "kwickmacstyle.moc"
