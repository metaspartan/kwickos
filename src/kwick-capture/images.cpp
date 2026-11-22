#include "images.h"

#include <QFile>
#include <QPainter>
#include <QPainterPath>
#include <QSvgRenderer>

Images::Images(Source source)
    : QQuickImageProvider(QQuickImageProvider::Image)
    , m_source(std::move(source))
{
}

QImage Images::icon(const QString &name, const QColor &color, const QSize &requestedSize) const
{
    QFile file(QStringLiteral(":/qt/qml/KwickCapture/icons/%1.svg").arg(name));
    if (!file.open(QIODevice::ReadOnly)) {
        return {};
    }
    QByteArray svg = file.readAll();
    const QByteArray hex = color.name(QColor::HexRgb).toLatin1();
    svg.replace("#000", hex);
    if (color.alpha() < 255) {
        svg.replace("<svg ", "<svg opacity=\"" + QByteArray::number(color.alphaF(), 'f', 3) + "\" ");
    }
    QSvgRenderer renderer(svg);
    const QSize size = requestedSize.isValid() && !requestedSize.isEmpty() ? requestedSize : QSize(48, 48);
    QImage image(size, QImage::Format_ARGB32_Premultiplied);
    image.fill(Qt::transparent);
    QPainter painter(&image);
    painter.setRenderHint(QPainter::Antialiasing);
    renderer.render(&painter);
    return image;
}

QImage Images::requestImage(const QString &id, QSize *size, const QSize &requestedSize)
{
    QImage image;
    if (id.startsWith(QLatin1String("icon/"))) {
        const QStringList parts = id.split(QLatin1Char('/'));
        const QColor color = parts.size() > 2 ? QColor::fromString(QStringLiteral("#") + parts.at(2)) : QColor(Qt::black);
        image = icon(parts.value(1), color.isValid() ? color : QColor(Qt::black), requestedSize);
    } else if (id.startsWith(QLatin1String("thumb/"))) {
        image = m_source(id);
        if (!image.isNull()) {
            const QSize bound = requestedSize.isValid() && !requestedSize.isEmpty() ? requestedSize : QSize(440, 300);
            image = image.scaled(bound, Qt::KeepAspectRatio, Qt::SmoothTransformation).convertToFormat(QImage::Format_ARGB32_Premultiplied);
            QImage rounded(image.size(), QImage::Format_ARGB32_Premultiplied);
            rounded.fill(Qt::transparent);
            QPainter painter(&rounded);
            painter.setRenderHint(QPainter::Antialiasing);
            QPainterPath path;
            path.addRoundedRect(QRectF(rounded.rect()), 14, 14);
            painter.setPen(Qt::NoPen);
            painter.setBrush(QBrush(image));
            painter.drawPath(path);
            painter.end();
            image = rounded;
        }
    } else {
        image = m_source(id);
        if (!image.isNull() && requestedSize.isValid() && !requestedSize.isEmpty() && (image.width() > requestedSize.width() || image.height() > requestedSize.height())) {
            image = image.scaled(requestedSize, Qt::KeepAspectRatio, Qt::SmoothTransformation);
        }
    }
    if (size) {
        *size = image.size();
    }
    return image;
}
