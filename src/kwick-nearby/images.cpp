#include "images.h"

#include <QFile>
#include <QImageReader>
#include <QPainter>
#include <QPainterPath>
#include <QSvgRenderer>
#include <QUrl>

Images::Images()
    : QQuickImageProvider(QQuickImageProvider::Image)
{
}

QImage Images::requestImage(const QString &id, QSize *size, const QSize &requestedSize)
{
    QImage image;
    const QSize want = requestedSize.isValid() && !requestedSize.isEmpty() ? requestedSize : QSize(48, 48);
    if (id.startsWith(QLatin1String("icon/"))) {
        const QStringList parts = id.split(QLatin1Char('/'));
        QFile file(QStringLiteral(":/qt/qml/KwickNearby/icons/%1.svg").arg(parts.value(1)));
        if (file.open(QIODevice::ReadOnly)) {
            QByteArray svg = file.readAll();
            QColor color = QColor::fromString(QStringLiteral("#") + parts.value(2));
            if (!color.isValid()) {
                color = Qt::black;
            }
            svg.replace("#000", color.name(QColor::HexRgb).toLatin1());
            if (color.alpha() < 255) {
                svg.replace("<svg ", "<svg opacity=\"" + QByteArray::number(color.alphaF(), 'f', 3) + "\" ");
            }
            QSvgRenderer renderer(svg);
            image = QImage(want, QImage::Format_ARGB32_Premultiplied);
            image.fill(Qt::transparent);
            QPainter painter(&image);
            painter.setRenderHint(QPainter::Antialiasing);
            renderer.render(&painter);
        }
    } else if (id.startsWith(QLatin1String("thumb/"))) {
        const QString path = QUrl::fromPercentEncoding(id.mid(6).toUtf8());
        QImageReader reader(path);
        reader.setAutoTransform(true);
        const QSize original = reader.size();
        if (original.isValid() && original.width() * qint64(original.height()) < 200000000LL) {
            reader.setScaledSize(original.scaled(want * 2, Qt::KeepAspectRatioByExpanding).boundedTo(original));
        }
        const QImage src = reader.read();
        if (!src.isNull()) {
            const QImage scaled = src.scaled(want, Qt::KeepAspectRatio, Qt::SmoothTransformation).convertToFormat(QImage::Format_ARGB32_Premultiplied);
            image = QImage(scaled.size(), QImage::Format_ARGB32_Premultiplied);
            image.fill(Qt::transparent);
            QPainter painter(&image);
            painter.setRenderHint(QPainter::Antialiasing);
            QPainterPath clip;
            clip.addRoundedRect(QRectF(image.rect()), 6, 6);
            painter.setClipPath(clip);
            painter.drawImage(0, 0, scaled);
        }
    }
    if (size) {
        *size = image.size();
    }
    return image;
}
