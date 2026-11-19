#include <KWindowEffects>
#include <KWindowShadow>

#include <QEvent>
#include <QMenu>
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

constexpr int ItemHeight = 24;
constexpr int SeparatorHeight = 11;
constexpr int HeaderHeight = 24;
constexpr int Inset = 5;
constexpr int PanelRadius = 12;
constexpr int Radius = PanelRadius - Inset;
constexpr int VMargin = 5;
constexpr int LeftPad = 14;
constexpr int RightPad = 14;
constexpr int IconSize = 16;
constexpr int IconGap = 7;
constexpr int ShortcutGap = 28;
constexpr int ArrowWidth = 16;
constexpr int ShadowBlur = 22;
constexpr int ShadowOffset = 8;
constexpr int ShadowMargin = ShadowBlur + ShadowOffset;
constexpr qreal PanelAlpha = 0.78;

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

bool hasLeadColumn(const QStyleOptionMenuItem *item, const QWidget *widget)
{
    return item->menuHasCheckableItems || menuShowsIcons(widget);
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

QPainterPath panelPath(const QRectF &rect)
{
    QPainterPath path;
    path.addRoundedRect(rect, PanelRadius, PanelRadius);
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

QList<KWindowShadowTile::Ptr> shadowTiles(qreal dpr)
{
    static QHash<int, QList<KWindowShadowTile::Ptr>> cache;
    const int key = qRound(dpr * 100);
    if (cache.contains(key)) {
        return cache.value(key);
    }
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
        p.setBrush(QColor(0, 0, 0, 165));
        p.drawPath(panelPath(QRectF(ShadowMargin, ShadowMargin + ShadowOffset, core, core).adjusted(2, 2, -2, -2)));
    }
    image = blurredAlpha(image, qMax(1, qRound(ShadowBlur * dpr / 3.0)));
    {
        QPainter p(&image);
        p.setRenderHint(QPainter::Antialiasing);
        p.scale(dpr, dpr);
        p.setPen(QPen(QColor(0, 0, 0, 90), 1.0));
        p.setBrush(Qt::NoBrush);
        p.drawPath(panelPath(QRectF(ShadowMargin, ShadowMargin, core, core).adjusted(-0.5, -0.5, 0.5, 0.5)));
        p.setCompositionMode(QPainter::CompositionMode_DestinationOut);
        p.setPen(Qt::NoPen);
        p.setBrush(Qt::black);
        p.drawPath(panelPath(QRectF(ShadowMargin, ShadowMargin, core, core)));
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
    using QObject::QObject;

    bool eventFilter(QObject *object, QEvent *event) override
    {
        auto menu = qobject_cast<QMenu *>(object);
        if (!menu) {
            return false;
        }
        switch (event->type()) {
        case QEvent::PlatformSurface:
            if (static_cast<QPlatformSurfaceEvent *>(event)->surfaceEventType() == QPlatformSurfaceEvent::SurfaceCreated) {
                install(menu);
            }
            break;
        case QEvent::Show:
        case QEvent::Resize:
            updateBlur(menu);
            QTimer::singleShot(0, menu, [menu] {
                updateBlur(menu);
            });
            break;
        default:
            break;
        }
        return false;
    }

    static void install(QMenu *menu)
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
        const auto tiles = shadowTiles(window->devicePixelRatio());
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
        updateBlur(menu);
    }

    static void updateBlur(QMenu *menu)
    {
        QWindow *window = menu->windowHandle();
        if (!window || !blurAvailable()) {
            return;
        }
        const QRegion region(panelPath(QRectF(menu->rect())).toFillPolygon().toPolygon());
        KWindowEffects::enableBlurBehind(window, true, region);
    }

    static bool blurAvailable()
    {
        return KWindowEffects::isEffectAvailable(KWindowEffects::BlurBehind);
    }
};

class KwickMacStyle : public QProxyStyle
{
public:
    KwickMacStyle()
        : QProxyStyle(QStyleFactory::create(QStringLiteral("Breeze")))
        , m_accent(accentColor())
        , m_decorator(new MenuDecorator(this))
    {
    }

    void polish(QWidget *widget) override
    {
        if (auto menu = qobject_cast<QMenu *>(widget)) {
            menu->setAttribute(Qt::WA_TranslucentBackground);
            menu->removeEventFilter(m_decorator);
            menu->installEventFilter(m_decorator);
            if (menu->testAttribute(Qt::WA_WState_Created)) {
                MenuDecorator::install(menu);
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
            return VMargin;
        case PM_MenuPanelWidth:
            return 0;
        case PM_SubMenuOverlap:
            return -Inset;
        default:
            return QProxyStyle::pixelMetric(metric, option, widget);
        }
    }

    int styleHint(StyleHint hint, const QStyleOption *option, const QWidget *widget, QStyleHintReturn *returnData) const override
    {
        switch (hint) {
        case SH_Menu_SubMenuPopupDelay:
            return 150;
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
                    return QSize(contentsSize.width(), item->text.isEmpty() ? SeparatorHeight : HeaderHeight);
                }
                const QFontMetrics fm(item->font);
                int width = LeftPad + (hasLeadColumn(item, widget) ? IconSize + IconGap : 0) + fm.horizontalAdvance(labelOf(item->text)) + RightPad;
                const QString shortcut = shortcutOf(item->text, item->font);
                if (item->reservedShortcutWidth > 0 || !shortcut.isEmpty()) {
                    width += ShortcutGap + std::max(item->reservedShortcutWidth, fm.horizontalAdvance(shortcut));
                }
                if (item->menuItemType == QStyleOptionMenuItem::SubMenu) {
                    width += ArrowWidth;
                }
                return QSize(std::max(width, 160), ItemHeight);
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
        QProxyStyle::drawControl(element, option, painter, widget);
    }

private:
    void drawMenuPanel(const QStyleOption *option, QPainter *painter) const
    {
        painter->save();
        painter->setRenderHint(QPainter::Antialiasing, true);
        painter->setCompositionMode(QPainter::CompositionMode_Source);
        const QRectF r(option->rect);
        QColor base = option->palette.color(QPalette::Window);
        const bool dark = base.lightnessF() < 0.5;
        base = dark ? QColor::fromRgbF(base.redF() * 0.86, base.greenF() * 0.86, base.blueF() * 0.86) : base.lighter(103);
        base.setAlphaF(MenuDecorator::blurAvailable() ? PanelAlpha : 1.0);
        painter->setPen(Qt::NoPen);
        painter->setBrush(base);
        painter->drawPath(panelPath(r));
        painter->setCompositionMode(QPainter::CompositionMode_SourceOver);
        QColor rim = dark ? QColor(255, 255, 255, 38) : QColor(0, 0, 0, 30);
        painter->setPen(QPen(rim, 1.0));
        painter->setBrush(Qt::NoBrush);
        QPainterPath inner;
        inner.addRoundedRect(r.adjusted(0.5, 0.5, -0.5, -0.5), PanelRadius - 0.5, PanelRadius - 0.5);
        painter->drawPath(inner);
        painter->restore();
    }

    void drawMenuItem(const QStyleOptionMenuItem *item, QPainter *painter, const QWidget *widget) const
    {
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
        if (hasLeadColumn(item, widget)) {
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
            return new KwickMacStyle;
        }
        return nullptr;
    }
};

#include "kwickmacstyle.moc"
