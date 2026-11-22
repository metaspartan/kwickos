#pragma once

#include <QQuickImageProvider>

class Images : public QQuickImageProvider
{
public:
    Images();
    QImage requestImage(const QString &id, QSize *size, const QSize &requestedSize) override;
};
