#pragma once

#include <QQuickAsyncImageProvider>
#include <QQuickImageProvider>

class PdfProvider : public QQuickAsyncImageProvider
{
public:
    QQuickImageResponse *requestImageResponse(const QString &id, const QSize &requestedSize) override;
};

class IconProvider : public QQuickImageProvider
{
public:
    IconProvider();
    QPixmap requestPixmap(const QString &id, QSize *size, const QSize &requestedSize) override;
};

class GlyphProvider : public QQuickImageProvider
{
public:
    GlyphProvider();
    QImage requestImage(const QString &id, QSize *size, const QSize &requestedSize) override;
};
