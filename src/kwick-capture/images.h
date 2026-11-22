#pragma once

#include <QImage>
#include <QQuickImageProvider>

#include <functional>

class Images : public QQuickImageProvider
{
public:
    using Source = std::function<QImage(const QString &)>;
    explicit Images(Source source);
    QImage requestImage(const QString &id, QSize *size, const QSize &requestedSize) override;

private:
    QImage icon(const QString &name, const QColor &color, const QSize &requestedSize) const;
    Source m_source;
};
