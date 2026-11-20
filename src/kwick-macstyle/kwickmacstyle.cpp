#include <KWindowEffects>
#include <KWindowShadow>

#include <QEvent>
#include <QMenu>
#include <QMenuBar>
#include <QPainter>
#include <QPainterPath>
#include <QPlatformSurfaceEvent>
#include <QProxyStyle>
#include <QSettings>
#include <QStandardPaths>
#include <QStyleFactory>
#include <QStyleOptionMenuItem>
#include <QStylePlugin>
#include <QTimer>
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
    const QStringList parts = settings.value(QStringLiteral("General/AccentColor")).toStringList();
    if (parts.size() >= 3) {
        const QColor color(parts.at(0).trimmed().toInt(), parts.at(1).trimmed().toInt(), parts.at(2).trimmed().toInt());
        if (color.isValid()) {
            return color;
        }
    }
    return QColor(10, 132, 255);
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
        auto menu = qobject_cast<QMenu *>(object);
        if (!menu) {
            return false;
        }
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

    static void install(const Look &look, QMenu *menu)
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

    static void updateBlur(const Look &look, QMenu *menu)
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

class KwickMacStyle : public QProxyStyle
{
public:
    explicit KwickMacStyle(const Look &look)
        : QProxyStyle(QStyleFactory::create(QStringLiteral("Breeze")))
        , m_look(look)
        , m_accent(accentColor())
        , m_decorator(new MenuDecorator(look, this))
    {
    }

    void polish(QWidget *widget) override
    {
        if (auto menu = qobject_cast<QMenu *>(widget)) {
            menu->setAttribute(Qt::WA_TranslucentBackground);
            menu->removeEventFilter(m_decorator);
            menu->installEventFilter(m_decorator);
            if (menu->testAttribute(Qt::WA_WState_Created)) {
                MenuDecorator::install(m_look, menu);
            }
            return;
        }
        QProxyStyle::polish(widget);
    }

    void unpolish(QWidget *widget) override
    {
        if (auto menu = qobject_cast<QMenu *>(widget)) {
            menu->removeEventFilter(m_decorator);
            return;
        }
        QProxyStyle::unpolish(widget);
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
            return QProxyStyle::pixelMetric(metric, option, widget);
        }
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
            return QProxyStyle::styleHint(hint, option, widget, returnData);
        }
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
        return QProxyStyle::sizeFromContents(type, option, contentsSize, widget);
    }

    void drawPrimitive(PrimitiveElement element, const QStyleOption *option, QPainter *painter, const QWidget *widget) const override
    {
        if (element == PE_PanelMenu || element == PE_FrameMenu) {
            if (!widget || widget->isWindow()) {
                if (element == PE_PanelMenu) {
                    drawMenuPanel(option, painter);
                }
                return;
            }
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
        QProxyStyle::drawControl(element, option, painter, widget);
    }

private:
    static bool isDark(const QPalette &palette)
    {
        return palette.color(QPalette::Window).lightnessF() < 0.5;
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

    void drawMenuPanel(const QStyleOption *option, QPainter *painter) const
    {
        if (m_look.fluent) {
            drawFluentMenuPanel(option, painter);
            return;
        }
        painter->save();
        painter->setRenderHint(QPainter::Antialiasing, true);
        painter->setCompositionMode(QPainter::CompositionMode_Source);
        const QRectF r(option->rect);
        QColor base = option->palette.color(QPalette::Window);
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
        const QColor text = item->palette.color(QPalette::Active, QPalette::WindowText);

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
