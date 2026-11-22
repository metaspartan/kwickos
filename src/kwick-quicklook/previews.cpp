#include "previews.h"

#include <poppler-qt6.h>

#include <QFile>
#include <QIcon>
#include <QMutex>
#include <QMutexLocker>
#include <QPainter>
#include <QRunnable>
#include <QSvgRenderer>
#include <QThreadPool>
#include <QUrl>

#include <memory>

namespace
{
QMutex pdfLock;
QString pdfPath;
std::unique_ptr<Poppler::Document> pdfDoc;

QImage renderPage(const QString &file, int page, int width)
{
    QMutexLocker locker(&pdfLock);
    if (file != pdfPath || !pdfDoc) {
        pdfDoc = Poppler::Document::load(file);
        pdfPath = file;
        if (!pdfDoc) {
            return {};
        }
        pdfDoc->setRenderHint(Poppler::Document::Antialiasing, true);
        pdfDoc->setRenderHint(Poppler::Document::TextAntialiasing, true);
        pdfDoc->setRenderHint(Poppler::Document::TextHinting, true);
    }
    std::unique_ptr<Poppler::Page> p = pdfDoc->page(page);
    if (!p) {
        return {};
    }
    const QSizeF points = p->pageSizeF();
    const double dpi = points.width() > 0 ? 72.0 * width / points.width() : 96.0;
    QImage image = p->renderToImage(dpi, dpi);
    if (image.isNull()) {
        return {};
    }
    QImage out(image.size(), QImage::Format_ARGB32_Premultiplied);
    out.fill(Qt::white);
    QPainter painter(&out);
    painter.drawImage(0, 0, image);
    return out;
}

class PdfResponse : public QQuickImageResponse, public QRunnable
{
public:
    PdfResponse(const QString &file, int page, int width)
        : m_file(file)
        , m_page(page)
        , m_width(width)
    {
        setAutoDelete(false);
    }

    QQuickTextureFactory *textureFactory() const override
    {
        return QQuickTextureFactory::textureFactoryForImage(m_image);
    }

    void run() override
    {
        m_image = renderPage(m_file, m_page, m_width);
        Q_EMIT finished();
    }

private:
    QString m_file;
    int m_page;
    int m_width;
    QImage m_image;
};
}

QQuickImageResponse *PdfProvider::requestImageResponse(const QString &id, const QSize &requestedSize)
{
    const int slash = id.indexOf(QLatin1Char('/'));
    const int page = id.left(slash).toInt();
    const QString file = QUrl::fromPercentEncoding(id.mid(slash + 1).toUtf8());
    const int width = std::clamp(requestedSize.width() > 0 ? requestedSize.width() : 1200, 64, 4000);
    auto *response = new PdfResponse(file, page, width);
    QThreadPool::globalInstance()->start(response);
    return response;
}

IconProvider::IconProvider()
    : QQuickImageProvider(QQuickImageProvider::Pixmap)
{
}

QPixmap IconProvider::requestPixmap(const QString &id, QSize *size, const QSize &requestedSize)
{
    const int edge = requestedSize.width() > 0 ? requestedSize.width() : 256;
    QIcon icon = QIcon::fromTheme(id);
    if (icon.isNull()) {
        icon = QIcon::fromTheme(QStringLiteral("application-octet-stream"));
    }
    QPixmap pixmap = icon.pixmap(QSize(edge, edge));
    if (size) {
        *size = pixmap.size();
    }
    return pixmap;
}

GlyphProvider::GlyphProvider()
    : QQuickImageProvider(QQuickImageProvider::Image)
{
}

QImage GlyphProvider::requestImage(const QString &id, QSize *size, const QSize &requestedSize)
{
    const QStringList parts = id.split(QLatin1Char('/'));
    const QString name = parts.value(0);
    const QColor tint(QLatin1Char('#') + parts.value(1, QStringLiteral("ffffff")));
    const QSize edge = requestedSize.isValid() && !requestedSize.isEmpty() ? requestedSize : QSize(32, 32);
    QImage image(edge, QImage::Format_ARGB32_Premultiplied);
    image.fill(Qt::transparent);
    QSvgRenderer renderer(QStringLiteral(":/qt/qml/KwickQuickLook/icons/") + name + QStringLiteral(".svg"));
    QPainter painter(&image);
    painter.setRenderHint(QPainter::Antialiasing);
    renderer.render(&painter);
    painter.setCompositionMode(QPainter::CompositionMode_SourceIn);
    painter.fillRect(image.rect(), tint);
    painter.end();
    if (size) {
        *size = edge;
    }
    return image;
}
