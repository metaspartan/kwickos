#include <QPainter>
#include <QPainterPath>
#include <QProxyStyle>
#include <QSettings>
#include <QStandardPaths>
#include <QStyleFactory>
#include <QStyleOptionMenuItem>
#include <QStylePlugin>

namespace
{

constexpr int ItemHeight = 22;
constexpr int SeparatorHeight = 11;
constexpr int HeaderHeight = 24;
constexpr int Inset = 5;
constexpr int Radius = 5;
constexpr int LeftPad = 14;
constexpr int RightPad = 15;
constexpr int IconSize = 16;
constexpr int IconGap = 7;
constexpr int ShortcutGap = 28;
constexpr int ArrowWidth = 16;

QString labelOf(const QString &text)
{
    const int tab = text.indexOf(QLatin1Char('\t'));
    QString label = tab >= 0 ? text.left(tab) : text;
    label.remove(QStringLiteral("&&"));
    QString out;
    out.reserve(label.size());
    for (int i = 0; i < label.size(); ++i) {
        if (label.at(i) == QLatin1Char('&') && i + 1 < label.size()) {
            continue;
        }
        out.append(label.at(i));
    }
    return out;
}

QString shortcutOf(const QString &text)
{
    const int tab = text.indexOf(QLatin1Char('\t'));
    return tab >= 0 ? text.mid(tab + 1) : QString();
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

bool hasLeadColumn(const QStyleOptionMenuItem *item)
{
    return item->maxIconWidth > 0 || item->menuHasCheckableItems;
}

class KwickMacStyle : public QProxyStyle
{
public:
    KwickMacStyle()
        : QProxyStyle(QStyleFactory::create(QStringLiteral("Breeze")))
        , m_accent(accentColor())
    {
    }

    int pixelMetric(PixelMetric metric, const QStyleOption *option, const QWidget *widget) const override
    {
        switch (metric) {
        case PM_MenuHMargin:
            return 0;
        case PM_MenuVMargin:
            return 5;
        case PM_MenuPanelWidth:
            return 0;
        default:
            return QProxyStyle::pixelMetric(metric, option, widget);
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
                int width = LeftPad + (hasLeadColumn(item) ? IconSize + IconGap : 0) + fm.horizontalAdvance(labelOf(item->text)) + RightPad;
                const QString shortcut = shortcutOf(item->text);
                if (item->reservedShortcutWidth > 0 || !shortcut.isEmpty()) {
                    width += ShortcutGap + std::max(item->reservedShortcutWidth, fm.horizontalAdvance(shortcut));
                }
                if (item->menuItemType == QStyleOptionMenuItem::SubMenu) {
                    width += ArrowWidth;
                }
                return QSize(std::max(width, 140), ItemHeight);
            }
        }
        return QProxyStyle::sizeFromContents(type, option, contentsSize, widget);
    }

    void drawControl(ControlElement element, const QStyleOption *option, QPainter *painter, const QWidget *widget) const override
    {
        if (element == CE_MenuItem) {
            if (const auto item = qstyleoption_cast<const QStyleOptionMenuItem *>(option)) {
                drawMenuItem(item, painter);
                return;
            }
        }
        QProxyStyle::drawControl(element, option, painter, widget);
    }

private:
    void drawMenuItem(const QStyleOptionMenuItem *item, QPainter *painter) const
    {
        painter->save();
        painter->setRenderHint(QPainter::Antialiasing, true);
        const QRect r = item->rect;
        const QColor text = item->palette.color(QPalette::Active, QPalette::WindowText);

        if (item->menuItemType == QStyleOptionMenuItem::Separator) {
            if (item->text.isEmpty()) {
                QColor line = text;
                line.setAlphaF(0.12);
                painter->fillRect(QRectF(r.left() + 10.0, r.top() + r.height() / 2, r.width() - 20.0, 1.0), line);
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

        QColor fg = selected ? item->palette.color(QPalette::Active, QPalette::HighlightedText) : text;
        if (!enabled) {
            fg.setAlphaF(0.25);
        }
        QColor secondary = fg;
        secondary.setAlphaF(selected ? 0.85 : (enabled ? 0.55 : 0.2));

        int x = r.left() + LeftPad;
        const int cy = r.top() + r.height() / 2;
        if (hasLeadColumn(item)) {
            const QRect iconRect(x, cy - IconSize / 2, IconSize, IconSize);
            if (!item->icon.isNull()) {
                const QIcon::Mode mode = !enabled ? QIcon::Disabled : (selected ? QIcon::Selected : QIcon::Normal);
                const QIcon::State state = item->checked ? QIcon::On : QIcon::Off;
                item->icon.paint(painter, iconRect, Qt::AlignCenter, mode, state);
            } else if (item->checkType != QStyleOptionMenuItem::NotCheckable && item->checked) {
                QPen pen(fg, 1.6, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin);
                painter->setPen(pen);
                painter->setBrush(Qt::NoBrush);
                if (item->checkType == QStyleOptionMenuItem::Exclusive) {
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
            }
            x += IconSize + IconGap;
        }

        int right = r.right() - RightPad + 1;
        if (item->menuItemType == QStyleOptionMenuItem::SubMenu) {
            QPen pen(selected ? fg : secondary, 1.5, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin);
            painter->setPen(pen);
            painter->setBrush(Qt::NoBrush);
            const qreal ax = r.right() - 13.5;
            QPainterPath arrow;
            arrow.moveTo(ax - 2.5, cy - 4.0);
            arrow.lineTo(ax + 1.5, cy + 0.0);
            arrow.lineTo(ax - 2.5, cy + 4.0);
            painter->drawPath(arrow);
            right -= ArrowWidth;
        }

        painter->setFont(item->font);
        const QString shortcut = shortcutOf(item->text);
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
